# AGENTS.md

## Moru product scope — read first

Moru is the user's personal **Android-only** fork of Kelivo. Ship exactly one
**arm64-v8a APK**. Do not build, release, add features for or repair iOS, macOS,
Windows, desktop Linux or Web applications. Do not add Nightly/scheduled builds.
Ubuntu CI runners execute Android checks; they are not Linux application targets.

Preserve the embedded PRoot/Linux environment, workspace, terminal/PTY and STDIO
MCP: these are Android features. The native `ios/`, `macos/`, `windows/`,
`linux/` and `web/` projects are removed and must not return; when merging
upstream Kelivo, resolve its changes to those folders by deleting them, and do
the same for upstream changes under `lib/desktop/`. The
remaining desktop/iOS Dart code under `lib/` is removed in separate, reviewed
steps. New UI work only needs Android/mobile layouts, not a parallel
desktop implementation.

Preserve explicit user settings, existing chat data, application ID and signing
identity unless a task explicitly changes them. Never publish an unsigned or
rotating-debug-key build as a stable release. See `docs/MORU_ANDROID_ONLY.md`.

## Project overview

Upstream Kelivo is a cross-platform Flutter LLM chat client. Moru's Dart package
name remains `Kelivo`; imports use `package:Kelivo/...`. Keeping that internal
package name does not require building other platforms.

## Architecture

- **Feature-based structure**: `lib/features/<feature>/` with `pages/`, `widgets/`, `models/`, `utils/` subdirectories.
- **Desktop code**: the desktop app shell (window, tray, hotkeys, desktop home and settings panes) and `lib/desktop/` are removed. The shared context menu, pointer anchor and select dropdown live in `lib/shared/widgets/`. Wide Android screens (tablet, foldable, landscape) still use `HomeDesktopScaffold` from `home_desktop_layout.dart`; scheduled tasks and a few screens keep `isDesktop` branches that are removed in later steps. Use the Android/mobile path for Moru tasks and do not add new desktop code.
- **State management**: Provider (`lib/core/providers/`).
- **Database**: Drift (`lib/core/database/`). Schema versions tracked in `drift_schemas/`.
- **Localization**: ARB-based (`lib/l10n/`), English template (`app_en.arb`). Edit source ARB, run `flutter gen-l10n`, and commit generated output. Preserve English and Chinese translations when adding Russian. Add new keys to every Chinese ARB, including `app_zh.arb`, `app_zh_Hans.arb` and `app_zh_Hant.arb`; inspect `desiredFileName.txt` for new untranslated messages before committing.

## Chat features that already exist — do not reimplement

- **Workspace AGENTS.md**: a workspace bound to a conversation gets its root
  `AGENTS.md` (and the one in the current working directory, when that lies
  inside the workspace) appended to the system message of every request.
  `lib/core/services/workspace/workspace_agents_instructions.dart` reads it;
  `MessageBuilderService.injectWorkspacePrompt` injects it. Nothing is stored in
  the conversation, the assistant's system prompt is untouched, and a missing,
  empty, oversized or unreadable file is skipped silently.
  Only a real path inside the real workspace root is eligible; the shared
  `WorkspaceFileAccess` also verifies the opened descriptor. Outward symlinks
  are skipped silently, including a symlink in the middle of the path.
- **Pending message queue**: submitting while a reply streams parks the message
  instead of rejecting it. `QueuedInputQueue` (`lib/features/home/controllers/`)
  owns the FIFO, `HomeViewModel` drains it when a conversation goes idle, and
  `_QueuedInputPanel` in `chat_input_bar.dart` shows order, edit and remove. A
  pending item can be edited in the composer through `QueuedMessageEditState`.
- **Assistant manager tool**: the opt-in local tool `manage_assistants`
  (`AssistantManagerTool` in `lib/features/home/services/`) lets the model
  list, read, create, update, duplicate, switch and delete assistants. It
  validates every id against the live providers, create/update/duplicate/delete
  go through the tool approval prompt, and it cannot delete the assistant
  running the chat or the last one. Extend its settings schema when
  `Assistant` gains a user-facing field.
