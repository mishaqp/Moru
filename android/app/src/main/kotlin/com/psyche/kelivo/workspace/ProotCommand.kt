package com.psyche.kelivo.workspace

import java.io.File

data class BindMount(
    val host: String,
    val guest: String,
    val readOnly: Boolean = false,
)

data class ProotLaunch(
    val argv: List<String>,
    val processEnv: Map<String, String>,
    val workingDirectory: File,
)

object ProotCommand {
    const val EXEC_LIB = "libproot_exec.so"
    const val LOADER_LIB = "libproot_loader.so"
    const val TALLOC_LIB = "libtalloc.so"
    const val TALLOC_SONAME = "libtalloc.so.2"
    /** Carries a caller's PATH past the login shell's profile. */
    const val PATH_KEEP = "KELIVO_PATH"

    // A login shell reads /etc/profile, which on Alpine and Debian replaces
    // PATH. Put back the directories a caller asked for (for example Moru's
    // npm prefix) that the profile dropped, ahead of the profile's own.
    val BASH_EVAL = """
        if [ -n "${'$'}{$PATH_KEEP-}" ]; then
          kelivo_add=
          kelivo_rest=${'$'}$PATH_KEEP:
          while [ -n "${'$'}kelivo_rest" ]; do
            kelivo_dir=${'$'}{kelivo_rest%%:*}
            kelivo_rest=${'$'}{kelivo_rest#*:}
            case ":${'$'}PATH:${'$'}kelivo_add:" in
              *":${'$'}kelivo_dir:"*) ;;
              *) [ -z "${'$'}kelivo_dir" ] || kelivo_add=${'$'}{kelivo_add:+${'$'}kelivo_add:}${'$'}kelivo_dir ;;
            esac
          done
          [ -z "${'$'}kelivo_add" ] || PATH=${'$'}kelivo_add${'$'}{PATH:+:${'$'}PATH}
          export PATH
          unset kelivo_add kelivo_rest kelivo_dir
        fi
        unset $PATH_KEEP
        cd -- "${'$'}1" && eval "${'$'}2"
    """.trimIndent()
    // Chroot runs as root while the bound workspace belongs to the Android
    // app. Prepare existing rootfs images too, before exec/PTY and agent runs.
    private val GIT_PREPARE = """
        if command -v git >/dev/null 2>&1; then
          moru_git_safe() {
            git config --system --get-all safe.directory 2>/dev/null |
              awk -v directory="${'$'}1" '${'$'}0 == "" { safe=0 } ${'$'}0 == directory { safe=1 } END { exit !safe }'
          }
          moru_git_attempt=0
          while ! moru_git_safe "${'$'}1"; do
            if moru_git_error=${'$'}(git config --system --add safe.directory "${'$'}1" 2>&1); then
              break
            else
              moru_git_code=${'$'}?
            fi
            moru_git_safe "${'$'}1" && break
            moru_git_config=${'$'}(git var GIT_CONFIG_SYSTEM) || exit "${'$'}moru_git_code"
            # A competing writer may have removed its lock since Git failed.
            # Try once immediately in that case; persistent errors still stop.
            if [ ! -e "${'$'}moru_git_config.lock" ] && [ "${'$'}moru_git_attempt" -eq 0 ]; then
              moru_git_attempt=1
              continue
            fi
            if [ ! -e "${'$'}moru_git_config.lock" ] || [ "${'$'}moru_git_attempt" -ge 50 ]; then
              moru_git_safe "${'$'}1" && break
              printf '%s\n' "${'$'}moru_git_error" >&2
              exit "${'$'}moru_git_code"
            fi
            moru_git_attempt=${'$'}((moru_git_attempt + 1))
            sleep 0.1
          done
        fi
        shift
        exec "${'$'}@"
    """.trimIndent()

    fun validateGuestCwd(cwd: String): String {
        val trimmed = cwd.trim()
        require(trimmed.startsWith("/")) { "guest cwd must be an absolute path" }
        require(!trimmed.contains('\u0000')) { "guest cwd contains a NUL byte" }
        require(trimmed.split('/').none { it == ".." }) {
            "guest cwd must not contain .. segments"
        }
        return trimmed
    }

