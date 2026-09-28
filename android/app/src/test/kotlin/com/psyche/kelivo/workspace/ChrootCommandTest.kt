package com.psyche.kelivo.workspace

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class ChrootCommandTest {
    private fun launch(
        binds: List<BindMount> = emptyList(),
        command: String? = "echo hello",
        tag: String = "run-1",
    ) = ChrootCommand.build(
        nativeLibDir = File("/nativelib"),
        rootfsDir = File("/data/app/env/rootfs"),
        binds = binds,
        cwd = "/workspace",
        command = command,
        env = linkedMapOf("HOME" to "/root"),
        shell = "/bin/bash",
        tag = tag,
        uid = 10538,
        gid = 10538,
        appDataDir = File("/data/app"),
        suPath = "/system/bin/su",
    )

    /** The helper's argv, as `sh -c` will split the su line. */
    private fun helperArgs(launch: ProotLaunch): List<String> {
        assertEquals("/system/bin/su", launch.argv[0])
        assertEquals("-c", launch.argv[1])
        assertEquals(3, launch.argv.size)
        val line = launch.argv[2]
        assertTrue(line.startsWith("exec '/nativelib/libmoru_chroot.so' "))
        return splitShell(line.removePrefix("exec "))
    }

    @Test
    fun runsTheGuestShellThroughSuAndTheHelper() {
        val args = helperArgs(
            launch(
                binds = listOf(
                    BindMount("/data/app/files/ws", "/workspace"),
                    BindMount("/data/app/files/app", "/app", readOnly = true),
                    BindMount("/storage/emulated/0/Download", "/downloads"),
                ),
            ),
        )
        val separator = args.indexOf("--")
        assertEquals(
            listOf(
                "/nativelib/libmoru_chroot.so", "run",
                "--rootfs", "/data/app/env/rootfs",
                "--uid", "10538", "--gid", "10538",
                "--tag", "run-1",
                "--cwd", "/workspace",
                "--bind", "/data/app/files/ws", "/workspace",
                // Only the app's own writable folders get files back.
                "--fix", "/data/app/files/ws",
                "--bind-ro", "/data/app/files/app", "/app",
                "--bind", "/storage/emulated/0/Download", "/downloads",
            ),
            args.subList(0, separator),
        )
        assertEquals(
            listOf(
                "/usr/bin/env", "-i", "HOME=/root", "MORU_RUN=run-1",
                "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "LANG=C.UTF-8",
                "/bin/bash", "-lc", ProotCommand.BASH_EVAL, "kelivo", "/workspace", "echo hello",
            ),
            args.subList(separator + 1, args.size),
        )
    }

    @Test
    fun aTerminalGetsALoginShellWithTheSessionTag() {
        val args = helperArgs(launch(command = null, tag = "pty-abc"))
        assertEquals(listOf("/bin/bash", "-l"), args.takeLast(2))
        assertTrue(args.contains("MORU_RUN=pty-abc"))
        assertTrue(args.contains("TERM=xterm-256color"))
    }

    @Test
    fun aFolderThatOnlyStartsLikeTheAppsIsNotFixed() {
        val args = helperArgs(launch(binds = listOf(BindMount("/data/application", "/x"))))
        assertFalse(args.contains("--fix"))
    }

    @Test
    fun badTagsAndCwdAreRefused() {
        assertThrows(IllegalArgumentException::class.java) { launch(tag = "a b") }
        assertThrows(IllegalArgumentException::class.java) { launch(tag = "") }
        assertThrows(IllegalArgumentException::class.java) {
            ChrootCommand.build(
                nativeLibDir = File("/n"), rootfsDir = File("/r"), binds = emptyList(),
                cwd = "/a/../b", command = "x", env = emptyMap(), shell = null, tag = "t",
                uid = 1, gid = 1, appDataDir = File("/d"), suPath = "/system/bin/su",
            )
        }
    }

    @Test
    fun killProbeAndFixOwnerGoThroughSu() {
        assertEquals(
            listOf("/system/bin/su", "-c", "exec '/n/libmoru_chroot.so' 'kill' '--tag' 'run-1'"),
            ChrootCommand.killArgv(File("/n"), "run-1", "/system/bin/su"),
        )
        assertEquals(
            "exec '/n/libmoru_chroot.so' 'probe' '--rootfs' '/r'",
            ChrootCommand.probeArgv(File("/n"), File("/r"), "/system/bin/su")[2],
        )
        assertEquals(
            "exec '/n/libmoru_chroot.so' 'fixown' '--uid' '5' '--gid' '6' '/d/a' '/d/b'",
            ChrootCommand.fixOwnerArgv(File("/n"), 5, 6, listOf(File("/d/a"), File("/d/b")), "/system/bin/su")[2],
        )
    }

    @Test
    fun suIsTheFirstThatExists() {
        assertEquals("/sbin/su", ChrootCommand.suPath { it == "/sbin/su" })
        assertEquals("/system/bin/su", ChrootCommand.suPath { false })
    }

    @Test
    fun theShellLineSurvivesQuotesAndSpacesInARealShell() {
        assumeTrue(File("/bin/sh").canExecute())
        val tricky = listOf("a b", "it's", "\"q\"", "\$HOME", "`x`", "semi;colon", "")
        val process = ProcessBuilder(
            "/bin/sh", "-c", "printf '%s\\n' " + ChrootCommand.shellLine(tricky),
        ).start()
        val lines = process.inputStream.bufferedReader().readLines()
        assertEquals(0, process.waitFor())
        assertEquals(tricky, lines)
    }

    /** Splits a line of single-quoted words, as sh does for shellLine's output. */
    private fun splitShell(line: String): List<String> {
        val words = mutableListOf<String>()
        val word = StringBuilder()
        var quoted = false
        var inWord = false
        var i = 0
        while (i < line.length) {
            val c = line[i]
            when {
                quoted && c == '\'' -> quoted = false
                quoted -> word.append(c)
                c == '\'' -> { quoted = true; inWord = true }
                c == '\\' -> { word.append(line[i + 1]); i++ }
                c == ' ' -> {
                    if (inWord) words += word.toString()
                    word.clear()
                    inWord = false
                }
                else -> { word.append(c); inWord = true }
            }
            i++
        }
        if (inWord) words += word.toString()
        return words
    }
}
