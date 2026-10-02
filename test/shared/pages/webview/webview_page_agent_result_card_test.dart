import 'dart:convert';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/browser_agent_tool.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/pages/webview/webview_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

/// Section 5 of the browser-overhaul plan: the Ask-AI result card must
/// survive past task completion, and a `browser_use` `done` activity (just
/// another logged activity, per Phase A) must never dismiss it on its own.
void main() {
  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  Widget agentApp(
    Widget child, {
    required BrowserAskAiBridge bridge,
    Locale locale = const Locale('en'),
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrowserAskAiBridge>.value(value: bridge),
      ChangeNotifierProvider<ToolApprovalService>(
        create: (_) => ToolApprovalService(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      theme: ThemeData(brightness: Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  testWidgets(
    'a done activity recorded while the result card is showing does not '
    'dismiss it, and it survives past task completion until the user '
    'dismisses it',
    (tester) async {
      final bridge = BrowserAskAiBridge();
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

      await tester.enterText(find.byType(TextField), 'summarize this page');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(requests, hasLength(1));
      bridge.reportOutcome(
        BrowserAskAiOutcome(
          requestId: requests.single,
          ok: true,
          answerText: 'The page is about flights.',
          conversationId: 'conv-1',
          assistantMessageId: 'msg-1',
        ),
      );
      await tester.pump();

      expect(find.textContaining('The page is about flights.'), findsOneWidget);

      // The browser_use `done` action is just another logged activity; it
      // must never itself dismiss the result card.
      BrowserAgentSession.instance.recordActivity(
        action: 'done',
        detail: 'Finished the task',
      );
      await tester.pump();

      expect(find.textContaining('The page is about flights.'), findsOneWidget);

      // Well past the panel's own transient "completed" hold duration --
      // the result card is a separate, persisted piece of state and must
      // still be there.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('The page is about flights.'), findsOneWidget);

      // Only an explicit dismiss removes it.
      await tester.tap(find.byTooltip('Dismiss answer'));
      await tester.pump();
      expect(find.textContaining('The page is about flights.'), findsNothing);
    },
  );

  testWidgets('action count follows the current page and retains its history', (
    tester,
  ) async {
    final bridge = BrowserAskAiBridge();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      bridge.dispose();
    });
    await tester.pumpWidget(
      agentApp(
        const WebViewPage(url: 'https://example.com', agentSession: true),
        bridge: bridge,
      ),
    );
    await tester.pump();
    await tester.pump();
    final session = BrowserAgentSession.instance;
    final id = session.recordActivity(action: 'observe');
    session.resolveActivity(id, BrowserActivityOutcome.ok);
    await tester.pump();
    expect(find.text('Actions · 1'), findsOneWidget);
    await session.controller!.loadRequest(
      Uri.parse('https://example.com/other'),
    );
    await tester.pump();
    expect(find.text('Actions'), findsOneWidget);
    final other = session.recordActivity(action: 'click');
    session.resolveActivity(other, BrowserActivityOutcome.ok);
    await tester.pump();
    expect(find.text('Actions · 1'), findsOneWidget);
    await session.controller!.goBack();
    await tester.pump();
    expect(find.text('Actions · 1'), findsOneWidget);
  });

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      '$locale result reserves height below a stable WebView under the app bar',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final bridge = BrowserAskAiBridge();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          bridge.dispose();
        });
        final requests = <String>[];
        bridge.requests.listen((request) => requests.add(request.id));
        await tester.pumpWidget(
          agentApp(
            const WebViewPage(url: 'https://m.vk.ru', agentSession: true),
            bridge: bridge,
            locale: locale,
          ),
        );
        await tester.pump();
        await tester.pump();
        final webview = find.byType(WebViewWidget);
        final initialRect = tester.getRect(webview);
        final element = tester.element(webview);
        final controller = tester
            .widget<WebViewWidget>(webview)
            .platform
            .params
            .controller;
        expect(initialRect.top, tester.getRect(find.byType(AppBar)).bottom);
        await tester.enterText(find.byType(TextField), 'summarize');
        await tester.pump();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(WebViewPage)),
        )!;
        await tester.tap(find.byTooltip(l10n.browserComposerSendTooltip));
        await tester.pump();
        bridge.reportOutcome(
          BrowserAskAiOutcome(
            requestId: requests.single,
            ok: true,
            answerText:
                'The first line of a long answer.\nThe second line.\nMore text.',
            conversationId: 'conv-geometry',
          ),
        );
        await tester.pump();
        final card = find.byType(BrowserAskAiResultCard);
        final reducedRect = tester.getRect(webview);
        expect(reducedRect.height, lessThan(initialRect.height));
        expect(reducedRect.bottom, lessThanOrEqualTo(tester.getRect(card).top));
        expect(tester.element(webview), same(element));
        expect(
          tester.widget<WebViewWidget>(webview).platform.params.controller,
          same(controller),
        );
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(webview).bottom,
          lessThanOrEqualTo(tester.getRect(card).top),
        );
        tester.view.viewInsets = const FakeViewPadding();
        tester.view.physicalSize = const Size(640, 320);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(webview).bottom,
          lessThanOrEqualTo(tester.getRect(card).top),
        );
        expect(tester.element(webview), same(element));
        expect(
          tester.widget<WebViewWidget>(webview).platform.params.controller,
          same(controller),
        );
      },
    );
  }

  testWidgets(
    'new-tab AI action counts belong to that tab after manual switching',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final bridge = BrowserAskAiBridge();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          bridge.dispose();
        });
        await tester.pumpWidget(
          agentApp(
            const WebViewPage(url: 'https://example.com', agentSession: true),
            bridge: bridge,
          ),
        );
        await tester.pump();
        await tester.pump();
        final session = BrowserAgentSession.instance;
        final firstId = session.activeTabId!;
        final newTabResult = await tester.runAsync(
          () => BrowserAgentTool.execute({
            'action': 'new_tab',
            'url': 'https://example.com',
          }, conversationId: 'conv-tabs'),
        );
        await tester.pumpAndSettle();
        expect(
          (jsonDecode(newTabResult!) as Map)['ok'],
          isTrue,
          reason: newTabResult,
        );
        final secondId = session.activeTabId!;
        expect(secondId, isNot(firstId));
        expect(
          session.activityCountForPage('https://example.com'),
          1,
          reason: '${session.tabs.value} / $newTabResult',
        );
        expect(
          find.text('Actions · 1'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(' / '),
        );
        await tester.runAsync(() => session.switchTab(firstId));
        await tester.pumpAndSettle();
        expect(find.text('Actions'), findsOneWidget);
        // Capture the original tab before a current action resolves, then switch
        // manually. Its result must never count against the second tab.
        final current = session.recordActivity(action: 'open');
        final captured = session.activityPageKey(
          'https://example.com',
          tabId: firstId,
        );
        await tester.runAsync(() => session.switchTab(secondId));
        session.resolveActivity(
          current,
          BrowserActivityOutcome.ok,
          destinationPageKey: captured,
          destinationCaptured: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('Actions · 1'), findsOneWidget);
        await tester.runAsync(() => session.switchTab(firstId));
        await tester.pumpAndSettle();
        expect(find.text('Actions · 1'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'an outcome for an unrecognized/mismatched request id is never shown',
    (tester) async {
      final bridge = BrowserAskAiBridge();

      await tester.pumpWidget(
        agentApp(
          const WebViewPage(url: 'https://example.com', agentSession: true),
          bridge: bridge,
        ),
      );
      await tester.pump();
      await tester.pump();

      // No submit happened on this page; an outcome for some other id
      // must never be shown.
      bridge.reportOutcome(
        const BrowserAskAiOutcome(
          requestId: 'not-mine',
          ok: true,
          answerText: 'should never appear',
          conversationId: 'conv-1',
        ),
      );
      await tester.pump();

      expect(find.textContaining('should never appear'), findsNothing);
    },
  );
}
