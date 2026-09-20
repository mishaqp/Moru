import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_bottom_panel.dart';
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
    'tapping Stop only cancels the Ask-AI request -- it never closes the '
    'window or tears down the session',
    (tester) async {
      final bridge = BrowserAskAiBridge();
      final cancelled = <String>[];
      bridge.cancellations.listen(cancelled.add);

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

      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());

      expect(cancelled, hasLength(1));
      // The page is still here: the session is still attached and the
      // bottom panel (hence the whole Scaffold) is still on screen.
      expect(BrowserAgentSession.instance.isAttached, isTrue);
      expect(find.byType(WebViewBottomPanel), findsOneWidget);
    },
  );
}
