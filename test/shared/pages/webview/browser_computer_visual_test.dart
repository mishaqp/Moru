// Deterministic native Flutter screenshots. The WebView is a blank test fake:
// these images review app chrome, never native web-page rendering.
// Capture with --dart-define=COMPUTER_QA_DIR=/absolute/path and
// --dart-define=COMPUTER_QA_PHASE=after. The original pre-Computer harness
// captured the historical before PNGs before product edits; see the README.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/workspace/task_plan.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/chat_gradient_background.dart';
import 'package:Kelivo/features/chat/widgets/computer_sheet.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/computer_status_panel.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_activity_log_sheet.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/theme/app_theme_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_webview_platform.dart';

const _directory = String.fromEnvironment('COMPUTER_QA_DIR');
const _phase = String.fromEnvironment(
  'COMPUTER_QA_PHASE',
  defaultValue: 'after',
);
const _compare = bool.fromEnvironment('COMPUTER_QA_COMPARE');
const _conversation = 'computer-visual-fixture';

Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  if (_directory.isEmpty && !_compare) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final raster = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      final encoded = bytes!.buffer.asUint8List();
      if (_compare) {
        await expectLater(
          encoded,
          matchesGoldenFile(
            '../../../../docs/design/browser/$_phase-$name.png',
          ),
        );
      } else {
        await Directory(_directory).create(recursive: true);
        await File('$_directory/$_phase-$name.png').writeAsBytes(encoded);
      }
    } finally {
      raster.dispose();
    }
  });
}

void _device(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<SettingsProvider> _settings(bool glass) async {
  final settings = SettingsProvider(createBusinessTestPreferences());
  addTearDown(settings.dispose);
  await settings.loaded;
  await settings.setThemeMode(ThemeMode.dark);
  await settings.setAppFontSystemFamily('Roboto');
  if (glass) await settings.setGlassTheme(true);
  return settings;
}

Widget _host({
  required SettingsProvider settings,
  required GlobalKey key,
  required Widget home,
  ToolRunRegistry? runs,
  TaskPlanRegistry? plans,
}) => RepaintBoundary(
  key: key,
  child: MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<BrowserAskAiBridge>(
        create: (_) => BrowserAskAiBridge(),
      ),
      ChangeNotifierProvider<ToolApprovalService>(
        create: (_) => ToolApprovalService(),
      ),
      if (runs != null)
        ChangeNotifierProvider<ToolRunRegistry>.value(value: runs),
      if (plans != null)
        ChangeNotifierProvider<TaskPlanRegistry>.value(value: plans),
    ],
    child: AppThemeBuilder(
      builder: (context, themes) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: themes.mode,
        home: home,
      ),
    ),
  ),
);

