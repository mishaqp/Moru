# Moru product target: Android arm64-v8a only

The user explicitly selected **Android only**, one **arm64-v8a APK**. Do not
build, release or repair iOS, macOS, Windows, desktop Linux or Web products.
Do not add scheduled/Nightly builds. A Linux-hosted CI runner is a build machine,
not a Linux application target.

## Preserved Android features

Keep the embedded PRoot/Linux environment, workspace, terminal/PTY, skills and
STDIO MCP. They are functionality of the Android app, not separate Linux apps.
Upstream non-Android source files remain inert for merge compatibility; their
build workflows have been removed, not replaced with disabled matrix options.

## Build contract

- Flutter 3.44.9, existing pinned dependency/toolchain versions.
- `flutter build apk --debug --target-platform=android-arm64` for PR validation.
- `flutter build apk --release --target-platform=android-arm64` for signed release.
- No split-per-ABI or universal/multi-ABI build.
- Android `ndk.abiFilters`, CMake ABI and PRoot downloads all select arm64-v8a.
- The four existing arm64 PRoot SHA-256 pins are unchanged.
- Verify actual ZIP library paths **and ELF architecture**, not the APK filename.
- Keep the existing full Dart analyzer/Flutter test PR gates and add Android JVM
  tests plus an actual arm64 build.

The Android workflow exports one APK and a separate diagnostic report archive.
PR/debug artifacts are for validation; they are not permanent stable releases.
Release signing is manual, master-only and requires the existing keystore secrets
plus `.github/moru-signing-cert-sha256.txt`. It fails rather than silently choosing
a new signing key. Never commit a private key or print it in logs.

## Integration with Russian localization

This change is deliberately separate from `feat/russian-android-arm64` so it does
not overwrite its in-progress ARB translations. Import this PR's build constraints
when integrating that branch. It does not claim Russian localization is complete,
and does not change application ID/version/signing identity as a side effect.
Before the first independently branded Moru release, verify the chosen identity,
full RU locale contract and permanent signature together.

## Regression evidence

Four policy tests first failed on the original repository configuration in run
35090292966 (job 104774740632): multi-ABI Gradle, multi-ABI PRoot fetching and pins,
and seven inherited non-Android/multi-platform workflows. Final-head successful
checks and a verified APK are required before merge; this document is not a claim
of a completed on-device test.
