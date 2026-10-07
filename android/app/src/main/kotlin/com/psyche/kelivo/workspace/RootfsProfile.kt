package com.psyche.kelivo.workspace

import java.io.File

/**
 * Puts the coding agents Moru installs (Settings → Agents, npm prefix
 * /root/.npm-global, see AcpAgentSpec) on the terminal's PATH. Every login
 * shell of Alpine, Debian and Ubuntu sources the scripts in /etc/profile.d after
 * setting its own PATH, so `claude`, `kimi` or `opencode` work in the
 * terminal whichever distribution is installed.
 */
object RootfsProfile {
    const val FILE = "etc/profile.d/moru-agents.sh"

    val SCRIPT = """
        # Written by Moru: coding agents installed from Settings → Agents.
        case ":${'$'}PATH:" in
          *:/root/.npm-global/bin:*) ;;
          *) PATH="/root/.npm-global/bin:${'$'}PATH"; export PATH ;;
        esac
    """.trimIndent() + "\n"

    /** Best effort: a rootfs the app cannot write (root mode) keeps working. */
    @Synchronized
    fun ensureInstalled(rootfsDir: File) {
        try {
            val file = File(rootfsDir, FILE)
            if (file.isFile && file.readText() == SCRIPT) return
            file.parentFile?.mkdirs()
            file.writeText(SCRIPT)
            file.setReadable(true, false)
        } catch (_: Exception) {
        }
    }
}