    fun build(
        nativeLibDir: File,
        rootfsDir: File,
        tmpDir: File,
        binds: List<BindMount>,
        cwd: String,
        command: String?,
        env: Map<String, String>,
        extraArgs: List<String> = emptyList(),
        shell: String? = null,
        includeLibraryPath: Boolean = File(nativeLibDir, TALLOC_LIB).isFile,
        emulateHardLinks: Boolean = true,
    ): ProotLaunch {
        val guestCwd = validateGuestCwd(cwd)
        require(extraArgs.none { it.contains('\u0000') }) { "PRoot argument contains a NUL byte" }
        val argv = mutableListOf(
            File(nativeLibDir, EXEC_LIB).absolutePath,
            "--root-id",
            // Hard links are denied to Android apps; PRoot fakes them with
            // symlinks. Agents publish files atomically (write a temporary
            // file, link it into place, remove the temporary), which that
            // fake turns into a dangling link, so their launches opt out and
            // fall back to a copy instead (see AcpAgentSpec's fs shim).
            *(if (emulateHardLinks) arrayOf("--link2symlink") else emptyArray()),
            "--kill-on-exit",
            // System V shared memory and semaphores, used by Python's
            // multiprocessing, PostgreSQL and some Node native modules.
            "--sysvipc",
            *extraArgs.toTypedArray(),
            "-r",
            rootfsDir.absolutePath,
            "-w",
            guestCwd,
        )
        for (bind in binds) {
            if (bind.host.isBlank() || bind.guest.isBlank()) continue
            argv += "-b"
            argv += "${bind.host}:${bind.guest}"
        }
        // PRoot bindings are writable. The app and file tools enforce the
        // user's read-only preference; arbitrary shell programs are not isolated.
        argv += listOf("-b", "/dev", "-b", "/proc", "-b", "/sys")
        // Android's /dev has no fd or shm entries that shells (process
        // substitution) and runtimes expect; proot-distro binds the same.
        // Per-descriptor stdin/stdout/stderr binds are left out: PRoot warns
        // about them on every run whose descriptor is a pipe or closed.
        argv += listOf(
            "-b", "/proc/self/fd:/dev/fd",
            "-b", "${File(rootfsDir, "tmp").absolutePath}:/dev/shm",
        )
        for (name in PROC_STAND_INS) {
            val standIn = File(tmpDir, "proc-$name")
            if (standIn.isFile) argv += listOf("-b", "${standIn.absolutePath}:/proc/$name")
        }
        argv += guestCommand(rootfsDir, guestCwd, command, env, shell)

        val processEnv = linkedMapOf(
            "PROOT_LOADER" to File(nativeLibDir, LOADER_LIB).absolutePath,
            "PROOT_TMP_DIR" to tmpDir.absolutePath,
            "TMPDIR" to tmpDir.absolutePath,
        )
        if (includeLibraryPath) {
            processEnv["LD_LIBRARY_PATH"] =
                tmpDir.absolutePath + File.pathSeparator + nativeLibDir.absolutePath
        }

        return ProotLaunch(
            argv = argv,
            processEnv = processEnv,
            workingDirectory = rootfsDir.parentFile ?: rootfsDir,
        )
    }

