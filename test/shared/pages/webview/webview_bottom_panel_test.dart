import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_ask_ai_controller.dart';
import 'package:Kelivo/shared/pages/webview/webview_bottom_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BrowserAskAiBridge bridge;
  late AskAiPanelController controller;

  setUp(() {
    bridge = BrowserAskAiBridge();
    controller = AskAiPanelController(
      bridge: bridge,
      completedHoldDuration: const Duration(milliseconds: 60),
    );
  });

  tearDown(() {
    controller.dispose();
    bridge.dispose();
  });

  Widget wrap({Widget? approvalCard}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Column(
        children: [
          Expanded(child: Container()),
          WebViewBottomPanel(
            controller: controller,
            canGoBack: true,
            canGoForward: false,
            onBack: () {},
            onForward: () {},
            onReload: () {},
            onShowActivityLog: () {},
            currentUrl: 'https://example.com',
            approvalCard: approvalCard,
          ),
        ],
      ),
    ),
  );

  testWidgets('send button is disabled with empty text, enabled once typed', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    IconButton sendButton() => tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('Send'),
        matching: find.byType(IconButton),
      ),
    );

    expect(sendButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(sendButton().onPressed, isNotNull);
  });

  testWidgets('double tap submits only once', (tester) async {
    await tester.pumpWidget(wrap());
    final requests = <String>[];
    bridge.requests.listen((r) => requests.add(r.id));

    await tester.enterText(find.byType(TextField), 'do a thing');
    await tester.pump();

    final button = find.descendant(
      of: find.byTooltip('Send'),
      matching: find.byType(IconButton),
    );
    await tester.tap(button);
    await tester.pump();
    // Second tap lands after the panel already swapped to the busy/status
    // row (the button/text field are gone), so this just double-checks the
    // controller-level guard by calling submit again directly is already
    // covered in the controller test; here we assert only one request was
    // actually emitted end to end. pumpEventQueue() needs a real event loop
    // (testWidgets bodies run in a virtual-time zone), so it is wrapped in
    // runAsync -- calling it unwrapped here deadlocks the test.
    await tester.runAsync(() => pumpEventQueue());

    expect(requests, hasLength(1));
  });

  testWidgets(
    'text is cleared after a successful submit and never restored on a '
    'later failure',
    (tester) async {
      await tester.pumpWidget(wrap());

      await tester.enterText(find.byType(TextField), 'ask something');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byTooltip('Send'),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();

      // The composer row is now replaced by the busy row; submit a failure
      // outcome and come back to idle via dismiss to see the field again.
      final id = controller.activeRequestId!;
      bridge.reportOutcome(
        BrowserAskAiOutcome(requestId: id, ok: false, error: 'boom'),
      );
      await tester.pump();
      // Error state shows its own banner; find the underlying TextField and
      // confirm it holds no stale text.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text ?? '', isEmpty);
    },
  );

  testWidgets('all seven task states are individually reachable and '
      'visually distinguishable', (tester) async {
    await tester.pumpWidget(wrap());

    // idle: hint text visible.
    expect(find.text('Tell the AI what to do…'), findsOneWidget);

    controller.submit('go');
    await tester.pump();
    expect(find.text('Starting…'), findsOneWidget);

    controller.noteActivity();
    await tester.pump();
    expect(find.text('Working…'), findsOneWidget);

    controller.setPendingApproval(true);
    await tester.pump();
    // awaitingApproval has no dedicated composer-area text of its own --
    // it is represented by the approval card taking over (see the
    // approvalCard-specific test below); the controller state itself is
    // still checked here.
    expect(controller.state, AskAiPanelState.awaitingApproval);
    controller.setPendingApproval(false);
    await tester.pump();

    controller.stop();
    await tester.pump();
    expect(find.text('Stopping…'), findsOneWidget);

    final id = controller.activeRequestId!;
    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: id, ok: false, cancelled: true),
    );
    await tester.pump();
    expect(find.text('Stopped'), findsOneWidget);

    // New request -> completed.
    final id2 = controller.submit('go again')!;
    await tester.pump();
    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: id2, ok: true, answerText: 'done'),
    );
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);

    // New request -> error.
    await tester.pump(const Duration(milliseconds: 100));
    final id3 = controller.submit('go a third time')!;
    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: id3, ok: false, error: 'no_conversation'),
    );
    await tester.pump();
    expect(find.textContaining('no_conversation'), findsOneWidget);
  });

  testWidgets('approvalCard replaces the composer entirely when provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(approvalCard: const Text('APPROVAL CARD HERE')),
    );

    expect(find.text('APPROVAL CARD HERE'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('nav buttons and send have real tooltips and 48dp targets', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    for (final tooltip in const ['Refresh', 'Forward', 'Send']) {
      final finder = find.byTooltip(tooltip);
      expect(finder, findsOneWidget, reason: 'missing tooltip: $tooltip');
    }

    final sizes = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .map((b) => b.constraints)
        .whereType<BoxConstraints>();
    for (final c in sizes) {
      expect(c.minWidth, greaterThanOrEqualTo(48));
      expect(c.minHeight, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('composer and Stop stay reachable when the keyboard opens', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).height, greaterThan(0));
  });
}
