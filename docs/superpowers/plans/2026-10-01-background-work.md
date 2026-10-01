# Moru Stage 2 Background Work Implementation Plan

> **For agentic workers:** use superpowers:executing-plans for integration and
> superpowers:dispatching-parallel-agents for independent file ownership.

**Goal:** Protect live Android assistant/workspace execution and recover
interrupted chats honestly, with persistent FIFO and actionable notifications.

**Architecture:** Existing single native FGS/FlutterEngine, existing generation
run database, atomic queue metadata, native notification receiver into the live
ToolApprovalService. No new dependencies or database schema.

**Tech Stack:** Flutter/Dart, Drift SQLite, Kotlin Android services and channels,
NotificationCompat, existing Robolectric/JUnit tests.

**Spec:** ../specs/2026-10-01-background-work-design.md

## Global Constraints

- Android-only, one arm64 APK; preserve SDK, signing, data and saved settings.
- PR base claude/moru-v0-1-16-audit-s69yji; no direct push to master or base.
- Do not skip, weaken or retry unchanged failing tests. Real-IO widget waits
  observe a condition with a bounded iteration count.
- All new strings in app_en, app_ru, app_zh, app_zh_Hans, app_zh_Hant ARB;
  run flutter gen-l10n and check desiredFileName.txt.
- Known ACP secrets never reach notification text or native DTOs.
- No automatic replay of interrupted prompts, tools or permission decisions.
- Full AGENTS.md checklist before commits; English commit messages; Russian
  docs/releases/v0.1.47.md with measured exit codes/counts and device limits.

## Review Focus

Inspect cross-chat/run identity, atomic queue acknowledgement/consumption,
late callbacks, native owner release, privacy updates, startup honesty and
Android policy assumptions. Review actual evidence, not inferred device success.

## Task 1: Native foreground and notification runtime

Owned files: android/app/src/main/AndroidManifest.xml; background Kotlin
GenerationForegroundService, BackgroundRuntime and new approval receiver;
related native JVM tests.

1. Add tests for specialUse and balanced owner/wake-lock Stop/exit behaviour.
2. Declare SPECIAL_USE and accurate subtype; runtime type only API 34+.
3. Add native syncApprovals/showResult methods to app.mobile_background.
   Approval target: approvalId, conversationId, generationRunId,
   assistantMessageId. Actions send approvalAction to the retained main engine
   and require a typed resolved/stale acknowledgement. No new engine.
4. Use unique notification tag and Intent data per run/approval; private
   visibility; authenticated Allow/Deny; stale action cannot target successor.
5. Add backgroundRestricted/LowPowerStandby status; use existing settings intents.
6. Run native tests if toolchain can be installed in external cache; APK remains CI.

## Task 2: Durable FIFO and interrupted-chat recovery

Owned files: queued_input_queue.dart, HomeViewModel, HomePageController,
ChatService, ChatDatabaseRepository, AcpChatSessions, timeline recovery UI;
corresponding queue/repository/ACP/controller tests.

1. Write crash-boundary tests before implementation.
2. Persist versioned per-chat queue/edit state in chat_storage_meta_rows;
   restore before initial drain; consume queuedInputId inside beginSendGeneration.
3. Preserve drafts on write failure; gate interrupted-chat auto drain; surface
   existing interrupted run alongside partial content and explicit continuation.
4. Await AcpChatTurn.onSession before prompt; reuse load/resume. Restore context
   without automatic prompt replay where appropriate.
5. Send integration instructions for ChatActions/ACP bridge to their owner;
   keep whole-current-run persistence and flush-all-active lifecycle semantics.
6. Run focused persistence, queue, ACP and chat-race tests; report exact results.

## Task 3: Dart approval/result notifications

Owned files: ToolApprovalService, mobile_background.dart, NotificationService,
ChatActions, AcpChatBridge, relevant tool-handler ownership propagation and
main.dart binding; matching Dart tests. Coordinate integration with Task 2.

1. Add strict UUID/chat/run/message approval resolver and race tests.
2. Capture immutable generation ownership at handler creation/invocation;
   reject cancelled generation callbacks. Never infer from selected chat.
3. Mirror live approval snapshots through syncApprovals; reconcile visibility,
   lifecycle, settings and privacy; native action resolves the same service.
4. Post ready/error after persisted terminal state, with native run-tag identity;
   suppress cancelled/unpersisted/visible results and avoid raw error previews.
5. Add queuedInputId forwarding and awaited session-id persistence integration
   requested by Task 2; flush all active runs on pause as best-effort enhancement.
6. Test concurrent chats, stale/duplicate/Stop/trust, process loss, privacy and
   permission grants without automatic permission prompts.

## Task 4: Background command/server owners

Owned files: keep_alive.dart, WorkspaceToolsService, MiniAppServers and matching
tests. Do not change the native channel contract independently of Task 1.

1. Tests acquire before start and release on launch failure, exit, Stop,
   restart and last-server-owner disposal.
2. Tie each background shell and live server to the common native service.
3. Native Stop cancels actual processes; no hidden idle keeper or leaked owner.
4. Emit safe shell ready/error outcome without serializing commands/output.
5. Run focused command/server tests and inspect ownership races.

## Task 5: Contextual battery help and Markdown anchors

Owned files: new small background hint widget, MobileBackgroundSettings/settings
page, source ARBs/generated localizations; file_link_resolver.dart,
markdown_with_highlight.dart and link tests.

1. Test hint only with active work and a concrete risk; durable dismiss;
   preserve explicit saved settings; no unsolicited OS permission/settings UI.
2. Reuse existing battery/autostart settings routes and truthful wording.
3. Reject pure #fragment as a file source and stop link handler early for it;
   retain file/HTTP fragments and traversal protection, bound/unbound chat tests.
4. Translate all five ARBs, generate localization, inspect missing-message report.

## Task 6: Integration, release notes, full checks and PR

1. Review combined diff with independent scoped reviewer; fix material findings.
2. Format only changed Dart; run analyzer, full Flutter tests and all three Python
   suites exactly as AGENTS.md; capture actual totals/return codes.
3. Update Russian release notes and device smoke plan; document specialUse
   rationale with official sources and Play review boundary.
4. Commit coherent tasks after green checklist; push feature branch; create PR
   against exact audit base. Report SHAs, PR and unverified Vivo/Pixel behaviour.
