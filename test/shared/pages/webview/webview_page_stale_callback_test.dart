import 'dart:async';

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

  testWidgets(
    'a slow title fetch from an old navigation is discarded once a newer '
    'navigation has started',
    (tester) async {
      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      final fake = FakeWebViewPlatform.lastCreated!;
      final slow = Completer<Object>();
      fake.jsHandlerAsync = (script) => slow.future;

      // Trigger a fresh onPageFinished for the current page, starting the
      // (slow) title fetch.
      fake.simulateCommittedNavigation('https://example.com/a');
      await tester.pump();

      // A newer navigation starts before the slow fetch resolves.
      fake.jsHandlerAsync = null;
      fake.jsHandler = (script) => '"Page B"';
      fake.simulateCommittedNavigation('https://example.com/b');
      await tester.pump();
      await tester.pump();

      // Now let the stale fetch for page A resolve.
      slow.complete('"Page A (stale)"');
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();

      expect(find.text('Page A (stale)'), findsNothing);
    },
  );
}
