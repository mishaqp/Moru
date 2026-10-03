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
the same for upstream changes under `lib/desktop/`. Platform-only desktop/iOS
Dart branches and direct dependencies are removed. Preserve Android phone and
wide-screen layouts; do not add a separate desktop implementation.

Preserve explicit user settings, existing chat data, application ID and signing
identity unless a task explicitly changes them. Never publish an unsigned or
rotating-debug-key build as a stable release. See `docs/MORU_ANDROID_ONLY.md`.

## Project overview

Upstream Kelivo is a cross-platform Flutter LLM chat client. Moru's Dart package
name remains `Kelivo`; imports use `package:Kelivo/...`. Keeping that internal
package name does not require building other platforms.

## Architecture

- **Feature-based structure**: `lib/features/<feature>/` with `pages/`, `widgets/`, `models/`, `utils/` subdirectories.
- **Desktop code**: PC/iOS application branches, unused dialogs, native terminal/file-manager actions and direct packages are removed. Shared context menus, pointer anchors and select dropdowns in `lib/shared/widgets/` serve Android too. Preserve `HomeDesktopScaffold`, `AppBreakpoints.tablet` and width-based `isWide` layouts for Android tablets, foldables and landscape. The legacy `desktop_send_shortcut_v1` setting still serves Android hardware keyboards; retired PC keys remain stored without migration. Linux process fixtures test Android shell/STDIO on CI; they are listed in `docs/MORU_ANDROID_ONLY.md`. Do not add desktop application code.
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
- **MCP manager tool**: the opt-in, default-off `manage_mcp` lists, reads and
  tests live MCP servers; add/update/enable/disable/remove use ordinary tool
  confirmation without individual "Always allow". Credentials are entered
  privately on its approval card or in MCP settings, never in model arguments
  or results. Full trust cannot fill missing credentials. It reuses the MCP
  JSON importer and runtime; package installation stays in workspace `shell`.
  Ordinary env/header values are visible; literal secret assignments in shell
  arguments are rejected. New STDIO servers default to the chat workspace
  unless explicitly bound elsewhere or unbound. Responses note that new tools
  become available from the next message; listed tool availability also
  requires an enabled, connected server.
- **Problem reports**: opt-in `report_problem` asks for fresh consent unless
  global full-trust mode is enabled; individual "Always allow" is unavailable.
  `ProblemReportService` exports a private ZIP with
  app/device/runtime details, allowlisted settings and a bounded technical
  journal from `FlutterLogger` (event names, error types and package frames,
  never chat text, prints or request/context logs). With Flutter logging enabled,
  it also includes bounded one-second summaries of frames over 100 ms (count,
  longest frame, build and raster durations). ACP/log redactors remove
  secrets before writing. The chat offers Share through a checked private
  snapshot; exports and owned share-cache copies are removed on next launch.
- **Browser and Computer**: `BrowserAgentSession.minimize` parks the live
  `WebViewController`; the next agent `WebViewPage` adopts it without reloading.
  `openSharedBrowser` opens or expands it. `BrowserMiniWindow` in `AppOverlays`
  retains the native host while parked, including when its visible card is off.
  Settings → Browser → floating window is opt-in (`browser_floating_window_v1`,
  default false). Keep a Material/text-style root and stable WebView ancestry
  across floating/Glass changes; do not replace the controller to change UI.
  The chat header's `ChatHeaderSwitcher` still opens files, terminal and browser.
  Browser navigation uses evenly spaced 48dp targets and a labeled Actions
  pill counted for the captured public page identity. Send stays inside the
  composer pill; the compact two-line AI answer is a sibling that reduces the
  WebView height, never an overlay. Its full answer and recent AI actions use
  `CustomBottomSheet`, with history, console and approvals preserved. The
  primary header action minimizes to chat; Close lives in the menu and asks
  confirmation during AI work. Keep WebView directly below the safe header.
