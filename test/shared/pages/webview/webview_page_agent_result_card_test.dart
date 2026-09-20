import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

/// Section 5 of the browser-overhaul plan: the Ask-AI result card must
/// survive past task completion, and a `browser_use` `done` activity (just
/// another logged activity, per Phase A) must never dismiss it on its own.
void main() {
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
    'a done activity recorded while the result card is showing does not '
    'dismiss it, and it survives past task completion until the user '
    'dismisses it',
    (tester) async {
      final bridge = BrowserAskAiBridge();
      final requests = <String>[];
      bridge.requests.listen((r) => requests.add(r.id));

      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
          bridge: bridge,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'summarize this page');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(requests, hasLength(1));
      bridge.reportOutcome(
        BrowserAskAiOutcome(
          requestId: requests.single,
          ok: true,
          answerText: 'The page is about flights.',
          conversationId: 'conv-1',
          assistantMessageId: 'msg-1',
        ),
      );
      await tester.pump();

      expect(find.textContaining('The page is about flights.'), findsOneWidget);

      // The browser_use `done` action is just another logged activity; it
      // must never itself dismiss the result card.
      BrowserAgentSession.instance.recordActivity(
        action: 'done',
        detail: 'Finished the task',
      );
      await tester.pump();

      expect(find.textContaining('The page is about flights.'), findsOneWidget);

      // Well past the panel's own transient "completed" hold duration --
      // the result card is a separate, persisted piece of state and must
      // still be there.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('The page is about flights.'), findsOneWidget);

      // Only an explicit dismiss removes it.
      await tester.tap(find.byTooltip('Dismiss answer'));
      await tester.pump();
      expect(find.textContaining('The page is about flights.'), findsNothing);
    },
  );

  testWidgets(
    'an outcome for an unrecognized/mismatched request id is never shown',
    (tester) async {
      final bridge = BrowserAskAiBridge();

      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
          bridge: bridge,
        ),
      );
      await tester.pump();
      await tester.pump();

      // No submit happened on this page; an outcome for some other id
      // must never be shown.
      bridge.reportOutcome(
        const BrowserAskAiOutcome(
          requestId: 'not-mine',
          ok: true,
          answerText: 'should never appear',
          conversationId: 'conv-1',
        ),
      );
      await tester.pump();

      expect(find.textContaining('should never appear'), findsNothing);
    },
  );
}
