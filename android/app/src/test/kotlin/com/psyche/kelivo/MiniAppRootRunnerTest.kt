package com.psyche.kelivo

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Test

class MiniAppRootRunnerTest {
    private val command get() = MiniAppDeviceCatalog.rootCommand("device.root.wifi.set", mapOf("enabled" to true))!!

    @Test fun dndRunsOnlyTheCatalogsFixedSuCommandForEveryMode() {
        val launched = mutableListOf<List<String>>()
        val runner = MiniAppRootRunner(launcher = { argv ->
            launched.add(argv)
            ProcessBuilder("/bin/sh", "-c", "exit 0").start()
        })
        for (mode in listOf("all", "priority", "alarms", "none")) {
            val dnd = MiniAppDeviceCatalog.rootCommand("device.root.dnd.set", mapOf("mode" to mode))!!
            assertEquals(MiniAppRootRunner.Outcome.COMPLETED, runner.execute(dnd).outcome)
            assertEquals(listOf("su", "-c", "exec '/system/bin/cmd' 'notification' 'set_dnd' '$mode'"), launched.last())
        }
        assertEquals(4, launched.size)
    }

    @Test fun drainsAndBoundsOutputWhileWaitingForActualProcessExit() {
        val runner = MiniAppRootRunner(launcher = { ProcessBuilder("/bin/sh", "-c", "printf '%05000d' 0").start() }, outputLimit = 256)
        val result = runner.execute(command)
        assertEquals(MiniAppRootRunner.Outcome.COMPLETED, result.outcome)
        assertEquals(0, result.exitCode)
        assertEquals(256, result.output.length)
        assertTrue(result.outputTruncated)
    }

    @Test fun timeoutTerminatesTheProcessAndDoesNotStrandTheNextCommand() {
        var calls = 0
        var process: Process? = null
        val runner = MiniAppRootRunner(timeoutMs = 60, launcher = {
            calls++
            ProcessBuilder("/bin/sh", "-c", if (calls == 1) "exec sleep 10" else "exit 0").start().also { process = it }
        })
        assertEquals(MiniAppRootRunner.Outcome.TIMED_OUT, runner.execute(command).outcome)
        assertFalse(process!!.isAlive)
        assertEquals(MiniAppRootRunner.Outcome.COMPLETED, runner.execute(command).outcome)
    }

    @Test fun cancellationTerminatesInFlightAndPreventsLaterLaunch() {
        val token = MiniAppRootCancellation()
        val started = CountDownLatch(1)
        val process = AtomicReference<Process>()
        val result = AtomicReference<MiniAppRootRunner.Result>()
        val runner = MiniAppRootRunner(launcher = {
            ProcessBuilder("/bin/sh", "-c", "exec sleep 10").start().also { process.set(it); started.countDown() }
        })
        val worker = Thread { result.set(runner.execute(command, token)) }
        worker.start()
        assertTrue(started.await(2, TimeUnit.SECONDS))
        token.cancel()
        worker.join(2000)
        assertFalse(worker.isAlive)
        assertFalse(process.get().isAlive)
        assertEquals(MiniAppRootRunner.Outcome.CANCELLED, result.get().outcome)
        var launched = false
        val blocked = MiniAppRootRunner(launcher = { launched = true; throw AssertionError("must not launch") })
        assertEquals(MiniAppRootRunner.Outcome.CANCELLED, blocked.execute(command, token).outcome)
        assertFalse(launched)
    }

    @Test fun refusalAndMissingSuAreDistinctFromSuccessfulExecution() {
        val denied = MiniAppRootRunner(launcher = { ProcessBuilder("/bin/sh", "-c", "printf 'Permission denied'; exit 1").start() }).execute(command)
        assertEquals(MiniAppRootRunner.Outcome.DENIED, denied.outcome)
        val absent = MiniAppRootRunner(launcher = { throw java.io.IOException("no su") }).execute(command)
        assertEquals(MiniAppRootRunner.Outcome.UNAVAILABLE, absent.outcome)
        val failed = MiniAppRootRunner(launcher = { ProcessBuilder("/bin/sh", "-c", "exit 7").start() }).execute(command)
        assertEquals(MiniAppRootRunner.Outcome.FAILED, failed.outcome)
    }
}