- **Background jobs and task plan**: workspace `shell` takes `background: true`
  and returns a `job_id`; `shell_output` reads, waits for or stops the job
  (its `ToolRun` stays in `ToolRunRegistry`, found by `byRuntimeRunId`). The
  `update_plan` workspace tool stores the checklist in `TaskPlanRegistry`.
  `ComposerStatusStrip` shows one `ComputerStatusPanel` for this reply's tools
  and keeps the open plan (`TaskPlanChip`) nearby. It replaces the separate
  running-command chip in the composer, follows the newest working step,
  retains a manually selected working step and briefly shows the final result.
  Every working card is one 56–60dp row at text scale 1.0: a 64x40 preview
  with 10dp corners, two text lines and an inline compact pager (16dp icons,
  48dp touch targets). Browser cards have a domain/status pill beside the
  action, with a blue running pulse (disabled by reduced motion), green
  success, red error or grey stopped dot. Without a snapshot the preview is
  a small themed Globe tile without domain text. URL-less browser steps,
  including done, show the last preceding page domain from the same response,
  validated by the selected step's display filter; this label never grants
  access to an earlier step's snapshot. The preview expands the shared
  browser without reloading its controller; the rest opens ComputerSheet.
  Browser previews use an exact saved source or a proven same-page snapshot
  captured no earlier than the step start; a different site's latest chat image
  never fills the placeholder. The card has no Stop of its own: the composer's
  Stop cancels the reply and, through
  `cancelStreamingById`, the shared browser action of that chat. A running
  browser step without a URL yet is named from that chat's live browser page
  and current action. Browser tool cards read "Browser · site/action", never
  the raw `browser_use` name. A terminal reply
  uses a 48dp summary with action count and View. Previews never show argument
  JSON: commands show the filtered live/saved output tail or `$ command`,
  files their name/content, plans ListChecks, other tools a framed icon.
  Background jobs remain accessible while running. `ComputerToolSource` and
  `ComputerResponseScope` adapt existing live/persisted tool parts and registry
  runs; tapping any tool card opens that reply's `ComputerSheet` (85% height).
  Preserve original specialized details on long press, reruns and approvals.
  The sheet centers its title between equal 44dp close/action slots, shows
  known parameters as labeled rows and hides other filtered JSON in a collapsed
  section; empty JSON sections are hidden. Browser steps without a checked
  snapshot have no large placeholder in the sheet. Boolean browser result
  status reads Success/Error, never Yes/No. Browser done actions use a Summary
  chip and plain summary text; other browser results show readable status,
  summary, title and URL, with raw JSON only in the collapsed parameters.
  Commands fill the result area and follow output until the user
  scrolls up; update_plan shows its actual checklist. Terminal response status
  always overrides "AI is working", including when its background job lives on.
  Cancellation durably marks unfinished response tools as stopped, clears live
  loading and ends only foreground response-owned ToolRuns. Generation Stop
  preserves explicit background shell jobs; use shell_output to stop those.
  Capture the chat/response identity when opening a sheet, normalize missing
  tool IDs consistently and retain completed run references in an open sheet.
  Identify orphan background steps by runtime ID; resolve saved `job_id` before
  a reused tool-call ID so concurrent processes cannot collapse into one step.
  If Stop precedes a background result, persist its known runtime identity and
  clear tool-card loading while retaining the independent job.
  `ComputerStep` display values apply existing launch-secret/auth-URL rules;
  execution arguments and live runtime output stay intact. Use the captured
  `ToolRun` display filter in every detail/copy surface.
  `BrowserThumbnailCache` reads existing checked screenshots, reduces them to
  JPEGs and bounds memory (24/chat, 8 chats, 256KiB/image). Computer widgets
  never request native screenshots or reload a WebView. Screenshot ownership
  must remain consistent across readiness/native capture. Dispose listeners,
  timers and preview controllers; keep keyboard/landscape/1.3 scaling working.

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
  Claude Code and Codex also support assistant `agentAuthMode: subscription`
  (missing/unknown saved values mean `provider`). Keep `manage_assistants`
  validation and imported/duplicated assistants in sync with this field.
  Subscription launches ignore provider/model overrides and scrub inherited
  provider credentials after the guest login profile; their persistent homes
  are `/root/.config/moru-agents/subscription/{claude,codex}`. Native CLI
  login/status/logout and ACP must share that home, identity and runtime mode.
  `AcpAgentAuth` keeps login output private and bounded; only its dedicated
  settings page may show an allowlisted auth URL/device code or submit Claude's
  full `code#state` to stdin. Open sign-in links in the external browser.
  Explicit Sign In selects subscription mode for the intended assistant before
  native login; inspecting the page or checking status must not change settings.
  Never copy Moru OAuth tokens, read agent token files, or log native auth output.
  Stop subscription processes before login/logout, block new starts throughout
  credential changes, and cancel all auth commands on disposal/uninstall.
  Codex subscription allows one native ACP process per manager because its
  refresh lock is process-local. Switching from an idle chat stops it before
  restoring the next context; another active reply reports `accountBusy`.
  Provider-mode concurrency stays available. `Check` reuses a live Codex
  subscription process and does not send a paid model prompt. Auth-required
  RPC errors invalidate the cached status. Logical `acp:` model sources must
  not enter ordinary API capability/title/suggestion paths; explicit auxiliary
  API models still apply. Preserve pinned provider settings when modes change.
  Subscription `AcpSecretRedactor` also masks unknown OAuth tokens, device
  codes and auth URLs across stream chunks before persistence. Hash local
  subscription tool-card IDs while retaining raw IDs privately for protocol
  routing. Reject agent browser tools containing auth URLs before execution;
  the browser library must skip auth URLs, including title-refresh writes.
  See `docs/audits/acp-subscription.md` and its versioned native probes for
  supported methods, provider-policy limitations and remaining phone checks.
  Session config options (ACP `configOptions`, `session/set_config_option`,
  `config_option_update`) drive the chat's agent options chip next to the
  mode chip: codex-acp 2.1.1 offers model, reasoning_effort, fast-mode and
  collaboration_mode; claude-agent-acp 0.85 offers model and effort. Both
  also list a `mode` option, which stays with the mode chip. Choices are kept
  in `Assistant.agentConfig` (id → value, reset when the agent changes) and
  applied before the next turn, model first, only while the agent still
  offers the value. With a Moru provider the provider keeps the model; only
  the other options apply. Option ids and values are redactor controls.
  A chat whose agent has not started shows the options that agent (and auth
  mode) offered last in this app run.
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
  Every guest process (terminal, tools, agents, MCP, mini-app servers, npm)
  loads `RootfsNodeDns` first through `NODE_OPTIONS`, added in
  `ProotCommand.guestCommand` only while `/etc/moru/node-dns.cjs` exists and
  merged once with the user's or agent's options. musl fails a whole lookup
  without a family with EAI_AGAIN when only AAAA goes unanswered (some
  routers); the shim retries with IPv4, then IPv6, and asks IPv4 first for
  five minutes after a rescue. Other errors and working IPv6 stay untouched.
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
  Claude needs Node >=22. Each launch owns a fresh mode-0700
  `/var/mc/<22-character random id>` via `CLAUDE_CODE_TMPDIR`, with its own
  `CLAUDE_CODE_CONTAINER_ID=moru-<id>`: the native root/container exception
  handles PRoot's real Android file UID. Keep base + `/claude-UID` <=44 bytes
  so Claude's Bash helper never falls back to shared `/tmp/claude-0`. The
  roots stay outside every chat mount: a workspace chat binds its own `/tmp`,
  which the preparation run does not see.
  All artifacts written during preparation and used by a subsequent agent
  or native-auth run (configs, auth homes, MCP/FS helpers and scratch dirs)
  must stay outside `/workspace`, `/chat`, `/skills`, `/tmp` and `/downloads`.
  Preparation runs without the chat mounts. Codex's fixed daemon mountpoint
  is created only inside the actual launch namespace after mounts are applied;
  its prepared source remains under `/var/md`.
  `AcpLaunchDirectories` leases cover preparation, close and failed startup;
  recovery uses boot/PID/start identities and inherited SDK markers, keeps
  live or uninspectable runs, and anchors cleanup to a managed directory fd.
  Root Codex binds its fresh `/var/md/<id>` onto its fixed daemon leaf only
  inside the run's private mount namespace; preparation and launch must use
  the same runtime mode. Never chown existing daemon dirs, shim getuid globally
  or weaken workspace permissions. See `docs/audits/*ownership.md` for scope
  and remaining Codex/Bubblewrap device checks.
  ACP failures retain bounded, redacted data/stderr in an `AgentErrorPart`,
  shown as collapsed details in the chat and agent check. Filter stderr before
  retaining its tail; keep current RPC classification ahead of older stderr.
  Error parts are diagnostic history and must not become future model prompts.
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
   `reorderable_grid_view`, `system_fonts`, `window_manager`, `desktop_drop`),
   direct iOS/desktop Sherpa packages, or on-device LLM packages.
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
- ACP lifecycle fixtures set permissions explicitly when a refusal depends on
  directory mode. Scope `/proc` enumeration with `acp_test_process_table.dart`
  to registered fixture PIDs (including surviving SDK children); keep their
  actual identities, UIDs and environments. Unrelated host processes with
  unreadable environments must not pin test directories under root or CI.
  Exercise the production refusal for an uninspectable registered process.

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
