import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/main.dart' show routeObserver;
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

/// `BrowserAgentSession.isRouteCurrent` is what
/// `MobileBackgroundCoordinator.finish()` ultimately consults (through
/// `consumeVisibleAskAiTask`) to decide whether the browser's own Ask-AI
/// surface is genuinely on screen right now -- this is the `WebViewPage`
/// side of that wiring: a real `RouteObserver` subscription, not a guess
/// from "is the session attached".
void main() {
  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  // WebViewPage is always pushed as its own route in production (never the
  // app's root route), so the test gives it a real placeholder root too --
  // otherwise closing it once the covering screen is popped back off would
  // try to pop a navigator's last remaining route, which Navigator.maybePop
  // (correctly) refuses, and the whole close path (dispose, unregister)
  // would never run.
  Widget agentApp() => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrowserAskAiBridge>(
        create: (_) => BrowserAskAiBridge(),
      ),
      ChangeNotifierProvider<ToolApprovalService>(
        create: (_) => ToolApprovalService(),
      ),
    ],
    child: MaterialApp(
      navigatorObservers: [routeObserver],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );

  testWidgets(
    'is current the moment the agent browser page is shown, false while '
    'covered by another screen, true again once that screen is popped, and '
    'false again once the browser itself closes',
    (tester) async {
      await tester.pumpWidget(agentApp());

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const WebViewPage(url: 'https://example.com', agentSession: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(BrowserAgentSession.instance.isRouteCurrent, isTrue);

      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covering screen')),
        ),
      );
      await tester.pumpAndSettle();

      expect(BrowserAgentSession.instance.isRouteCurrent, isFalse);

      navigator.pop();
      await tester.pumpAndSettle();

      expect(BrowserAgentSession.instance.isRouteCurrent, isTrue);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(BrowserAgentSession.instance.isRouteCurrent, isFalse);
      expect(BrowserAgentSession.instance.isAttached, isFalse);
    },
  );

  testWidgets(
    'a plain (non-agent) browser page never touches route visibility',
    (tester) async {
      BrowserAgentSession.instance.isRouteCurrent = false;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WebViewPage(url: 'https://example.com'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(BrowserAgentSession.instance.isRouteCurrent, isFalse);
    },
  );
}
