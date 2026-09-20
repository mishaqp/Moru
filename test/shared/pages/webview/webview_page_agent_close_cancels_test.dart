import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

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
    'closing the page while an Ask-AI task is running cancels it, and '
    'dispose leaves no dangling listener (no exception on a late outcome)',
    (tester) async {
      final bridge = BrowserAskAiBridge();
      final cancelled = <String>[];
      bridge.cancellations.listen(cancelled.add);
      // Listen for the submitted request BEFORE it is ever sent: bridge's
      // streams are broadcast-only (no replay), so a listener attached
      // after `submit()` -- e.g. inside a later `runAsync` block -- can
      // miss the event and hang forever awaiting it.
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

      await tester.enterText(find.byType(TextField), 'do something');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(requests, hasLength(1));
      final requestId = requests.single;

      // Close via the top bar's close button (manual close). The page has
      // nothing to pop back to (home:) and the Ask-AI request is still
      // "starting" (cancelForClose() only asks the bridge to cancel; it
      // does not itself resolve the request), so its busy spinner keeps
      // animating -- pumpAndSettle() would time out waiting for an
      // indeterminate animation to stop. A couple of plain pumps are
      // enough to let the close handler's own awaits resolve.
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump();

      await tester.runAsync(() => pumpEventQueue());

      expect(cancelled, [requestId]);

      // A late outcome for the now-closed page's request must not throw.
      expect(
        () => bridge.reportOutcome(
          BrowserAskAiOutcome(
            requestId: requestId,
            ok: true,
            answerText: 'late',
          ),
        ),
        returnsNormally,
      );
    },
  );
}
