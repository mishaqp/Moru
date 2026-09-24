import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/chat_header_switcher.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/browser_mini_window.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart' show rootNavigatorKey;

import '../../../support/fake_webview_platform.dart';

const _minimize = ValueKey('browser_minimize');

void main() {
  late int chatTaps;

  setUp(() {
    installFakeWebViewPlatform();
    chatTaps = 0;
  });

  tearDown(() async {
    final session = BrowserAgentSession.instance;
    if (session.minimized.value) await session.closeMinimized();
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrowserAskAiBridge>(
        create: (_) => BrowserAskAiBridge(),
      ),
      ChangeNotifierProvider<ToolApprovalService>(
        create: (_) => ToolApprovalService(),
      ),
    ],
    child: MaterialApp(
      navigatorKey: rootNavigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => Overlay.wrap(
        child: Stack(children: [child!, const BrowserMiniWindow()]),
      ),
      home: Scaffold(
        appBar: AppBar(actions: const [ChatHeaderSwitcher()]),
        body: Align(
          alignment: Alignment.topLeft,
          child: TextButton(
            onPressed: () => chatTaps++,
            child: const Text('chat'),
          ),
        ),
      ),
    ),
  );

  Future<void> openBrowser(WidgetTester tester) async {
    await tester.tap(find.byKey(ChatHeaderSwitcher.browserKey));
    await tester.pumpAndSettle();
    expect(find.byType(WebViewPage), findsOneWidget);
  }

  testWidgets('minimize keeps the page alive and expand does not reload it', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    final session = BrowserAgentSession.instance;
    final fake = FakeWebViewPlatform.lastCreated!;
    final loadedUrl = await session.controller!.currentUrl();

    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    expect(find.byType(WebViewPage), findsNothing);
    expect(find.byKey(BrowserMiniWindow.windowKey), findsOneWidget);
    expect(session.isAttached, isTrue);
    expect(session.minimized.value, isTrue);

    // The chat under the mini window still takes taps.
    await tester.tap(find.text('chat'));
    expect(chatTaps, 1);

    await tester.tap(find.byKey(BrowserMiniWindow.expandKey));
    await tester.pumpAndSettle();

    expect(find.byType(WebViewPage), findsOneWidget);
    expect(find.byKey(BrowserMiniWindow.windowKey), findsNothing);
    expect(identical(FakeWebViewPlatform.lastCreated, fake), isTrue);
    expect(await session.controller!.currentUrl(), loadedUrl);
    expect(session.minimized.value, isFalse);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(session.isAttached, isFalse);
  });

  testWidgets('closing the mini window ends the session', (tester) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(BrowserMiniWindow.closeKey));
    await tester.pumpAndSettle();

    final session = BrowserAgentSession.instance;
    expect(find.byKey(BrowserMiniWindow.windowKey), findsNothing);
    expect(session.isAttached, isFalse);
    expect(session.minimized.value, isFalse);
  });

  testWidgets('browser_use close also closes a minimized browser', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    await BrowserAgentSession.instance.close();
    await tester.pumpAndSettle();

    expect(find.byKey(BrowserMiniWindow.windowKey), findsNothing);
    expect(BrowserAgentSession.instance.isAttached, isFalse);
  });

  testWidgets('the header shows only the browser without a workspace', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.byKey(ChatHeaderSwitcher.filesKey), findsNothing);
    expect(find.byKey(ChatHeaderSwitcher.terminalKey), findsNothing);
    expect(find.byKey(ChatHeaderSwitcher.browserKey), findsOneWidget);
  });
}
