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

  Widget agentApp(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrowserAskAiBridge>(
        create: (_) => BrowserAskAiBridge(),
      ),
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

  testWidgets('a manual close (the top bar\'s close button) records the manual '
      'close reason', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      agentApp(
        WebViewPage(key: key, url: 'https://example.com', agentSession: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pumpAndSettle();

    // lastCloseReason is @visibleForTesting on the private State; read it
    // dynamically the way a `@visibleForTesting` member on a private
    // State is conventionally reached from a test.
    expect(
      (key.currentState as dynamic).lastCloseReason,
      WebViewCloseReason.manual,
    );
  });
}
