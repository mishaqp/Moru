# Moru: Russian Android presentation

## Scope

This code-only integration takes the reviewed `lib`, `test` and `tool` source trees from `0a936685f1549057838bbc0702afafc1c9f23448` onto Android-only master `63aa1f33bf90d1d9d986ccb52e2f07dcfd2e1028`. It does NOT change `.github`, workflow permissions, Android build targets, signing identity, application ID or dependencies. The previous attempt to change workflows was denied; those changes are excluded rather than retried through another mechanism. PR #2 remains historical until this replacement is verified.

The catalog contains 3572 English and 3572 Russian messages, using Flutter ARB/gen-l10n. English and Chinese remain supported. New installations default to Russian; an explicitly saved locale or follow-system preference is preserved.

Covered presentation: chat, settings, assistants, provider/OAuth dialogs, models, MCP, workspace/terminal, skills, memory, search, backups, diagnostics labels, tooltips/accessibility, notifications, palette names, local speech-model descriptions and code-block fallback labels.

Provider/model/tool IDs, download URLs, code-fence language identifiers, protocol schemas, raw server diagnostics, user content and model-facing source prompts are not translated. User-created names remain data.

## Verification and limits

Previous combined-source run 35097982347 passed ARB parity and placeholder checks, 6 validator tests, 4 Android-only policy tests, 6 APK-validator tests, 33 locale/settings navigation tests and the full Dart analyzer. Its later push failed on workflow permission; no successful final integration or APK is inferred from that run.

The reusable validator is `python3 tool/check_moru_ru.py`; its mutation tests are `python3 tool/test_check_moru_ru.py`. The existing PR Checks and Moru Android arm64 workflows must verify this final code-only branch: generated l10n consistency, changed Dart formatting, full analyzer and Flutter suite, Android JVM tests and a real single-arm64 APK. Read actual final-head checks before claiming completion. No physical-device test is claimed.

## Distribution

PR #1's Android-only configuration is unchanged. Exactly one arm64-v8a APK; no iOS/desktop/Nightly product. Embedded Linux/PRoot, terminal/PTY and STDIO MCP remain Android features.

A debug CI artifact is not a stable signed release. Stable publication requires the separately configured permanent signing identity and public certificate pin; no rotating debug key may replace it. This localization change does not rename or re-sign an already installed application.
