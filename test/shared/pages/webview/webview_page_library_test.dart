import 'dart:async';
import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_library.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_library_sheet.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart' show rootNavigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  final session = BrowserAgentSession.instance;
  late Directory dir;
  final original = BrowserLibrary.instance;

  setUp(() async {
    installFakeWebViewPlatform();
    dir = Directory.systemTemp.createTempSync('browser-library-ui');
    BrowserLibrary.instance = BrowserLibrary(directory: () async => dir);
    // Read the (empty) files in real time; in the widget test the lists
    // then change at once, before their writes finish.
    await BrowserLibrary.instance.load();
  });

  tearDown(() {
    BrowserLibrary.instance = original;
    dir.deleteSync(recursive: true);
  });

  Future<void> openBrowser(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
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
          home: const Scaffold(body: Text('chat')),
        ),
      ),
    );
    rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const WebViewPage(url: 'https://moon.example/', agentSession: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  // The library was loaded in real time, so what follows its loads runs
  // in the real event loop: give it a turn, then build.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the star bookmarks the page, and a visited page is in the '
      'history and opens from it', (tester) async {
    await openBrowser(tester);
    final library = BrowserLibrary.instance;

    expect(find.text('moon.example'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('browser_bookmark_star')));
    await settle(tester);
    expect(library.isBookmarked('https://moon.example/'), isTrue);

    // The page finished loading, so it is in the history.
    expect([
      for (final e in library.history.value) e.url,
    ], contains('https://moon.example/'));
    unawaited(library.recordVisit('https://mars.example/', 'Mars'));
    await settle(tester);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Mars'), findsOneWidget);

    await tester.enterText(find.byKey(BrowserLibrarySheet.searchKey), 'mars');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BrowserLibrarySheet),
        matching: find.textContaining('moon.example'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Mars'));
    await tester.pumpAndSettle();
    expect(await session.controller!.currentUrl(), 'https://mars.example/');
  });
}
