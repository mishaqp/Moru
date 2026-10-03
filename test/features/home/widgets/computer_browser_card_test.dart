import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_sheet.dart';
import 'package:Kelivo/features/chat/widgets/frosted/frosted_surface.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/computer_status_panel.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_webview_platform.dart';

const _preview = ValueKey('computer-browser-preview');
const _thumbnail = ValueKey('computer-step-thumbnail:browser');
const _url = 'https://ya.ru/search';
const _chat = 'browser-card-chat';

ComputerStep _browserStep() => ComputerStep(
  id: 'browser',
  toolName: 'browser_use',
  arguments: {'action': 'read', 'url': _url},
  loading: true,
);

Future<SettingsProvider> _settings({bool glass = false}) async {
  final settings = SettingsProvider(createBusinessTestPreferences());
  await settings.loaded;
  if (glass) await settings.setGlassTheme(true);
  addTearDown(settings.dispose);
  return settings;
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required SettingsProvider settings,
  List<ComputerStep>? steps,
  double scale = 1,
  double keyboard = 0,
  Locale locale = const Locale('en'),
  bool asComposerStrip = false,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(create: (_) => BrowserAskAiBridge()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        theme: ThemeData.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: AppSnackBarOverlay(child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: asComposerStrip
                ? ComposerStatusStrip(
                    conversationId: _chat,
                    responseId: 'browser-card-response',
                    generating: true,
                    steps: steps ?? [_browserStep()],
                  )
                : ComputerStatusPanel(
                    steps: steps ?? [_browserStep()],
                    generating: true,
                    conversationId: _chat,
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color _previewFill(WidgetTester tester, Finder preview) {
  Color? fill;
  tester.element(preview).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      fill = (widget.decoration as BoxDecoration).color;
    } else if (widget is ColoredBox) {
      fill = widget.color;
    }
    return fill == null;
  });
  expect(fill, isNotNull, reason: 'The globe tile paints its themed fill.');
  return fill!;
}

void main() {
  setUp(() {
    installFakeWebViewPlatform();
    FakeWebViewPlatform.onCreated = null;
    addTearDown(() async {
      FakeWebViewPlatform.onCreated = null;
      final browser = BrowserAgentSession.instance;
      await browser.closeMinimized();
      browser.pageUrl.value = null;
      browser.currentActivity.value = null;
    });
  });

  testWidgets('preview resumes the parked browser without loading its page', (
    tester,
  ) async {
    final settings = await _settings();
    await _pumpPanel(tester, settings: settings);
    final created = <FakeWebViewController>[];
    FakeWebViewPlatform.onCreated = created.add;
    rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const WebViewPage(url: _url, agentSession: true),
      ),
    );
    await tester.pumpAndSettle();
    final browser = BrowserAgentSession.instance;
    browser.setOwnerConversationId(_chat);
    final parked = browser.controller!;
    final native = parked.platform as FakeWebViewController;
    final loads = List<String>.of(native.loadedUrls);
    final reloads = native.reloadCount;
    expect(loads, [_url]);
    expect(created, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('browser_minimize')));
    await tester.pumpAndSettle();
    expect(browser.minimized.value, isTrue);
    expect(find.byType(WebViewPage), findsNothing);
    expect(find.byKey(_preview).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(_preview));
    await tester.pumpAndSettle();
    expect(find.byType(WebViewPage), findsOneWidget);
    expect(find.byType(ComputerSheet), findsNothing);
    expect(browser.controller, same(parked));
    expect(browser.minimized.value, isFalse);
    expect(native.loadedUrls, loads);
    expect(native.reloadCount, reloads);
    expect(created, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('the browser card title opens its response Computer sheet', (
    tester,
  ) async {
    final settings = await _settings();
    await _pumpPanel(tester, settings: settings);
    expect(find.byKey(_preview), findsOneWidget);
    await tester.tap(find.text('Browser · ya.ru'));
    await tester.pumpAndSettle();
    expect(find.byType(ComputerSheet), findsOneWidget);
    expect(find.byType(WebViewPage), findsNothing);
    expect(find.text('Computer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the domain pill opens the Computer sheet outside the preview', (
    tester,
  ) async {
    final settings = await _settings();
    await _pumpPanel(tester, settings: settings);
    final domain = find.text('ya.ru');
    expect(domain, findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_preview), matching: domain),
      findsNothing,
    );
    await tester.tap(domain);
    await tester.pumpAndSettle();
    expect(find.byType(ComputerSheet), findsOneWidget);
    expect(find.byType(WebViewPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'Dark Glass browser card fits 320dp with landscape keyboard at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final settings = await _settings(glass: true);
        await _pumpPanel(
          tester,
          settings: settings,
          scale: scale,
          keyboard: 100,
          locale: const Locale('ru'),
          steps: [
            ComputerStep(
              id: 'command',
              toolName: 'shell',
              arguments: {'command': 'pwd'},
              content: '/workspace',
            ),
            _browserStep(),
          ],
        );
        final panel = tester.getRect(find.byKey(ComputerStatusPanel.panelKey));
        final preview = tester.getRect(find.byKey(_preview));
        final title = tester.getRect(find.text('Браузер · ya.ru'));
        expect(tester.getSize(find.byKey(_thumbnail)), const Size(64, 40));
        if (scale == 1) expect(panel.height, inInclusiveRange(56, 60));
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(320));
        expect(panel.top, greaterThanOrEqualTo(0));
        expect(panel.bottom, lessThanOrEqualTo(140));
        expect(preview.left, greaterThanOrEqualTo(panel.left));
        expect(preview.right, lessThanOrEqualTo(title.left));
        expect(title.right, lessThanOrEqualTo(panel.right));
        expect(find.byKey(_preview).hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(ComputerStatusPanel.panelKey),
            matching: find.byType(FrostedSurface),
          ),
          findsWidgets,
        );
        for (final key in [
          ComputerStatusPanel.previousKey,
          ComputerStatusPanel.nextKey,
        ]) {
          final target = tester.getRect(find.byKey(key));
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
          expect(target.left, greaterThanOrEqualTo(preview.right));
          expect(target.right, lessThanOrEqualTo(panel.right));
          expect(target.bottom, lessThanOrEqualTo(panel.bottom));
          expect(target.center.dy, closeTo(panel.center.dy, 0.1));
        }
        expect(find.byTooltip('Остановить'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Dark Glass composer browser fits its 296dp panel with keyboard at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final settings = await _settings(glass: true);
        await _pumpPanel(
          tester,
          settings: settings,
          scale: scale,
          keyboard: 100,
          locale: const Locale('ru'),
          asComposerStrip: true,
        );
        expect(find.byType(ComposerStatusStrip), findsOneWidget);
        final strip = tester.getRect(find.byType(ComposerStatusStrip));
        final panel = tester.getRect(find.byKey(ComputerStatusPanel.panelKey));
        final preview = tester.getRect(find.byKey(_preview));
        final title = tester.getRect(find.text('Браузер · ya.ru'));
        expect(strip.width, 320);
        expect(panel.width, 296);
        expect(panel.left, 12);
        expect(panel.right, 308);
        expect(panel.bottom, strip.bottom - 6);
        expect(strip.top, greaterThanOrEqualTo(0));
        expect(strip.bottom, lessThanOrEqualTo(140));
        if (scale == 1) expect(panel.height, inInclusiveRange(56, 60));
        expect(tester.getSize(find.byKey(_thumbnail)), const Size(64, 40));
        expect(preview.left, greaterThanOrEqualTo(panel.left));
        expect(preview.right, lessThanOrEqualTo(title.left));
        expect(title.right, lessThanOrEqualTo(panel.right));
        expect(find.byKey(_preview).hitTestable(), findsOneWidget);
        expect(find.text('Браузер · ya.ru').hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(ComputerStatusPanel.panelKey),
            matching: find.byType(FrostedSurface),
          ),
          findsWidgets,
        );
        for (final key in [
          ComputerStatusPanel.previousKey,
          ComputerStatusPanel.nextKey,
        ]) {
          final target = tester.getRect(find.byKey(key));
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
          expect(target.left, greaterThanOrEqualTo(preview.right));
          expect(target.right, lessThanOrEqualTo(panel.right));
          expect(target.bottom, lessThanOrEqualTo(panel.bottom));
          expect(target.center.dy, closeTo(panel.center.dy, 0.1));
        }
        expect(find.byTooltip('Остановить'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the blank globe tile uses the dark theme with Glass enabled', (
    tester,
  ) async {
    final settings = await _settings();
    await _pumpPanel(tester, settings: settings);
    final globe = find.descendant(
      of: find.byKey(_thumbnail),
      matching: find.byIcon(Lucide.Globe),
    );
    expect(globe, findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_thumbnail), matching: find.byType(Text)),
      findsNothing,
    );
    final plainFill = _previewFill(tester, globe);
    final plainIcon = tester.widget<Icon>(globe).color!;
    final cs = Theme.of(tester.element(globe)).colorScheme;
    expect(plainFill.a, 1);
    expect(plainFill, cs.surfaceContainerHighest);
    expect(plainIcon, cs.onSurfaceVariant);

    await settings.setGlassTheme(true);
    await tester.pumpAndSettle();
    expect(_previewFill(tester, globe), plainFill);
    expect(tester.widget<Icon>(globe).color, plainIcon);
    expect(tester.takeException(), isNull);
  });
}
