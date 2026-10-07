import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/browser_mini_window.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/pages/webview/webview_tabs_sheet.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart' show rootNavigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewWidget;

import '../../../support/fake_webview_platform.dart';

void main() {
  final session = BrowserAgentSession.instance;

  setUp(installFakeWebViewPlatform);

  tearDown(() async {
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
      locale: const Locale('en'),
      navigatorKey: rootNavigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => Overlay.wrap(
        child: Stack(children: [child!, const BrowserMiniWindow()]),
      ),
      home: const Scaffold(body: Text('chat')),
    ),
  );

  // The page keys its WebViewWidget by the controller it shows.
  Object? shownController(WidgetTester tester) =>
      (tester
                  .widget<WebViewWidget>(
                    find.descendant(
                      of: find.byType(WebViewPage),
                      matching: find.byType(WebViewWidget),
                    ),
                  )
                  .key!
              as ObjectKey)
          .value;

  Future<void> openBrowser(WidgetTester tester) async {
    await tester.pumpWidget(app());
    rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const WebViewPage(
          url: 'https://first.example/',
          agentSession: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the tabs button opens the list; a new tab goes on screen and '
      'the first one comes back from the list', (tester) async {
    await openBrowser(tester);
    final first = session.controller!;
    expect(identical(shownController(tester), first), isTrue);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('browser_tabs_button')));
    await tester.pumpAndSettle();
    expect(find.text('Tabs: 1'), findsOneWidget);
    await tester.tap(find.byKey(BrowserTabsSheet.newTabKey));
    await tester.pumpAndSettle();

    expect(session.tabs.value, hasLength(2));
    final second = session.controller!;
    expect(identical(second, first), isFalse);
    expect(identical(shownController(tester), second), isTrue);
    expect(await second.currentUrl(), browserStartPage);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('browser_tabs_button')));
    await tester.pumpAndSettle();
    final firstId = session.tabs.value.first.id;
    await tester.tap(find.byKey(BrowserTabsSheet.tabKey(firstId)));
    await tester.pumpAndSettle();
    expect(identical(shownController(tester), first), isTrue);

    // Closing a tab from the list keeps the browser open.
    await tester.tap(find.byKey(const ValueKey('browser_tabs_button')));
    await tester.pumpAndSettle();
    final secondId = session.tabs.value.last.id;
    await tester.tap(find.byKey(BrowserTabsSheet.closeKey(secondId)));
    await tester.pumpAndSettle();
    expect(session.tabs.value, hasLength(1));
    expect(find.byType(WebViewPage), findsOneWidget);
  });

  testWidgets('the menu switches the site to its desktop version and back', (
    tester,
  ) async {
    await openBrowser(tester);
    final fake = FakeWebViewPlatform.lastCreated!;

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop site'));
    await tester.pumpAndSettle();
    expect(fake.userAgent, contains('X11; Linux x86_64'));
    expect(session.tabs.value.single.desktop, isTrue);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop site'));
    await tester.pumpAndSettle();
    expect(fake.userAgent, isNull);
  });

  testWidgets('a tab switch while minimized shows in the mini window', (
    tester,
  ) async {
    await openBrowser(tester);
    await tester.tap(find.byKey(const ValueKey('browser_minimize')));
    await tester.pumpAndSettle();
    expect(find.byKey(BrowserMiniWindow.windowKey), findsOneWidget);

    await tester.runAsync(
      () => session.newTab(url: 'https://second.example/', byAgent: true),
    );
    await tester.pumpAndSettle();
    final mini = tester.widget<WebViewWidget>(
      find.descendant(
        of: find.byKey(BrowserMiniWindow.windowKey),
        matching: find.byType(WebViewWidget),
      ),
    );
    expect(
      identical((mini.key! as ObjectKey).value, session.controller),
      isTrue,
    );
    expect(find.text('second.example'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('browser-mini-tab-count')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });
}
