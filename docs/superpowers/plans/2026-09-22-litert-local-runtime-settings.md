# LiteRT Local Runtime Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit the LiteRT-LM runtime options for an installed local model and reopen those settings from the model center.

**Architecture:** Extend the existing `ModelDetailSheet` for `ProviderKind.local`; keep local runtime options in the provider's existing model override. Preserve installed-file metadata via `modelSyncMetadata`. Add a settings action to each installed model row and localize new controls in all supported locales.

**Tech Stack:** Flutter, Dart, `SettingsProvider`, generated Flutter localization files, widget tests.

**Spec:** User-provided LiteRT model-center screenshot and PR #37 at https://github.com/mishaqp/Moru/pull/37; runtime override contract in `lib/core/services/api/providers/litert_local.dart`.

## Global Constraints

- Edit only models whose provider type is `ProviderKind.local`; preserve existing behavior for other providers.
- Persist the runtime keys already read by the LiteRT provider: `localBackend`, `localMaxNumTokens`, `localTemperature`, `localTopK`, `localTopP`, `localThinkingBudget`, `localThinking`, `localVision`, `localAudio`, `localTools`, and `localKeepLoaded`.
- Keep `localModelPath`, `localSha256`, file size, origin, and install timestamp when saving.
- Do not merge PR #37 or publish a stable release; its PR description keeps physical-device inference as a separate validation gate.

## Review Focus

- Reject zero/negative context and Top K, non-finite or negative temperature, Top P outside 0–1, and thinking budgets below -1; leave the sheet open on invalid input.
- Missing optional runtime fields must load the runtime's compatible defaults: CPU, 4096 context, temperature 1, Top K 64, Top P 0.95, thinking budget -1, audio off, model kept loaded.
- Reasoning, vision, and tools capability toggles must update the matching runtime flags.
- Editing the display name or runtime settings must not change the installed file identity.
- Non-local providers must continue to show their existing model-type, output-mode, and HTTP header/body controls.

---

### Task 1: Edit and persist LiteRT runtime options

**Files:**
- Modify: `lib/features/model/widgets/model_detail_sheet.dart`
- Modify: `lib/l10n/app_{en,ru,zh,zh_Hans,zh_Hant}.arb`
- Modify: `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_ru.dart`, `app_localizations_zh.dart`
- Create: `test/features/model/widgets/model_detail_sheet_local_runtime_settings_test.dart`

**Interfaces:**
- Consumes: local model overrides in `ProviderConfig.modelOverrides[modelId]`.
- Produces: local-only advanced controls; saving updates the existing model override and closes with `true`.

- [x] **Step 1: Write a widget test first.** Open `showModelDetailSheet` with a seeded local override, switch to Advanced, and assert the runtime context/backend fields exist. Enter context 8192, temperature 0.4, Top K 32, Top P 0.8 and budget 256; save and assert the persisted keys and original path/hash are retained.
- [x] **Step 2: Run the test to confirm the missing local runtime controls fail.** Run `flutter test test/features/model/widgets/model_detail_sheet_local_runtime_settings_test.dart`; expected: the context field key is not found.
- [x] **Step 3: Add local-only state, defaults, validation, and controls.** When `ProviderKind.local`, hide model type/output controls and show backend, context, temperature, Top K, Top P, thinking budget when reasoning is enabled, audio and keep-loaded switches. Map the existing input/ability choices to vision/tools/thinking flags and merge values over `modelSyncMetadata(prev)`.
- [x] **Step 4: Add matching strings to the five ARB files and generated localization Dart files.**
- [ ] **Step 5: Run the widget test and format/analyze checks.** Expected: the settings round-trip test passes and no formatter/analyzer errors are reported.
- [ ] **Step 6: Commit the task.**

### Task 2: Expose settings from the installed-model list

**Files:**
- Modify: `lib/features/provider/pages/local_models_page.dart`
- Create or extend: `test/features/provider/pages/local_models_page_test.dart`

**Interfaces:**
- Consumes: `InstalledLocalModel.id` and the existing `showModelDetailSheet`.
- Produces: an edit action alongside delete; saving refreshes the installed row.

- [ ] **Step 1: Write a widget test first.** Render an installed local model, tap the edit action, and assert the LiteRT runtime settings sheet opens.
- [ ] **Step 2: Run the test to confirm the settings action is absent.** Run `flutter test test/features/provider/pages/local_models_page_test.dart`; expected: no Edit tooltip is found.
- [ ] **Step 3: Add the edit action and refresh the page after a successful save.**
- [ ] **Step 4: Run the page test and the full Flutter suite.** Expected: both local-model widget tests pass; CI reports all project checks.
- [ ] **Step 5: Commit the task.**

## Completion Checklist

- [ ] Both settings editor and installed-row entry-point tests pass.
- [ ] Localization generation, formatting, and analysis pass.
- [ ] PR checks and arm64 build CI pass.
- [ ] PR remains open and no stable release is published pending physical-device inference validation.
