package com.psyche.kelivo.workspace

import java.io.File
import java.util.concurrent.TimeUnit

/**
 * The fast mode: the Linux environment in a real chroot through `su` and the
 * bundled helper (cpp/moru_chroot.c) instead of PRoot. The command runs as
 * root in the rootfs; files it leaves under the app's own binds go back to
 * the app when it exits.
 */
object ChrootCommand {
    const val HELPER_LIB = "libmoru_chroot.so"

    /** The helper's exit code when the chroot could not be set up. */
    const val SETUP_FAILED = 125

    private val suCandidates = listOf(
        "/system/bin/su",
        "/system/xbin/su",
        "/sbin/su",
        "/debug_ramdisk/su",
    )

    /** KernelSU and Magisk both provide /system/bin/su to granted apps. */
    fun suPath(exists: (String) -> Boolean = { File(it).exists() }): String =
        suCandidates.firstOrNull(exists) ?: suCandidates.first()

    /** [args] as one `sh -c` string, each argument single-quoted. */
    fun shellLine(args: List<String>): String = args.joinToString(" ") { arg ->
        require(!arg.contains('\u0000')) { "argument contains a NUL byte" }
        "'" + arg.replace("'", "'\\''") + "'"
    }

    private fun su(nativeLibDir: File, suPath: String, helperArgs: List<String>): List<String> =
        listOf(
            suPath,
            "-c",
            "exec " + shellLine(listOf(File(nativeLibDir, HELPER_LIB).absolutePath) + helperArgs),
        )

    /**
     * Runs [command] (a terminal when null) in the rootfs as root. [tag]
     * marks every process of the run for [killArgv]. Root-owned files left
     * under writable binds inside [appDataDir] go back to [uid]:[gid].
     */
    fun build(
        nativeLibDir: File,
        rootfsDir: File,
        binds: List<BindMount>,
        cwd: String,
        command: String?,
        env: Map<String, String>,
        shell: String?,
        tag: String,
        uid: Int,
        gid: Int,
        appDataDir: File,
        suPath: String = suPath(),
    ): ProotLaunch {
        val guestCwd = ProotCommand.validateGuestCwd(cwd)
        require(tag.matches(Regex("[A-Za-z0-9._-]{1,128}"))) { "invalid run tag" }
        val args = mutableListOf(
            "run",
            "--rootfs", rootfsDir.absolutePath,
            "--uid", uid.toString(),
            "--gid", gid.toString(),
            "--tag", tag,
            "--cwd", guestCwd,
        )
        val appData = appDataDir.absolutePath.trimEnd('/') + "/"
        for (bind in binds) {
            if (bind.host.isBlank() || bind.guest.isBlank()) continue
            args += listOf(if (bind.readOnly) "--bind-ro" else "--bind", bind.host, bind.guest)
            if (!bind.readOnly && (bind.host.trimEnd('/') + "/").startsWith(appData)) {
                args += listOf("--fix", bind.host)
            }
        }
        args += "--"
        // env -i clears the helper's environment: the tag goes in again.
        args += ProotCommand.guestCommand(
            rootfsDir, guestCwd, command, env + ("MORU_RUN" to tag), shell,
        )
        return ProotLaunch(
            argv = su(nativeLibDir, suPath, args),
            processEnv = linkedMapOf("PATH" to "/system/bin:/system/xbin"),
            workingDirectory = rootfsDir.parentFile ?: rootfsDir,
        )
    }

    /** Kills every process of the run [tag]. */
    fun killArgv(nativeLibDir: File, tag: String, suPath: String = suPath()): List<String> =
        su(nativeLibDir, suPath, listOf("kill", "--tag", tag))

    /** Checks root, a private mount namespace and the rootfs. */
    fun probeArgv(nativeLibDir: File, rootfsDir: File, suPath: String = suPath()): List<String> =
        su(nativeLibDir, suPath, listOf("probe", "--rootfs", rootfsDir.absolutePath))

    /** Gives root-owned files under [dirs] back to [uid]:[gid]. */
    fun fixOwnerArgv(
        nativeLibDir: File,
        uid: Int,
        gid: Int,
        dirs: List<File>,
        suPath: String = suPath(),
    ): List<String> = su(
        nativeLibDir,
        suPath,
        listOf("fixown", "--uid", uid.toString(), "--gid", gid.toString()) +
            dirs.map { it.absolutePath },
    )

    /** Runs a short root command: its exit code and output, or a timeout. */
    fun runRoot(argv: List<String>, timeoutSeconds: Long): RootResult {
        val process = ProcessBuilder(argv).redirectErrorStream(true).start()
        try {
            process.outputStream.close()
        } catch (_: Exception) {
        }
        val output = StringBuilder()
        val reader = Thread({
            try {
                output.append(process.inputStream.bufferedReader().readText())
            } catch (_: Exception) {
            }
        }, "ws-root").apply { isDaemon = true; start() }
        val finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS)
        if (!finished) {
            process.destroyForcibly()
            return RootResult(exitCode = -1, output = "timed out", timedOut = true)
        }
        reader.join(1000)
        return RootResult(exitCode = process.exitValue(), output = output.toString().trim())
    }
}

data class RootResult(
    val exitCode: Int,
    val output: String,
    val timedOut: Boolean = false,
)
