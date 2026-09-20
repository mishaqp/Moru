import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

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

  testWidgets('a main-frame error shows the error screen with Retry, and '
      'Retry re-triggers a load', (tester) async {
    await tester.pumpWidget(
      agentApp(
        const WebViewPage(url: 'https://example.com', agentSession: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    final fake = FakeWebViewPlatform.lastCreated!;
    fake.simulateWebResourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'net::ERR_NAME_NOT_RESOLVED',
        errorType: WebResourceErrorType.hostLookup,
        isForMainFrame: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('browser_main_frame_error')),
      findsOneWidget,
    );

    final reloadsBefore = fake.reloadCount;
    await tester.tap(find.byKey(const ValueKey('browser_error_retry_button')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('browser_main_frame_error')),
      findsNothing,
    );
    expect(fake.reloadCount, reloadsBefore + 1);
  });

  testWidgets(
    'a subresource error does not show the error screen and still logs '
    'to the console',
    (tester) async {
      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      FakeWebViewPlatform.lastCreated!.simulateWebResourceError(
        const WebResourceError(
          errorCode: -6,
          description: 'net::ERR_CONNECTION_REFUSED',
          isForMainFrame: false,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('browser_main_frame_error')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Console Logs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ERR_CONNECTION_REFUSED'), findsOneWidget);
    },
  );

  testWidgets('a null isForMainFrame is treated conservatively (no '
      'full-page error)', (tester) async {
    await tester.pumpWidget(
      agentApp(
        const WebViewPage(url: 'https://example.com', agentSession: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    FakeWebViewPlatform.lastCreated!.simulateWebResourceError(
      const WebResourceError(errorCode: -1, description: 'unknown'),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('browser_main_frame_error')),
      findsNothing,
    );
  });
}