    /**
     * The program run inside the rootfs: the guest's shell in [cwd] with only
     * [env] (plus defaults), a login shell for a terminal ([command] null) or
     * `bash -lc` for one command. Shared by PRoot and the chroot helper.
     */
    fun guestCommand(
        rootfsDir: File,
        cwd: String,
        command: String?,
        env: Map<String, String>,
        shell: String?,
    ): List<String> {
        val guestCwd = validateGuestCwd(cwd)
        val guestShell = shell?.takeIf { it.isNotBlank() } ?: if (
            RootfsInfo.guestFile(rootfsDir, "/bin/bash").let { it.isFile && it.canExecute() }
        ) "/bin/bash" else "/bin/sh"
        validateGuestCwd(guestShell)
        val argv = mutableListOf("/usr/bin/env", "-i")
        val guestEnv = LinkedHashMap(env)
        // env -i discards the host environment. Export guest defaults so child
        // processes (including dpkg) receive PATH, not only bash's shell default.
        guestEnv.putIfAbsent("HOME", "/root")
        guestEnv.putIfAbsent("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
        guestEnv.putIfAbsent("LANG", "C.UTF-8")
        if (command == null) {
            guestEnv.putIfAbsent("TERM", "xterm-256color")
        } else {
            env["PATH"]?.let { guestEnv[PATH_KEEP] = it }
        }
        if (RootfsNodeDns.isInstalled(rootfsDir)) {
            guestEnv["NODE_OPTIONS"] = RootfsNodeDns.nodeOptions(guestEnv["NODE_OPTIONS"])
        }
        for ((key, value) in guestEnv) {
            argv += "$key=$value"
        }
        argv += listOf("/bin/sh", "-c", GIT_PREPARE, "kelivo-git", "/workspace")
        if (command == null) {
            argv += listOf(guestShell, "-l")
        } else {
            argv += listOf(guestShell, "-lc", BASH_EVAL, "kelivo", guestCwd, command)
        }
        return argv
    }

    private val PROC_STAND_INS = listOf("stat", "vmstat")

    /** What [build]'s binds need on disk before PRoot starts. */
    fun stageGuest(rootfsDir: File, tmpDir: File) {
        File(rootfsDir, "tmp").mkdirs()
        stageProcStandIns(tmpDir)
        RootfsProfile.ensureInstalled(rootfsDir)
        RootfsNodeDns.ensureInstalled(rootfsDir)
    }

    /**
     * Android forbids apps to read /proc/stat and /proc/vmstat, so Node's
     * os.cpus() comes back empty and top/free/ps fail. Like proot-distro and
     * ReTerminal, stand-ins are bound over them; only when the real files
     * cannot be read, so a device that allows it keeps its real numbers.
     */
    fun stageProcStandIns(
        tmpDir: File,
        cpus: Int = Runtime.getRuntime().availableProcessors(),
        readable: (File) -> Boolean = ::canRead,
    ) {
        tmpDir.mkdirs()
        for (name in PROC_STAND_INS) {
            val standIn = File(tmpDir, "proc-$name")
            if (readable(File("/proc/$name"))) {
                standIn.delete()
                continue
            }
            val text = if (name == "stat") procStat(cpus) else PROC_VMSTAT
            if (!standIn.isFile || standIn.readText() != text) standIn.writeText(text)
        }
    }

    private fun canRead(file: File): Boolean = try {
        file.inputStream().use { it.read() }
        true
    } catch (_: Exception) {
        false
    }

    /** Idle counters for [cpus] cores, in the kernel's /proc/stat layout. */
    fun procStat(cpus: Int): String = buildString {
        val count = cpus.coerceAtLeast(1)
        append("cpu  ${100 * count} 0 ${100 * count} ${10000 * count} 0 0 0 0 0 0\n")
        for (cpu in 0 until count) append("cpu$cpu 100 0 100 10000 0 0 0 0 0 0\n")
        append("intr 0\nctxt 0\nbtime 0\nprocesses 1\nprocs_running 1\nprocs_blocked 0\nsoftirq 0\n")
    }

    private val PROC_VMSTAT = listOf(
        "nr_free_pages", "nr_inactive_anon", "nr_active_anon", "nr_inactive_file",
        "nr_active_file", "nr_dirty", "nr_writeback", "pgpgin", "pgpgout",
        "pswpin", "pswpout", "pgfault", "pgmajfault",
    ).joinToString("") { "$it 0\n" }

    /** Copy libtalloc.so to the SONAME proot actually DT_NEEDs. */
    fun stageTalloc(nativeLibDir: File, tmpDir: File) {
        val source = File(nativeLibDir, TALLOC_LIB)
        if (!source.isFile) return
        tmpDir.mkdirs()
        val staged = File(tmpDir, TALLOC_SONAME)
        if (staged.isFile && staged.length() == source.length()) return
        source.copyTo(staged, overwrite = true)
    }
}


internal fun validateExternalMounts(mounts: List<BindMount>) {
    val prefix = "/mounts/"
    require(mounts.size <= 10 && mounts.map { it.guest.lowercase() }.distinct().size == mounts.size)
    for (mount in mounts) {
        require(mount.guest.startsWith(prefix))
        val name = mount.guest.removePrefix(prefix)
        require(name.isNotEmpty() && name == name.trim() && name != "." && name != "..")
        require(name.none { it == '/' || it == '\\' || it == ':' || it.code < 32 || it.code == 127 })
        require(File(mount.host).isAbsolute && mount.host.none { it == ':' || it == '\u0000' })
    }
}
