package com.psyche.kelivo.workspace

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GitSafeDirectoryTest {
    @get:Rule
    val tmp = TemporaryFolder()

    @Test
    fun guestCommandsTrustOnlyTheWorkspaceDespiteDifferentOwnership() {
        val config = tmp.newFile("gitconfig")
        val workspace = repository("workspace", config)
        val outside = repository("outside", config)
        File(workspace, "note.txt").writeText("workspace change")
        assertDubiousOwner(git(config, workspace, "status", "--porcelain", differentOwner = true))

        val result = guest(config, workspace, "git status --porcelain")

        assertEquals(result.output, 0, result.exitCode)
        assertEquals("?? note.txt\n", result.output)
        assertDubiousOwner(git(config, outside, "status", "--porcelain", differentOwner = true))
    }

    @Test
    fun terminalPreparationPreservesSettingsAndDoesNotDuplicateWorkspaceTrust() {
        val config = tmp.newFile("gitconfig")
        config.writeText("[user]\n\temail = user@example.com\n[safe]\n\tdirectory = /user/shared\n")
        val workspace = repository("workspace", config)
        File(workspace, "note.txt").writeText("terminal change")

        repeat(2) {
            val result = guest(config, workspace, null, "git status --porcelain\nexit \"\$?\"\n")
            assertEquals(result.output, 0, result.exitCode)
            assertEquals("?? note.txt\n", result.output)
        }

        assertEquals("user@example.com\n", git(config, workspace, "config", "--system", "user.email").output)
        assertEquals(
            "/user/shared\n${workspace.absolutePath}\n",
            git(config, workspace, "config", "--system", "--get-all", "safe.directory").output,
        )
    }

    @Test
    fun workspaceTrustIsRestoredAfterAnExistingSystemConfigReset() {
        val config = tmp.newFile("gitconfig")
        val workspace = repository("workspace", config)
        config.writeText("[safe]\n\tdirectory = ${workspace.absolutePath}\n\tdirectory =\n")

        val result = guest(config, workspace, "git status --porcelain")

        assertEquals(result.output, 0, result.exitCode)
    }

    @Test
    fun failedSystemConfigWriteStopsTheOriginalCommand() {
        val config = tmp.newFolder("not-a-config-file")
        val workspace = tmp.newFolder("workspace")
        val result = guest(config, workspace, "touch command-ran")

        assertNotEquals(result.output, 0, result.exitCode)
        assertTrue(result.output, !File(workspace, "command-ran").exists())
    }

    @Test
    fun concurrentPreparationWaitsForTheSystemConfigWriter() {
        val config = tmp.newFile("gitconfig")
        val workspace = repository("workspace", config)
        val lock = File(config.path + ".lock").also { it.writeText("held by another writer") }
        val barrier = File(tmp.root, "writer-failed")
        assertEquals(0, ProcessBuilder("/usr/bin/mkfifo", barrier.path).start().waitFor())
        val bin = tmp.newFolder("git-barrier")
        File(bin, "git").apply {
            writeText("""
                #!/bin/sh
                /usr/bin/git "${'$'}@"
                result=${'$'}?
                if [ "${'$'}1" = config ] && [ "${'$'}3" = --add ] && [ "${'$'}result" -ne 0 ]; then
                  printf 'contended' > "${'$'}MORU_BARRIER"
                fi
                exit "${'$'}result"
            """.trimIndent() + "\n")
            assertTrue(setExecutable(true))
        }
        val observed = CompletableFuture.supplyAsync { barrier.inputStream().bufferedReader().use { it.readText() } }
        val result = guest(config, workspace, "git status --porcelain",
            env = mapOf("PATH" to "${bin.path}:/usr/bin:/bin", "MORU_BARRIER" to barrier.path),
            afterStart = { process ->
                try {
                    assertEquals("contended", observed.get(5, TimeUnit.SECONDS))
                    assertTrue(lock.delete())
                } catch (error: Throwable) { process.destroyForcibly(); throw error }
            })
        assertEquals(result.output, 0, result.exitCode)
        assertEquals("${workspace.path}\n", git(config, workspace, "config", "--system", "--get-all", "safe.directory").output)
    }

    @Test
    fun preparationPreservesTheCommandEnvironmentAndExitCode() {
        val config = tmp.newFile("gitconfig")
        val workspace = tmp.newFolder("workspace")
        val result = guest(config, workspace, "printf '%s\\n' \"\$MORU_CHECK\"; exit 37",
            env = mapOf("MORU_CHECK" to "value with spaces and 'quotes'"))

        assertEquals("value with spaces and 'quotes'\n", result.output)
        assertEquals(37, result.exitCode)
    }

    @Test
    fun aGuestWithoutGitCanStillRunCommandsBeforeGitIsInstalled() {
        val config = tmp.newFile("gitconfig")
        val workspace = tmp.newFolder("workspace")
        val bin = tmp.newFolder("without-git")
        // The host login profile calls id; leave that available while Git is absent.
        Files.createSymbolicLink(File(bin, "id").toPath(), File("/usr/bin/id").toPath())
        val result = guest(config, workspace, "printf ready", env = mapOf("PATH" to bin.path))

        assertEquals(result.output, 0, result.exitCode)
        assertEquals("ready", result.output)
    }

    private fun repository(name: String, config: File): File = tmp.newFolder(name).also {
        val initialized = git(config, it, "init", "--quiet")
        assertEquals(initialized.output, 0, initialized.exitCode)
    }

    private fun guest(config: File, workspace: File, command: String?, stdin: String = "", env: Map<String, String> = emptyMap(), afterStart: (Process) -> Unit = {}): Result {
        val argv = ProotCommand.guestCommand(
            rootfsDir = tmp.newFolder(),
            cwd = "/workspace",
            command = command,
            env = environment(config) + ("GIT_TEST_ASSUME_DIFFERENT_OWNER" to "1") + env,
            shell = "/bin/sh",
        )
        // Run the real guest launch on the host; translate the bound guest path
        // to its temporary host directory without needing root or PRoot.
        if (command != null) assertTrue(argv.contains("/workspace"))
        return run(argv.map { if (it == "/workspace") workspace.absolutePath else it }, workspace, stdin, afterStart = afterStart)
    }

    private fun git(config: File, cwd: File, vararg args: String, differentOwner: Boolean = false): Result =
        run(listOf("/usr/bin/git") + args, cwd, env = environment(config) +
            if (differentOwner) mapOf("GIT_TEST_ASSUME_DIFFERENT_OWNER" to "1") else emptyMap())

    private fun environment(config: File): Map<String, String> = mapOf(
        "HOME" to tmp.root.absolutePath,
        "PATH" to "/usr/bin:/bin",
        "GIT_CONFIG_SYSTEM" to config.absolutePath,
        "GIT_CONFIG_GLOBAL" to "/dev/null",
    )

    private fun run(argv: List<String>, cwd: File, stdin: String = "", env: Map<String, String> = emptyMap(), afterStart: (Process) -> Unit = {}): Result {
        val builder = ProcessBuilder(argv).directory(cwd).redirectErrorStream(true)
        builder.environment().clear()
        builder.environment().putAll(env)
        val process = builder.start()
        afterStart(process)
        process.outputStream.bufferedWriter().use { it.write(stdin) }
        val output = process.inputStream.bufferedReader().use { it.readText() }
        return Result(process.waitFor(), output)
    }

    private fun assertDubiousOwner(result: Result) {
        // This is Git's own deterministic ownership hook, used in upstream
        // t/t0033-safe-directory.sh; no chown, sudo or test skips are needed.
        assertEquals(result.output, 128, result.exitCode)
        assertTrue(result.output, result.output.contains("dubious ownership"))
    }

    private data class Result(val exitCode: Int, val output: String)
}
