# Computer and browser implementation plan

> For agentic workers: use executing-plans with independent work dispatched by dispatching-parallel-agents; root integrates and reviews the branch.

Goal: implement the user's Android Computer strip/sheet and browser polish.
Architecture: adapt existing tool snapshots, attach live ToolRun state, use stable selection and a bounded thumbnail cache; preserve live controller ownership.
Tech stack: Flutter, Provider, CustomBottomSheet, existing lucide/animation/image dependencies.
Spec: ../specs/2026-10-02-computer-browser-design.md

## Global constraints
- Android/mobile only. Existing capabilities, approvals and data remain available.
- Base PR: claude/moru-v0-1-16-audit-s69yji.
- New text: EN, RU, zh, zh_Hans, zh_Hant; flutter gen-l10n.
- Scoped development tests; full AGENTS.md checklist once before push.

## Review focus
- Simultaneous background runs and a user viewing an older running step.
- New user message, changed chat, generation cancellation and late results.
- Authentication URLs and secret values in parameters, results, copy and thumbnails.
- Keyboard/landscape/textScaler 1.3, narrow screens and long labels.
- Browser minimize/expand/settings toggles with no reload or second controller.

### Task 1: model, selection and bounded previews
Files: lib/features/chat/models/computer_step.dart, computer_step_selection.dart; lib/core/services/browser/browser_thumbnail_cache.dart; scoped model/cache tests.
Interfaces: ComputerStep({required id, required toolName, arguments, content, metadata, loading, run}); ComputerStepKind.browser/command/file/image/tool. ComputerStepSelection.update(List<ComputerStep>), select(int), latest(), index, selected. BrowserThumbnailCache per-chat lookup/capture from existing screenshots.
- [x] Add failing tests for classification, redaction, stable selection, limits and per-chat isolation.
- [x] Implement model/cache with existing APIs; no capture in UI.
- [x] Run touched tests and format changed files.

### Task 2: Computer sheet and thumbnail widget
Files: lib/features/chat/widgets/computer_sheet.dart, computer_step_thumbnail.dart; test/shared/widgets/computer_sheet_test.dart.
Interfaces: showComputerSheet(context, {required List<ComputerStep> steps, String? conversationId, String? initialStepId, Listenable? updates, List<ComputerStep> Function()? readSteps}); ComputerStepThumbnail(step, conversationId).
- [x] Add failing navigation, action, live update, secrets and scaled/landscape tests.
- [x] Implement full-width CustomBottomSheet at 0.85 height, all-step pager, latest, header action and status.
- [x] Run touched tests and format.

### Task 3: browser polish
Files: webview_top_bar.dart, webview_bottom_panel.dart, browser_mini_window.dart, webview_activity_log_sheet.dart, app_overlays.dart, settings_provider.dart, browser_settings_page.dart; existing scoped tests.
- [x] Capture before PNGs before edits.
- [x] Add failing defects 1–5 and setting/controller handoff tests.
- [x] Fix Material root, grouped menu/toggle/icons, full-width activity sheet, 48dp navigation, opt-in floating mode.
- [x] Verify scoped tests.

### Task 4: composer and message integration
Files: composer_status_strip.dart, chat_input_section.dart, home_page.dart, chat_message_widget.dart and focused source/scope helpers.
- [x] Add failing browser/command/file strip, selection and collapse tests.
- [x] Adapt live tools and restored payloads; use ToolRunRegistry for background jobs; wrap message tool details in common response scope.
- [x] Wire stop to generation and running jobs; preserve plan.
- [x] Verify test/shared and test/features/home plus touched tests.

### Task 5: visual evidence and delivery
Files: five ARB, generated output, docs/design/browser/*.png, AGENTS.md, docs/releases/v0.1.47.md, version build.
- [x] Generate translations; capture dark/glass browser/menu/strip/sheet before-after PNGs.
- [x] Review all changed code and fix substantive issues with regression tests.
- [x] Format changed files and run full AGENTS.md checklist once.
- [x] Commit, push feature branch, create PR to specified base; record PR and phone checks.

Delivery: [PR #86](https://github.com/mishaqp/Moru/pull/86), branch
`codex/computer-panel-browser-polish`, application commit `477f5d29`.
Android release validation was dispatched with `publish=false`:
[CI run](https://github.com/mishaqp/Moru/actions/runs/37057796214).
Phone scenarios and actual local verification results are in
`docs/releases/v0.1.47.md`; all 30 PNGs are listed in
`docs/design/browser/README.md`.
