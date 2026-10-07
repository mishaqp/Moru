package com.psyche.kelivo.workspace

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RootfsProfileTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun path(startPath: String): String {
        val rootfs = tmp.newFolder()
        RootfsProfile.ensureInstalled(rootfs)
        val process = ProcessBuilder(
            "/bin/sh", "-c", ". \"$1\"; printf '%s' \"\$PATH\"", "sh",
            File(rootfs, RootfsProfile.FILE).absolutePath,
        ).apply { environment()["PATH"] = startPath }.start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        assertEquals(0, process.waitFor())
        return output
    }

    @Test
    fun agentsJoinTheProfilePathOnce() {
        assumeTrue(File("/bin/sh").canExecute())
        // Alpine's /etc/profile sets exactly this before sourcing profile.d.
        assertEquals(
            "/root/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            path("/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"),
        )
        assertEquals("/usr/bin:/root/.npm-global/bin:/bin", path("/usr/bin:/root/.npm-global/bin:/bin"))
    }

    @Test
    fun anUnchangedFileIsNotRewritten() {
        val rootfs = tmp.newFolder()
        RootfsProfile.ensureInstalled(rootfs)
        val file = File(rootfs, RootfsProfile.FILE)
        file.setLastModified(1_000L)
        RootfsProfile.ensureInstalled(rootfs)
        assertEquals(1_000L, file.lastModified())
    }
}
