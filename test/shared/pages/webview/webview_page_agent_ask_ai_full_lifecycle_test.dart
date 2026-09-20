import 'dart:async';

import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/generation_terminal_event.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_runner.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

/// Drives the browser's floating "Ask AI" composer through the *real*
/// `runBrowserAskAiRequest` — wired to the same `BrowserAskAiBridge` the
/// widget listens to, exactly the way `HomePageController._setupBrowserAskAi`
/// wires it in production — instead of a test calling `bridge.reportOutcome`
/// by hand with an already-finished answer. That shortcut is what let the
/// premature-outcome bug (send() reporting a still-empty placeholder as the
/// final answer) go unnoticed: it never exercised the actual timing between
/// send() returning and the real generation finishing.
void main() {
  const assistant = Assistant(id: 'assistant-1', name: 'Assistant');
  final conversation = Conversation(
    id: 'conv-1',
    title: 'Chat',
    assistantId: assistant.id,
  );

  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  Widget agentApp(Widget child, {required BrowserAskAiBridge bridge}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BrowserAskAiBridge>.value(value: bridge),
          ChangeNotifierProvider<ToolApprovalService>(
            create: (_) => ToolApprovalService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );

  testWidgets(
    'the result card only appears once this run\'s real terminal event '
    'arrives -- not the moment send() itself returns -- and the panel stays '
    'busy (Stop available, no card) for everything in between, including '
    'tool activity',
    (tester) async {
      final bridge = BrowserAskAiBridge();
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final sendCalls = <String>[];
      final cancelCalls = <String?>[];

      // Mirrors HomePageController._setupBrowserAskAi: listens to the
      // bridge's requests and drives the real runner against a fake send()
      // that returns the moment generation *starts* -- an empty placeholder
      // message, exactly like ChatActions.sendMessage does in production --
      // never the finished reply.
      bridge.requests.listen((request) {
        unawaited(
          runBrowserAskAiRequest(
            bridge: bridge,
            request: request,
            currentConversationId: conversation.id,
            getConversation: (id) =>
                id == conversation.id ? conversation : null,
            getAssistantById: (id) => id == assistant.id ? assistant : null,
            currentAssistant: null,
            terminalEvents: terminal.stream,
            send:
                ({
                  required input,
                  required conversation,
                  required assistant,
                  required onGenerationStarted,
                }) async {
                  sendCalls.add(request.id);
                  onGenerationStarted('assistant-msg-1');
                  return ChatActionResult.success(
                    ChatMessage(
                      id: 'assistant-msg-1',
                      conversationId: conversation.id,
                      role: 'assistant',
                      content: '',
                    ),
                    generationRunId: 'run-1',
                  );
                },
            cancel: (conversationId, {expectedMessageId}) async {
              cancelCalls.add(expectedMessageId);
            },
          ),
        );
      });

      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
          bridge: bridge,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byType(TextField),
        'what is this page about?',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      // send() has already returned (synchronously, in this fake) -- proving
      // that alone must never surface an answer.
      expect(sendCalls, ['browser-ask-ai-0']);
      expect(find.text('what is this page about?'), findsNothing);
      expect(find.byTooltip('Dismiss answer'), findsNothing);
      expect(find.text('Starting…'), findsOneWidget);
      // Stop must still be reachable while nothing has finished yet.
      expect(
        tester
            .widget<IconButton>(
              find
                  .descendant(
                    of: find.byTooltip('Stop'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNotNull,
      );

      // A browser_use tool call happens while the model is still working --
      // must move starting -> running, and must still not surface any card.
      BrowserAgentSession.instance.recordActivity(
        action: 'click',
        detail: 'Clicked the summary button',
      );
      await tester.pump();
      expect(find.text('Working…'), findsOneWidget);
      expect(find.byTooltip('Dismiss answer'), findsNothing);

      // Still nothing reported to the bridge itself.
      var outcomeReported = false;
      bridge.outcomes.first.then((_) => outcomeReported = true);
      await tester.pump();
      expect(outcomeReported, isFalse);

      // Only now does the real generation actually finish, with the chat's
      // own final ChatMessage as the source of truth for the answer text.
      terminal.add(
        GenerationTerminalEvent(
          conversationId: conversation.id,
          assistantMessageId: 'assistant-msg-1',
          generationRunId: 'run-1',
          terminalState: GenerationRunState.completed,
          message: ChatMessage(
            id: 'assistant-msg-1',
            conversationId: conversation.id,
            role: 'assistant',
            content: 'This page is about flight prices.',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('This page is about flight prices.'),
        findsOneWidget,
      );
      expect(cancelCalls, isEmpty);
    },
  );

  testWidgets(
    'Stop tapped while generation is still running eventually clears the '
    'busy state once the run\'s own cancelled terminal event arrives, and '
    'never shows a result card',
    (tester) async {
      final bridge = BrowserAskAiBridge();
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final cancelCalls = <String?>[];

      bridge.requests.listen((request) {
        unawaited(
          runBrowserAskAiRequest(
            bridge: bridge,
            request: request,
            currentConversationId: conversation.id,
            getConversation: (id) =>
                id == conversation.id ? conversation : null,
            getAssistantById: (id) => id == assistant.id ? assistant : null,
            currentAssistant: null,
            terminalEvents: terminal.stream,
            send:
                ({
                  required input,
                  required conversation,
                  required assistant,
                  required onGenerationStarted,
                }) async {
                  onGenerationStarted('assistant-msg-2');
                  return ChatActionResult.success(
                    ChatMessage(
                      id: 'assistant-msg-2',
                      conversationId: conversation.id,
                      role: 'assistant',
                      content: '',
                    ),
                    generationRunId: 'run-2',
                  );
                },
            cancel: (conversationId, {expectedMessageId}) async {
              cancelCalls.add(expectedMessageId);
            },
          ),
        );
      });

      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
          bridge: bridge,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'summarize');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      expect(find.text('Stopping…'), findsOneWidget);
      expect(cancelCalls, ['assistant-msg-2']);

      terminal.add(
        GenerationTerminalEvent(
          conversationId: conversation.id,
          assistantMessageId: 'assistant-msg-2',
          generationRunId: 'run-2',
          terminalState: GenerationRunState.cancelled,
          message: ChatMessage(
            id: 'assistant-msg-2',
            conversationId: conversation.id,
            role: 'assistant',
            content: '',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Stopping…'), findsNothing);
      expect(find.byTooltip('Dismiss answer'), findsNothing);
    },
  );
}
