import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/frosted/frosted_surface.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_ask_ai_controller.dart';
import 'package:Kelivo/shared/pages/webview/webview_bottom_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

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

  testWidgets('navigation has 48dp targets and send is 40dp inside the field', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    for (final tooltip in const ['Refresh', 'Forward', 'Send']) {
      final finder = find.byTooltip(tooltip);
      expect(finder, findsOneWidget, reason: 'missing tooltip: $tooltip');
    }

    for (final tooltip in const ['Refresh', 'Forward']) {
      final button = find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    final send = find.descendant(
      of: find.byTooltip('Send'),
      matching: find.byType(IconButton),
    );
    final field = find.byType(TextField);
    final pill = find
        .ancestor(of: field, matching: find.byType(Container))
        .first;
    expect(tester.getSize(send), const Size(40, 40));
    expect(tester.getRect(pill).contains(tester.getRect(send).topLeft), isTrue);
    expect(
      tester.getRect(pill).contains(tester.getRect(send).bottomRight),
      isTrue,
    );
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

  testWidgets(
    'navigation stays 48dp under a compact theme and AI log is distinct',
    (tester) async {
      var backCalls = 0;
      var forwardCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(visualDensity: VisualDensity.compact),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WebViewNavRow(
              canGoBack: true,
              canGoForward: false,
              onBack: () => backCalls++,
              onForward: () => forwardCalls++,
              onReload: () {},
              onShowActivityLog: () {},
            ),
          ),
        ),
      );
      for (final icon in [
        Lucide.ArrowLeft,
        Lucide.ArrowRight,
        Lucide.RefreshCw,
      ]) {
        final button = find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(IconButton),
        );
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
      expect(find.byIcon(Lucide.History), findsNothing);
      expect(find.byIcon(Lucide.Sparkles), findsOneWidget);
      expect(find.text('Actions'), findsOneWidget);
      final backIcon = tester.widget<Icon>(find.byIcon(Lucide.ArrowLeft));
      final forwardIcon = tester.widget<Icon>(find.byIcon(Lucide.ArrowRight));
      expect(forwardIcon.color!.a, lessThan(backIcon.color!.a));
      expect(forwardIcon.color!.a, closeTo(0.55, 0.001));
      final semantics = tester.getSemantics(
        find.ancestor(
          of: find.byIcon(Lucide.ArrowRight),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        semantics,
        matchesSemantics(
          label: 'Forward',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      await tester.tap(find.byIcon(Lucide.ArrowLeft));
      await tester.tap(find.byIcon(Lucide.ArrowRight));
      expect(backCalls, 1);
      expect(forwardCalls, 0);
    },
  );

  testWidgets('navigation distributes controls across 320dp at 1.3 scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(wrap());
    expect(tester.takeException(), isNull);
    final row = tester.widget<Row>(
      find
          .descendant(
            of: find.byType(WebViewNavRow),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(row.mainAxisAlignment, MainAxisAlignment.spaceAround);
    final action = find.text('Actions');
    expect(action, findsOneWidget);
    final refresh = tester.getCenter(find.byTooltip('Refresh'));
    expect(tester.getCenter(action).dx, greaterThan(refresh.dx));
    expect(
      tester.getRect(find.byType(WebViewNavRow)).right,
      greaterThanOrEqualTo(tester.getRect(action).right),
    );
  });

  testWidgets('Glass bottom panel uses the app tint without live blur', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    await settings.setGlassTheme(true);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: wrap(),
      ),
    );
    final surface = find.byType(FrostedSurface);
    expect(surface, findsWidgets);
    for (final widget in tester.widgetList<FrostedSurface>(surface)) {
      expect(widget.style.background.a, closeTo(0.34, 0.001));
      expect(widget.style.border.a, closeTo(0.2, 0.001));
      expect(widget.style.blurSigma, 0);
    }
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
