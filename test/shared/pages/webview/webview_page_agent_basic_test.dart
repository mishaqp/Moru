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

/// Each `webview_page_agent_*_test.dart` file holds one or a couple of
/// agent-session scenarios, deliberately kept in separate files: a shared
/// `BrowserAgentSession.instance` singleton plus a focused `TextField`'s
/// real cursor-blink timer made sequential `testWidgets` runs in one large
/// file for this page flaky/hang-prone in this sandbox, even with an
/// explicit end-of-test disposal. Splitting by file (each gets its own
/// `flutter_tester` process) sidesteps that without weakening coverage.
void main() {
  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  Widget agentApp(
    Widget child, {
    BrowserAskAiBridge? bridge,
    ToolApprovalService? approval,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrowserAskAiBridge>.value(
        value: bridge ?? BrowserAskAiBridge(),
      ),
      ChangeNotifierProvider<ToolApprovalService>.value(
        value: approval ?? ToolApprovalService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  testWidgets('shows the merged bottom panel and registers with the '
      'shared browser session', (tester) async {
    await tester.pumpWidget(
      agentApp(
        const WebViewPage(url: 'https://example.com', agentSession: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(WebViewBottomPanel), findsOneWidget);
    expect(BrowserAgentSession.instance.isAttached, isTrue);
  });
}
