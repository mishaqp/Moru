# Moru Russian UI and Android arm64 implementation plan

## Approved scope

User approved complete Russian presentation localization and one Android arm64-v8a APK, using the existing Flutter/ARB architecture. Base: `846af083621e9e6a59b1d30b89ed2468777d0491`. No agent/runtime redesign. Preserve English and Chinese source translations, existing tools, provider/model IDs, schemas, URLs, persisted values and user data. No iPhone/desktop/Nightly build or repair. Work on the isolated GitHub branch and verify in GitHub Actions.

## Task 1: inventory and baseline

- [ ] Read the exact English ARB, localization configuration, language selection/default persistence, Android resources, Gradle files and CI.
- [ ] Export the full English message catalog for translation, including ICU placeholders and descriptions. Inventory visible hardcoded strings in Android/mobile paths separately from model-facing prompts and diagnostics.
- [ ] Run the original analyzer/tests before production edits. Add a locale-contract check and verify it rejects a missing Russian ARB, then retain that check in final CI.

## Task 2: translate and connect Russian

- [ ] Create `lib/l10n/app_ru.arb` with the exact English message key set and Russian text, preserving placeholder identifiers/types, ICU variables and technical tokens.
- [ ] Review Russian plural forms (one/few/many/other), contextual terminology, dialogs, accessibility/tooltip text, provider/OAuth, MCP, workspace, skills, memory, backups, errors and notifications.
- [ ] Add Russian to existing language selectors. Default new installations to Russian without overriding an explicitly stored language or the system-language option.
- [ ] Move confirmed Android-visible hardcoded text into the existing localization mechanism. Do not translate protocol payloads or model-facing source prompts.
- [ ] Generate Dart using `flutter gen-l10n`; never hand-edit generated getters as a substitute for ARB.

## Task 3: one Android build

- [ ] Retain upstream non-Android source files but prevent its legacy multi-platform workflows from building in Moru.
- [ ] Provide an Android-only workflow, pinned to the project's required Flutter version. Compile only arm64-v8a and verify the APK's native-library ABI set.
- [ ] Preserve any established Moru application ID/certificate; if this is its first independent release, keep the identity and signing setup explicit rather than silently using a rotating debug certificate. Do not expose private keys in logs or source.

## Task 4: verification and integration

- [ ] Validate ARB key parity, duplicate keys, nonempty values, placeholder preservation and explicit technical-English exceptions.
- [ ] Add runtime/widget localization checks for representative screens and Russian plural cases, plus English fallback/selection.
- [ ] Run generation consistency, formatting of changed Dart files, `dart analyze --fatal-infos lib test integration_test`, all `flutter test`, Android unit tests and arm64 APK build.
- [ ] Inspect the final diff and remove temporary translation staging/automation. Open a PR and merge only on final-head green checks.
- [ ] Verify published APK package/version/ABI/signature and give the user its actual link. Any remaining untranslated paths, unrun checks or signing limitation must be reported, not concealed by a success claim.
