package com.psyche.kelivo.workspace

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ProotArgvTest {
    @get:Rule
    val tmp = TemporaryFolder()

    @Test
    fun execArgvMatchesGoldenString() {
        val launch = ProotCommand.build(
            nativeLibDir = File("/nativelib"),
            rootfsDir = File("/data/rootfs"),
            tmpDir = File("/data/tmp"),
            binds = listOf(BindMount("/host/files", "/workspace")),
            cwd = "/workspace",
            command = "echo hello",
            env = linkedMapOf(
                "HOME" to "/root",
                "PATH" to "/bin",
            ),
            includeLibraryPath = true,
        )
        val golden =
            "/nativelib/libproot_exec.so --root-id --link2symlink --kill-on-exit --sysvipc " +
                "-r /data/rootfs -w /workspace -b /host/files:/workspace " +
                "-b /dev -b /proc -b /sys -b /proc/self/fd:/dev/fd -b /data/rootfs/tmp:/dev/shm " +
                "/usr/bin/env -i HOME=/root PATH=/bin LANG=C.UTF-8 " +
                "KELIVO_PATH=/bin " +
                "/bin/sh -lc " + ProotCommand.BASH_EVAL + " kelivo /workspace echo hello"
        val prepare = launch.argv.indexOf("KELIVO_PATH=/bin") + 1
        assertEquals(listOf("/bin/sh", "-c"), launch.argv.subList(prepare, prepare + 2))
        assertEquals(listOf("kelivo-git", "/workspace"), launch.argv.subList(prepare + 3, prepare + 5))
        assertEquals(golden, (launch.argv.take(prepare) + launch.argv.drop(prepare + 5)).joinToString(" "))
        assertEquals("/data", launch.workingDirectory.absolutePath)
        assertEquals("/nativelib/libproot_loader.so", launch.processEnv["PROOT_LOADER"])
        assertEquals("/data/tmp", launch.processEnv["PROOT_TMP_DIR"])
        assertEquals("/data/tmp", launch.processEnv["TMPDIR"])
        assertEquals("/data/tmp:/nativelib", launch.processEnv["LD_LIBRARY_PATH"])
    }

    @Test
    fun ptyArgvUsesLoginShellAndTerm() {
        val launch = ProotCommand.build(
            nativeLibDir = File("/nativelib"),
            rootfsDir = File("/data/rootfs"),
            tmpDir = File("/data/tmp"),
            binds = emptyList(),
            cwd = "/root",
            command = null,
            env = linkedMapOf("HOME" to "/root"),
            includeLibraryPath = false,
        )
        assertEquals("/bin/sh", launch.argv[launch.argv.size - 2])
        assertEquals("-l", launch.argv.last())
        assertEquals("HOME=/root", launch.argv[launch.argv.indexOf("-i") + 1])
        assertTrue(launch.argv.contains("TERM=xterm-256color"))
        assertTrue(launch.argv.contains("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"))
    }

    @Test
    fun emptyExecEnvironmentExportsGuestDefaultsToChildProcesses() {
        assumeTrue(File("/bin/bash").canExecute() && File("/usr/bin/env").canExecute())
        val launch = ProotCommand.build(
            nativeLibDir = File("/nativelib"),
            rootfsDir = File("/data/rootfs"),
            tmpDir = File("/data/tmp"),
            binds = emptyList(),
            cwd = "/",
            command = "/usr/bin/env",
            shell = "/bin/bash",
            env = mapOf(
                "GIT_CONFIG_SYSTEM" to tmp.newFile("gitconfig").absolutePath,
                "GIT_CONFIG_GLOBAL" to "/dev/null",
            ),
            includeLibraryPath = false,
        )
        val argv = launch.argv.drop(launch.argv.indexOf("/usr/bin/env")).toMutableList()
        // Run the guest shell launch on the test host without its login profiles,
        // which could mask a missing exported PATH by setting one themselves.
        argv.addAll(argv.indexOf("/bin/bash") + 1, listOf("--noprofile", "--norc"))
        val process = ProcessBuilder(argv).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        assertEquals(output, 0, process.waitFor())
        val lines = output.lineSequence().toSet()
        assertTrue(output, lines.contains("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"))
        assertTrue(output, lines.contains("HOME=/root"))
        assertTrue(output, lines.contains("LANG=C.UTF-8"))
    }

    @Test
    fun callerPathSurvivesALoginProfileThatResetsIt() {
        assumeTrue(File("/usr/bin/env").canExecute())
        // Alpine's /etc/profile sets PATH itself, dropping Moru's npm prefix
        // where the agents live; a login profile in HOME does the same here.
        val home = tmp.newFolder("home")
        File(home, ".profile").writeText("PATH=/usr/bin:/bin\n")
        File(home, ".bash_profile").writeText("PATH=/usr/bin:/bin\n")
        val bin = tmp.newFolder("npm", "bin")
        File(bin, "moru-agent").apply {
            writeText("#!/bin/sh\necho agent-found\n")
            setExecutable(true)
        }
        for (shell in listOf("/bin/sh", "/bin/bash").filter { File(it).canExecute() }) {
            val launch = ProotCommand.build(
                nativeLibDir = File("/nativelib"),
                rootfsDir = File("/data/rootfs"),
                tmpDir = File("/data/tmp"),
                binds = emptyList(),
                cwd = "/",
                command = "moru-agent; echo \"path=\$PATH\"; " +
                    "echo \"keep=\${${ProotCommand.PATH_KEEP}-unset}\"",
                shell = shell,
                env = mapOf(
                    "HOME" to home.absolutePath,
                    "PATH" to "${bin.absolutePath}:/usr/bin:/bin",
                    "GIT_CONFIG_SYSTEM" to tmp.newFile().absolutePath,
                    "GIT_CONFIG_GLOBAL" to "/dev/null",
                ),
                includeLibraryPath = false,
            )
            val argv = launch.argv.drop(launch.argv.indexOf("/usr/bin/env"))
            val process = ProcessBuilder(argv).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            assertEquals(output, 0, process.waitFor())
            val lines = output.lineSequence().toSet()
            assertTrue("$shell: $output", lines.contains("agent-found"))
            // Only what the profile dropped is added back, once, in front.
            assertTrue("$shell: $output", lines.contains("path=${bin.absolutePath}:/usr/bin:/bin"))
            assertTrue("$shell: $output", lines.contains("keep=unset"))
        }
    }

    @Test
    fun agentsRunWithoutFakeHardLinks() {
        fun argv(emulate: Boolean) = ProotCommand.build(
            File("/libs"), File("/rootfs"), File("/tmp"), emptyList(), "/root", "true",
            emptyMap(), emulateHardLinks = emulate,
        ).argv
        assertTrue(argv(true).contains("--link2symlink"))
        assertFalse(argv(false).contains("--link2symlink"))
        assertTrue(argv(false).contains("--kill-on-exit"))
    }

    @Test
    fun hiddenProcFilesGetStandInsOnlyWhenUnreadable() {
        val staged = tmp.newFolder("staged")
        ProotCommand.stageProcStandIns(staged, cpus = 4, readable = { false })
        val stat = File(staged, "proc-stat").readText()
        assertEquals(4, stat.lines().count { Regex("^cpu\\d+ ").containsMatchIn(it) })
        assertTrue(stat.startsWith("cpu  "))
        assertTrue(File(staged, "proc-vmstat").readText().contains("pgfault 0"))
        val argv = ProotCommand.build(
            File("/libs"), File("/rootfs"), staged, emptyList(), "/root", "true", emptyMap(),
        ).argv
        assertTrue(argv.contains("${File(staged, "proc-stat").absolutePath}:/proc/stat"))
        assertTrue(argv.contains("${File(staged, "proc-vmstat").absolutePath}:/proc/vmstat"))

        // A device that lets apps read them keeps the real files.
        ProotCommand.stageProcStandIns(staged, cpus = 4, readable = { true })
        assertFalse(File(staged, "proc-stat").exists())
        val real = ProotCommand.build(
            File("/libs"), File("/rootfs"), staged, emptyList(), "/root", "true", emptyMap(),
        ).argv
        assertFalse(real.any { it.endsWith(":/proc/stat") })
    }

    @Test
    fun terminalAndDefaultPathRunsDoNotCarryACallerPath() {
        for (command in listOf("echo hello", null)) {
            val launch = ProotCommand.build(
                File("/libs"), File("/rootfs"), File("/tmp"), emptyList(), "/root", command,
                mapOf("HOME" to "/root"),
            )
            assertFalse(launch.argv.any { it.startsWith("${ProotCommand.PATH_KEEP}=") })
        }
    }

    @Test
    fun readOnlyPreferenceUsesUnmodifiedProotForExecAndPty() {
        for (command in listOf("echo hello", null)) {
            val binds = listOf(BindMount("/storage/My Notes", "/mounts/Notes", true))
            validateExternalMounts(binds)
            val launch = ProotCommand.build(File("/libs"), File("/rootfs"), File("/tmp"), binds, "/workspace", command, emptyMap())
            assertEquals("/libs/libproot_exec.so", launch.argv.first())
            assertTrue(launch.argv.contains("/storage/My Notes:/mounts/Notes"))
            assertFalse(launch.argv.any { it.startsWith("--read-only") })
            assertFalse(launch.processEnv.containsKey("PROOT_NO_SECCOMP"))
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun externalMountGuestCannotEscapeMountRoot() {
        validateExternalMounts(listOf(BindMount("/storage/Notes", "/mounts/../root")))
    }

    @Test(expected = IllegalArgumentException::class)
    fun externalMountHostCannotInjectProotDelimiter() {
        validateExternalMounts(listOf(BindMount("/storage/Notes:other", "/mounts/Notes")))
    }
}
