package com.psyche.kelivo

import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class MiniAppRootCancellation {
    private val cancelled = AtomicBoolean(false)
    private val process = AtomicReference<Process?>()
    val isCancelled get() = cancelled.get()

    fun cancel() {
        cancelled.set(true)
        process.get()?.let { terminate(it) }
    }

    internal fun attach(value: Process) {
        process.set(value)
        if (isCancelled) terminate(value)
    }

    internal fun detach() { process.set(null) }

    companion object {
        internal fun terminate(process: Process) {
            try { process.destroy() } catch (_: Exception) { }
            try { process.destroyForcibly() } catch (_: Exception) { }
        }
    }
}

/** A bounded host-side runner, independent of Linux/root-shell tool settings. */
class MiniAppRootRunner(
    private val launcher: (List<String>) -> Process = { ProcessBuilder(it).redirectErrorStream(true).start() },
    private val timeoutMs: Long = 4000,
    private val outputLimit: Int = 2048,
) {
    enum class Outcome { COMPLETED, DENIED, FAILED, UNAVAILABLE, UNSUPPORTED, TIMED_OUT, CANCELLED }
    data class Result(val outcome: Outcome, val exitCode: Int? = null, val output: String = "", val outputTruncated: Boolean = false)

    fun execute(command: MiniAppRootCommand, cancellation: MiniAppRootCancellation = MiniAppRootCancellation()): Result {
        if (cancellation.isCancelled) return Result(Outcome.CANCELLED)
        val process = try { launcher(command.suArgv()) } catch (_: IOException) { return Result(Outcome.UNAVAILABLE) } catch (_: SecurityException) { return Result(Outcome.DENIED) }
        cancellation.attach(process)
        val output = java.io.ByteArrayOutputStream()
        var truncated = false
        // Always drain past the retained limit so a noisy child cannot deadlock
        // on a full pipe. A broken vendor stream cannot strand the command queue.
        fun drain(stream: java.io.InputStream): Thread = Thread {
            try {
                val buffer = ByteArray(512)
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    synchronized(output) {
                        val remaining = (outputLimit.coerceIn(1, 8192) - output.size()).coerceAtLeast(0)
                        output.write(buffer, 0, count.coerceAtMost(remaining))
                        if (count > remaining) truncated = true
                    }
                }
            } catch (_: Exception) { } finally { try { stream.close() } catch (_: Exception) { } }
        }.apply { isDaemon = true; name = "mini-app-root-output"; start() }
        val readers = listOf(drain(process.inputStream), drain(process.errorStream))
        val deadline = System.nanoTime() + timeoutMs.coerceIn(1, 10000) * 1_000_000
        var exit: Int? = null
        var outcome: Outcome? = null
        try {
            while (outcome == null) {
                if (cancellation.isCancelled) { outcome = Outcome.CANCELLED; break }
                exit = try { process.exitValue() } catch (_: IllegalThreadStateException) { null }
                if (exit != null) break
                if (System.nanoTime() >= deadline) { outcome = Outcome.TIMED_OUT; break }
                Thread.sleep(10)
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            outcome = Outcome.CANCELLED
        } finally {
            if (outcome == Outcome.TIMED_OUT || outcome == Outcome.CANCELLED) {
                MiniAppRootCancellation.terminate(process)
                // destroyForcibly requests termination asynchronously. Wait only
                // within a separate short bound so callers cannot overtake the
                // old command immediately after cancellation/timeout.
                val stopDeadline = System.nanoTime() + 200_000_000
                while (System.nanoTime() < stopDeadline) {
                    try { process.exitValue(); break } catch (_: IllegalThreadStateException) { }
                    try { Thread.sleep(2) } catch (_: InterruptedException) { Thread.currentThread().interrupt(); break }
                }
            }
            cancellation.detach()
            for (reader in readers) {
                try { reader.join(100) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
            }
        }
        val retained = synchronized(output) { output.toString(StandardCharsets.UTF_8.name()) }
        val normalized = retained.lowercase()
        if (outcome == null) outcome = when {
            exit == 0 -> Outcome.COMPLETED
            normalized.contains("permission denied") || normalized.contains("not allowed") || normalized.contains("denied by") -> Outcome.DENIED
            exit == 126 || exit == 127 || normalized.contains("unknown command") || normalized.contains("not found") -> Outcome.UNSUPPORTED
            else -> Outcome.FAILED
        }
        return Result(outcome, exit, retained, truncated)
    }
}