Widget _composerFixture({List<ComputerStep> steps = const []}) => Builder(
  builder: (context) {
    final glass = context.watch<SettingsProvider>().glassTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: glass ? Colors.transparent : cs.surface,
      appBar: AppBar(title: const Text('Project assistant')),
      body: ChatGradientBackgroundHost(
        enabled: false,
        active: glass,
        accent: cs.primary,
        child: Stack(
          children: [
            if (glass) const Positioned.fill(child: ChatGradientBackground()),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Review the project and run its checks.'),
                  ),
                ),
                ComposerStatusStrip(
                  conversationId: _conversation,
                  generating: true,
                  responseId: 'visual-response',
                  steps: steps,
                  onStop: () {},
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Message',
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);

List<ComputerStep> _steps(ToolRun run) => [
  ComputerStep(
    id: 'command',
    toolName: 'shell',
    arguments: const {'command': 'flutter test test/shared'},
    content: '24 tests passed\nRunning browser checks',
    metadata: const {
      'workspace': {'durationMs': 12000},
    },
    loading: true,
    run: run,
  ),
  ComputerStep(
    id: 'browser',
    toolName: 'browser_use',
    arguments: const {'action': 'observe', 'url': 'https://example.com'},
    content: jsonEncode({
      'ok': true,
      'url': 'https://example.com',
      'title': 'Example Domain',
      'text': 'This domain is for use in illustrative examples in documents.',
    }),
  ),
  ComputerStep(
    id: 'file',
    toolName: 'read_file',
    arguments: const {'path': '/workspace/README.md'},
    content:
        '# Sample project\n\nRun the shared browser checks before release.',
  ),
];

Widget _sheetFixture(List<ComputerStep> steps) => Builder(
  builder: (context) {
    final glass = context.watch<SettingsProvider>().glassTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: glass ? Colors.transparent : cs.surface,
      appBar: AppBar(title: const Text('Project assistant')),
      body: ChatGradientBackgroundHost(
        enabled: false,
        active: glass,
        accent: cs.primary,
        child: Stack(
          children: [
            if (glass) const Positioned.fill(child: ChatGradientBackground()),
            Center(
              child: TextButton(
                onPressed: () => showComputerSheet(
                  context,
                  steps: steps,
                  conversationId: _conversation,
                  initialStepId: 'command',
                ),
                child: const Text('Open Computer'),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

void _activities() {
  final session = BrowserAgentSession.instance;
  final start = DateTime.utc(2026, 10, 2, 12);
  session.recentActivityNotifier.value = [
    BrowserActivity(
      id: 'open',
      action: 'open',
      detail: 'https://example.com',
      outcome: BrowserActivityOutcome.ok,
      startedAt: start,
      finishedAt: start.add(const Duration(seconds: 1)),
    ),
    BrowserActivity(
      id: 'observe',
      action: 'observe',
      outcome: BrowserActivityOutcome.ok,
      startedAt: start.add(const Duration(seconds: 1)),
      finishedAt: start.add(const Duration(seconds: 2)),
    ),
    BrowserActivity(
      id: 'click',
      action: 'click',
      outcome: BrowserActivityOutcome.running,
      startedAt: start.add(const Duration(seconds: 2)),
    ),
  ];
  session.currentActivity.value = session.recentActivityNotifier.value.last;
}

void main() {
  setUpAll(() async {
    // A real font keeps review PNGs readable; use the bundled font in CI.
    final fontPath =
        Platform.environment['COMPUTER_QA_FONT'] ??
        'dependencies/gpt_markdown/lib/fonts/JetBrainsMono-Regular.ttf';
    final data = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in ['Roboto', 'sans-serif', 'monospace']) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  setUp(() {
    installFakeWebViewPlatform();
    FakeWebViewPlatform.onCreated = (controller) {
      controller.title = 'Example Domain';
    };
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
    BrowserAgentSession.instance.setOwnerConversationId(_conversation);
  });

  tearDown(() => FakeWebViewPlatform.onCreated = null);

  for (final glass in [false, true]) {
    final themeName = glass ? 'glass' : 'dark';
    testWidgets('$themeName fullscreen browser and menu evidence', (
      tester,
    ) async {
      _device(tester);
      final settings = await _settings(glass);
      final key = GlobalKey();
      await tester.pumpWidget(
        _host(
          settings: settings,
          key: key,
          home: const WebViewPage(
            url: 'https://example.com',
            agentSession: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('example.com'), findsOneWidget);
      await _snapshot(tester, key, '$themeName-browser');

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Desktop site'), findsOneWidget);
      await _snapshot(tester, key, '$themeName-menu');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$themeName composer strip evidence', (tester) async {
      _device(tester);
      final settings = await _settings(glass);
      final key = GlobalKey();
      final runs = ToolRunRegistry();
      final run = runs.start(
        'command',
        'shell',
        command: 'flutter test test/shared',
        conversationId: _conversation,
        runtimeRunId: 'visual-command',
      );
      run.appendStdout(
        Uint8List.fromList(
          utf8.encode('24 tests passed\nRunning browser checks'),
        ),
      );
      final plans = TaskPlanRegistry()
        ..set(
          _conversation,
          const TaskPlan([
            PlanStep('Read project', PlanStepStatus.completed),
            PlanStep('Run browser checks', PlanStepStatus.inProgress),
            PlanStep('Review result', PlanStepStatus.pending),
          ]),
        );
      await tester.pumpWidget(
        _host(
          settings: settings,
          key: key,
          runs: runs,
          plans: plans,
          home: _composerFixture(steps: _phase == 'before' ? [] : _steps(run)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('flutter test test/shared'), findsOneWidget);
      if (_phase != 'before') {
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(ComputerStatusPanel.panelKey));
        expect(rect.bottom, lessThanOrEqualTo(844));
        expect(rect.width, greaterThan(300));
      }
      await _snapshot(tester, key, '$themeName-strip');
      await tester.pumpWidget(const SizedBox.shrink());
      run.dispose();
      runs.dispose();
      plans.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$themeName original activity sheet evidence', (tester) async {
      _device(tester);
      final settings = await _settings(glass);
      final key = GlobalKey();
      _activities();
      await tester.pumpWidget(
        _host(
          settings: settings,
          key: key,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Browser')),
              body: Center(
                child: TextButton(
                  onPressed: () => showActivityLogSheet(context),
                  child: const Text('Open activity'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open activity'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Click'), findsWidgets);
      await _snapshot(
        tester,
        key,
        '$themeName-${_phase == 'before' ? 'sheet' : 'activity-sheet'}',
      );
      expect(tester.takeException(), isNull);
    });

    if (_phase != 'before') {
      for (final scenario in [
        (
          name: 'sheet',
          size: const Size(390, 844),
          textScale: 1.0,
          keyboard: 0.0,
        ),
        (
          name: 'sheet-keyboard-130',
          size: const Size(390, 844),
          textScale: 1.3,
          keyboard: 600.0,
        ),
        (
          name: 'sheet-landscape-130',
          size: const Size(844, 390),
          textScale: 1.3,
          keyboard: 0.0,
        ),
      ]) {
        testWidgets('$themeName Computer ${scenario.name} evidence', (
          tester,
        ) async {
          _device(tester, size: scenario.size, textScale: scenario.textScale);
          final settings = await _settings(glass);
          final key = GlobalKey();
          final run = ToolRun(
            toolCallId: 'command',
            toolName: 'shell',
            command: 'flutter test test/shared',
            runtimeRunId: 'visual-command',
            startedAt: DateTime.utc(2026, 10, 2, 12),
          );
          run.appendStdout(
            Uint8List.fromList(
              utf8.encode('24 tests passed\nRunning browser checks'),
            ),
          );
          final steps = _steps(run);
          await tester.pumpWidget(
            _host(settings: settings, key: key, home: _sheetFixture(steps)),
          );
          tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
          await tester.pump();
          await tester.tap(find.text('Open Computer'));
          await tester.pumpAndSettle();
          expect(find.text('1 / 3'), findsOneWidget);
          final pager = tester.getRect(
            find.byKey(const ValueKey('computer-next-step')),
          );
          expect(
            pager.bottom,
            lessThanOrEqualTo(scenario.size.height - scenario.keyboard / 2),
          );
          await _snapshot(tester, key, '$themeName-${scenario.name}');
          if (scenario.name == 'sheet') {
            await tester.tap(find.byKey(const ValueKey('computer-next-step')));
            await tester.pumpAndSettle();
            expect(find.text('2 / 3'), findsOneWidget);
            await _snapshot(tester, key, '$themeName-sheet-browser');
            await tester.tap(find.byKey(const ValueKey('computer-next-step')));
            await tester.pumpAndSettle();
            expect(find.text('3 / 3'), findsOneWidget);
            await _snapshot(tester, key, '$themeName-sheet-file');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          run.dispose();
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('$themeName browser with keyboard at text scale 1.3', (
        tester,
      ) async {
        _device(tester, textScale: 1.3);
        final settings = await _settings(glass);
        final key = GlobalKey();
        await tester.pumpWidget(
          _host(
            settings: settings,
            key: key,
            home: const WebViewPage(
              url: 'https://example.com',
              agentSession: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField), 'Review project checks');
        await tester.showKeyboard(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _snapshot(tester, key, '$themeName-browser-keyboard-130');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$themeName landscape browser at text scale 1.3', (
        tester,
      ) async {
        _device(tester, size: const Size(844, 390), textScale: 1.3);
        final settings = await _settings(glass);
        final key = GlobalKey();
        await tester.pumpWidget(
          _host(
            settings: settings,
            key: key,
            home: const WebViewPage(
              url: 'https://example.com',
              agentSession: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _snapshot(tester, key, '$themeName-browser-landscape-130');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