- **Floating browser**: the agent `WebViewPage` can minimize into
  `BrowserMiniWindow` (in `AppOverlays`). `BrowserAgentSession.minimize`
  parks the live `WebViewController`, and the next agent `WebViewPage` adopts
  it without reloading; `openSharedBrowser` opens or expands it. The chat
  header's `ChatHeaderSwitcher` and the composer's `ComposerStatusStrip` are the
  entry points for files, terminal, browser and running commands.
- **Background jobs and task plan**: workspace `shell` takes `background: true`
  and returns a `job_id`; `shell_output` reads, waits for or stops the job
  (its `ToolRun` stays in `ToolRunRegistry`, found by `byRuntimeRunId`). The
  `update_plan` workspace tool stores the checklist in `TaskPlanRegistry`.
  `ComposerStatusStrip` shows the open plan (`TaskPlanChip`) and the running
  command (`RunningToolChip`) side by side above the composer.

- **ACP agents**: coding agents (Claude Code, Codex, OpenCode, Kimi Code,
  DeepSeek Harness, custom) speak
  the Agent Client Protocol over the Linux environment's STDIO pipes
  (`lib/core/services/acp/`). `AcpAgentManager` installs them with npm and
  checks them (Settings → Agents); `AcpAgentSpec.launch` maps a Moru provider
  to each agent's variables/config (keys only in env). Provider headers use
  backend-supported env references. Kimi's explicit User-Agent override needs
  a process-owned temporary config, removed after native stop/exit or uninstall;
  keep its persistent sessions/home and coordinate all active config owners.
  Known launch secrets are redacted before ACP display/error payloads leave
  the boundary; private tool correlation must retain actual execution values.
  Moru MCP approval cards and browser activity details inherit the launch's
  display filter while handlers receive the original execution arguments.
  An assistant with `agentId` answers through its agent: `AcpChatBridge` swaps the chunk
  source in `_executeGeneration`, `AcpTurnTranslator` turns `session/update`
  into `StreamChunk`s (workspace cards, plan strip), permission requests go
  to `ToolApprovalService` on the tool card, and `AcpChatSessions` keeps one
  process and session per chat (`acp.session` in conversation extras).
  Each process owns an authenticated loopback `AcpMcpServer` (dart:io,
  random port/token): it exposes the assistant's browser, mini apps, memory
  and scheduled tasks through the existing `ToolHandlerService`, with the
  chat's assistant, conversation and workspace context. File/shell tools
  are excluded. `AcpMcpBinding` pairs each call with the agent's existing
  ACP tool card; only the Moru handler asks for approval. HTTP-capable agents
  receive an HTTP `mcpServers` entry on new/load/resume; others use the dependency-free
  Node `AcpMcpStdioBridge` written by `writeFilesScript` (token only in env).
  Hidden chats cannot use the live browser UI. Settings → Agents → Check runs
  `AcpMcpProbe` from the active Linux runtime to report actual loopback access;
  device PRoot/root-chroot availability must be tested on the phone.
  Codex always uses `wire_api = "responses"`; its detail page and the assistant
  agent picker warn when the selected provider has no Responses API enabled.
  DeepSeek Harness passes custom request headers in `providers.moru.headers`
  for all three supported APIs.
  Kimi uses `kimi acp`; DeepSeek Harness is installed globally in Moru's npm
  prefix and runs `dsh --profile acp`, never `npx` per launch. Probe the active
  runtime's Node before installing or starting them: Kimi needs >=22.19.0;
  DSH accepts ^22.19.0 or >=24.0.0 (not Node 23). Distro Node on apt systems
  is 12-20, so installing an agent runs `AcpAgentSpec.nodeUpgradeScript`
  (removes distro npm/libnode*, installs NodeSource 24) when Node is too old;
  verified on Ubuntu 22.04/24.04 and Debian 13. Alpine's own `apk` Node is
  new enough (22.23 on 3.22, 24 on 3.23+). DSH builds koffi with CMake on
  Alpine. Every built-in agent was installed and answered ACP `initialize`
  on Alpine 3.24 and Debian 13.
  `AcpChatSessions` restores with load first, advertised resume second, then
  a new session with history; missing modes/plans are valid capabilities.
  `AcpAgentWebServers` owns the official Kimi/DSH/OpenCode Web processes in
  the Linux runtime, with separate persistent state, generated configs and the
  assistant's workspace. Bind only 127.0.0.1, wait for the printed authenticated address,
  and send the login URL only to `openSharedBrowser`, never a log or chat.
  OpenCode Web instead gets a fresh cryptographically random password for
  every process, only in `OPENCODE_SERVER_PASSWORD`. Its clean URL must match
  the allocated port. A new JS-disabled WebView authenticates once at `/session`
  before joining the shared browser; Chromium's Basic auth cache is scoped to
  the exact scheme, host and port. Ordinary browser delegates cancel auth
  challenges. Never put credentials into URLs, JavaScript, the browser library
  or `WebViewDatabase`; Stop revokes an in-flight browser bootstrap.
  Stop on the card, app detach and provider disposal; changed launch settings
  replace the process.
  Only ACP launches pass `PATH`; `ProotCommand` carries it as `KELIVO_PATH`
  and restores dropped entries after the guest's login profile (Alpine and
  Debian reset `PATH` in `/etc/profile`). Exit 127 means the agent's command
  is missing: say "not installed" and re-probe installation.
  Agent and agent-Web launches set `emulateHardLinks: false` (no PRoot
  `--link2symlink`, which leaves dangling links after atomic writes) and
  load `AcpFsCompat` via `NODE_OPTIONS` to copy when Android denies link(2).
  PRoot always binds `/dev/fd`, `/dev/shm`, `--sysvipc`, and stand-ins for
  unreadable `/proc/stat`/`/proc/vmstat` (`ProotCommand.stageGuest`). Root
  mode (`moru_chroot`) adds missing `/dev/fd` and `/dev/std*` links to the
  device's /dev, binds the rootfs `/tmp` on `/dev/shm`, and probes `/bin/sh`
  inside the chroot (Alpine's is an absolute link to busybox).
  `RootfsProfile` writes `/etc/profile.d/moru-agents.sh` so the terminal
  finds agents. Built-in install scripts first add system packages one by
  one (`moru_packages` in `acp_agent_catalog.dart`); a missing package is
  logged, not fatal. Environment → Packages groups `EnvironmentDependencies`
  (development, agents, SSH); ticked rows install through one `installAll`
  and `agentDependencies` is the "prepare for agents" set.
  Built-in removal uses each spec's explicit npm package manifest and `set -e`.
  A failed npm removal leaves the agent installed and keeps its error journal;
  OpenCode's manifest includes both arm64 platform packages. Do not infer
  package names from installation shell text or remove shared system packages.
  Guest launch preparation trusts only `/workspace` in
  system Git config to handle the Android UID/root-chroot ownership mismatch.
- **Mini apps**: published web apps (`MiniAppStore`, bridge `moru.*` in
  `MiniAppBridge`). They keep an error journal, the last 5 versions, and
  manifest game settings (`MiniAppDisplay`). Background jobs (`moru.jobs`,
  `MiniAppJobs`) are stored with the app and run through the native
  `ScheduledTasks` planner as kind `miniAppJob`. `MiniAppJobRunner` runs them
  in a hidden WebView. An app may declare a server (`server.command`):
  `MiniAppServers` runs it in the Linux environment on `$PORT` while the app
  or a job uses it, and pages reach it with `moru.server.fetch`.
  `MiniAppWebHost` serves the apps to browsers in the Wi-Fi
  (`MiniAppWebServer`, `moru.local` via `MdnsResponder`), kept alive by
  `ProcessKeepAlive` (`app.keep_alive`).

## Pre-commit checklist

All model file tools and the Files UI use
`lib/core/services/workspace/workspace_file_access.dart` as the common boundary.
Resolve symlinks in every path component and compare with captured real allowed
roots; verify `/proc/self/fd` after opening and keep that descriptor alive for
the actual read. Content writes verify before truncating; parent descriptors
anchor creation, rename and unlink. Do not replace this with lexical checks or
reopen a checked pathname later. Internal symlinks remain valid; deleting a
final symlink checks its parent and removes only the link. Content writes
through read-only aliases remain blocked, including when their targets are
reached by another path.
Unlinking a final symlink to a read-only target is allowed only when its own
parent is writable; the target is never changed.
Preview/share/export snapshots live in private app data, outside the model
file roots, and are copied from a checked open descriptor. Explicit picker
access grants only the selected file. Markdown images and linked thumbnails
render checked bytes. HTML previews disable file/content access and use the
same token-protected loopback server as the browser action, with the original
source file and granted root retained separately from the private snapshot.
Each bounded resource read must stay in both that root and the captured real
page directory. After the standard HTTP parser normalizes the request URI, its
path must still begin with that server’s token; normalization within the token
is allowed. Validate each opened descriptor against both captured boundaries
before reading, and reject encoded path separators or residual dot segments.
Keep the standard HTTP parser, close each HTTP connection after its response,
and close an embedded preview server when its widget is disposed, including
a server that finishes starting after disposal. CSP permits the server origin
and blocks file/content URLs; navigation permits only HTTP/HTTPS.
If a registered runtime's status cannot be read, workspace tools fail closed
before creating a context; they never fall back to native unsandboxed policy.

```bash
dart format lib test
dart analyze --fatal-infos lib test integration_test
flutter test
python3 -m unittest discover -s tool -p 'test_android_only_policy.py' -v
python3 -m unittest discover -s tool -p 'test_verify_apk_arm64.py' -v
python3 -m unittest discover -s tool -p 'test_verify_release_keep_rules.py' -v
```

Format only changed Dart files. `pr-check.yml` enforces the existing analyzer,
tests and localization gates. `moru-android.yml` additionally builds one arm64
APK, runs Android JVM tests and inspects actual APK libraries/signature. PRs
of this repository build the signed release APK (fork PRs build debug);
`tool/verify_release_keep_rules.py` checks every release APK R8 shrinks. Code that
reads generic types by reflection (Gson `TypeToken`) needs keep rules in
`android/app/proguard-rules.pro`.

## Updating Moru (upstream Kelivo merges, any AI tool)

Upstream is `https://github.com/Chevey339/kelivo` (`master`). Work on a branch
and land it through a PR; never push to `master` directly.

1. `git remote add upstream https://github.com/Chevey339/kelivo.git` (once),
   then `git fetch upstream && git merge upstream/master` (merge, not rebase).
2. Resolve every conflict in `ios/`, `macos/`, `windows/`, `linux/`, `web/`
   and in any `lib/desktop/` file by deleting it (`git rm`).
   Keep Moru's side for `android/`, `pubspec.yaml` identity/version,
   `.github/`, `tool/`, `docs/releases/` and Russian ARB strings.
3. Do not re-add the removed desktop packages (`bitsdojo_window`,
   `screen_retriever`, `tray_manager`, `hotkey_manager`,
   `reorderable_grid_view`, `system_fonts`) or on-device LLM packages.
4. Add Russian translations for new ARB keys, run `flutter gen-l10n`, and run
   the whole pre-commit checklist before pushing.

`tool/test_android_only_policy.py` fails when a merge brings back a native
platform folder, a removed desktop package or any `lib/desktop/` file; fix the
merge, never the test.

## Tests must be deterministic

A red test is a bug in the code or in the test, never "a flake" to re-run.
Find the race or order dependency and remove it. Do not skip, disable, retry
or loosen tests to get CI green.

- Dart: debug hooks that simulate a stuck native call (`debug*HangSeconds`)
  start before any cancellation check, so a cancel from the progress callback
  cannot overtake them.
- Robolectric: declare custom shadows on the test class, not on single test
  methods. The sandbox is shared, and mixing shadows per method makes
  results depend on test order.

## Releases

Work lands through one long-lived PR. Bump `version:` in `pubspec.yaml`
(`x.y.z+N`, `N` = previous build + 1) once when the PR starts and keep
`docs/releases/vX.Y.Z.md` (Russian) up to date in it.

- Every push to a PR of this repository builds the signed release APK and
  publishes it as the pre-release `vX.Y.Z-pre.<run>`, deleting older
  pre-releases. It installs over the stable app without losing data. A
  pre-release holds only the APK: no description, checksum or metadata files
  (the user's wish); its tag and target commit are all `promote` needs.
- When the user has tested it, merge the PR (bring `master` into it first so
  the trees match). The `promote` job publishes the last pre-release APK as
  `vX.Y.Z` without rebuilding, when the merged tree equals the tested commit.
- Otherwise publish with the manual `moru-android.yml` dispatch on `master`
  (`variant=release`, `publish=true`).

## Benchmarks are not tests

`test/perf/*_bench.dart` print timings and contain no `expect()`, so they cannot
fail. They are outside the default `_test.dart` glob. Run one explicitly:

```bash
flutter test test/perf/timeline_scroll_bench.dart
```

## UI guidelines

- Use app-defined widgets from `lib/shared/widgets/` and `lib/shared/dialogs/` when equivalent (for example `SectionCard`, `CustomBottomSheet`, `IosFormTextField`, `IosCheckbox`, `InteractiveDrawer`). Their names do not imply an iOS build is needed.
- Existing mobile bottom-sheet patterns are supported.
- Use `lucide_icons_flutter`, not `Icons.*` from Material.
- Use the existing `flutter_animate` / `animations` patterns for motion.
- New features target Android. Do not duplicate them into unused desktop UI.

## Code style

- Preserve Android data and update compatibility. Avoid speculative fallback layers and unrelated migrations.
- Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, configuration and indirection.
- Grow in tested increments; never trade a working product for unfinished complexity.
- Keep components modular and concerns separated.
- Prefer established libraries when they improve reliability. Check documentation and actual types before inventing missing capabilities or adding dependencies.
- Lean on dependencies already in the project.
- Do not implement a temporary architecture intended to be replaced immediately.

## Local dependencies

Several packages live under `dependencies/` and are referenced by path in
`pubspec.yaml` (for example `gpt_markdown`, `mcp_client`, `flutter_tts`,
`flutter_math_fork`, `downsize`). The analyzer excludes
`dependencies/flutter_math_fork/**` and `dependencies/flutter_tts/**`.

## Useful commands

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter build apk --debug --target-platform=android-arm64
python3 tool/verify_apk_arm64.py build/app/outputs/flutter-apk/app-debug.apk
```

## Cloud coding containers

If `flutter` is not on `PATH` (a fresh Codex/agent cloud container), run
`bash tool/codex_cloud_setup.sh` once, then `source
"${MORU_TOOLCHAINS:-$HOME/.moru-toolchains}/activate.sh"` in every shell. The
script installs the Flutter version pinned in `.github/workflows/pr-check.yml`
from the official archive, verifies its SHA-256 against the release manifest,
keeps the SDK outside the repository and runs `flutter pub get` like CI
(`pubspec.lock` is not committed). It needs network access, not root. Then run the whole
pre-commit checklist; APK builds are left to CI.
