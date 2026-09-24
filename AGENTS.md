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
the same for upstream changes to removed files under `lib/desktop/`. The
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
- **Desktop code**: the desktop app shell (window, tray, hotkeys, desktop home and settings panes) is removed. `lib/desktop/` still holds desktop branches reached from mobile screens and a few shared menu widgets; those are removed or moved to `lib/shared/` in later steps. Use the Android/mobile path for Moru tasks and do not add new desktop code.
- **State management**: Provider (`lib/core/providers/`).
- **Database**: Drift (`lib/core/database/`). Schema versions tracked in `drift_schemas/`.
- **Localization**: ARB-based (`lib/l10n/`), English template (`app_en.arb`). Edit source ARB, run `flutter gen-l10n`, and commit generated output. Preserve English and Chinese translations when adding Russian.

## Chat features that already exist — do not reimplement

- **Workspace AGENTS.md**: a workspace bound to a conversation gets its root
  `AGENTS.md` (and the one in the current working directory, when that lies
  inside the workspace) appended to the system message of every request.
  `lib/core/services/workspace/workspace_agents_instructions.dart` reads it;
  `MessageBuilderService.injectWorkspacePrompt` injects it. Nothing is stored in
  the conversation, the assistant's system prompt is untouched, and a missing,
  empty, oversized or unreadable file is skipped silently.
- **Pending message queue**: submitting while a reply streams parks the message
  instead of rejecting it. `QueuedInputQueue` (`lib/features/home/controllers/`)
  owns the FIFO, `HomeViewModel` drains it when a conversation goes idle, and
  `_QueuedInputPanel` in `chat_input_bar.dart` shows order, edit and remove. A
  pending item can be edited in the composer through `QueuedMessageEditState`.

## Pre-commit checklist

```bash
dart format lib test
dart analyze --fatal-infos lib test integration_test
flutter test
python3 -m unittest discover -s tool -p 'test_android_only_policy.py' -v
python3 -m unittest discover -s tool -p 'test_verify_apk_arm64.py' -v
```

Format only changed Dart files. `pr-check.yml` enforces the existing analyzer,
tests and localization gates. `moru-android.yml` additionally builds one arm64
APK, runs Android JVM tests and inspects actual APK libraries/signature.

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
