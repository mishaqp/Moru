import 'dart:convert';
import 'dart:typed_data';

import 'package:Kelivo/core/services/api/tool_display_redaction.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_step_thumbnail.dart';
import 'package:Kelivo/features/home/widgets/computer_status_panel.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required List<ComputerStep> steps,
  bool generating = true,
  double scale = 1,
  double width = 320,
  Locale locale = const Locale('en'),
  String? conversationId,
  bool disableAnimations = true,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  locale: locale,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      size: Size(width, 240),
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(scale),
      viewInsets: const EdgeInsets.only(bottom: 100),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: width,
        child: ComputerStatusPanel(
          steps: steps,
          generating: generating,
          conversationId: conversationId,
        ),
      ),
    ),
  ),
);

ComputerStep _command({bool loading = true, String? content}) => ComputerStep(
  id: 'command',
  toolName: 'shell',
  arguments: {'command': 'echo "a long command with useful arguments"'},
  loading: loading,
  content: content,
);

void main() {
  testWidgets('a named step never borrows another live page identity', (
    tester,
  ) async {
    final session = BrowserAgentSession.instance;
    session.setOwnerConversationId('chat');
    session.pageStarted('https://wttr.in/');
    session.recordActivity(action: 'read');
    addTearDown(() {
      session.setOwnerConversationId(null);
      session.pageUrl.value = null;
      session.currentActivity.value = null;
    });
    final step = ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      arguments: {'url': 'https://ya.ru', 'action': 'open'},
      loading: true,
    );
    await tester.pumpWidget(_host(steps: [step], conversationId: 'chat'));
    await tester.pumpAndSettle();
    final thumbnail = tester.widget<ComputerStepThumbnail>(
      find.byType(ComputerStepThumbnail),
    );
    expect(thumbnail.browserPageUrl, isNull);
    expect(find.text('Browser · ya.ru'), findsOneWidget);
    expect(find.text('Opening…'), findsOneWidget);
    expect(find.text('wttr.in'), findsNothing);
  });

  testWidgets('an auth-page step never takes live public page labels', (
    tester,
  ) async {
    final session = BrowserAgentSession.instance;
    session.setOwnerConversationId('chat');
    session.pageStarted('https://ya.ru');
    session.recordActivity(action: 'read');
    addTearDown(() {
      session.setOwnerConversationId(null);
      session.pageUrl.value = null;
      session.currentActivity.value = null;
    });
    final step = ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      arguments: {'url': 'https://auth.openai.com/authorize', 'action': 'open'},
      loading: true,
    );
    await tester.pumpWidget(_host(steps: [step], conversationId: 'chat'));
    await tester.pumpAndSettle();
    expect(find.text('ya.ru'), findsNothing);
    expect(find.text('Browser · ya.ru'), findsNothing);
    expect(find.text('Opening…'), findsOneWidget);
  });

  testWidgets('browser done keeps the compact card while the reply is active', (
    tester,
  ) async {
    final step = ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      arguments: {'action': 'done'},
      content: '{"ok":true,"action":"done","summary":"finished"}',
    );
    await tester.pumpWidget(_host(steps: [step], locale: const Locale('ru')));
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Действие браузера'), findsNothing);
    expect(find.byType(ComputerStepThumbnail), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('browser card fits 320dp landscape at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final step = ComputerStep(
        id: 'browser',
        toolName: 'browser_use',
        arguments: {'action': 'navigate', 'url': 'https://ya.ru'},
        loading: true,
      );
      await tester.pumpWidget(
        _host(steps: [step], scale: scale, locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (scale == 1) {
        expect(
          tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height,
          lessThanOrEqualTo(60),
        );
      }
      expect(
        tester.getSize(
          find.byKey(const ValueKey('computer-step-thumbnail:browser')),
        ),
        const Size(64, 40),
      );
      expect(
        find.byKey(const ValueKey('computer-browser-preview')),
        findsOneWidget,
      );
      expect(find.byTooltip('Остановить'), findsNothing);
    });
  }

  testWidgets('browser address dot tracks running done error and stopped', (
    tester,
  ) async {
    for (final status in ['running', 'done', 'error', 'stopped']) {
      final step = ComputerStep(
        id: 'browser',
        toolName: 'browser_use',
        arguments: {'action': 'read', 'url': 'https://ya.ru'},
        loading: status == 'running',
        content: status == 'error' ? '{"ok":false}' : '{"ok":true}',
        metadata: status == 'stopped'
            ? {
                'computer': {'status': 'stopped'},
              }
            : null,
      );
      await tester.pumpWidget(_host(steps: [step]));
      await tester.pumpAndSettle();
      final dot = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('computer-browser-status-dot')),
      );
      expect((dot.decoration as BoxDecoration).color, switch (status) {
        'running' => const Color(0xFF3B82F6),
        'done' => const Color(0xFF22C55E),
        'error' => const Color(0xFFEF4444),
        _ => const Color(0xFF9CA3AF),
      });
    }
  });

  testWidgets('browser dot pulses only during work and honors reduced motion', (
    tester,
  ) async {
    ComputerStep step(bool loading) => ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      arguments: {'action': 'read', 'url': 'https://ya.ru'},
      loading: loading,
    );
    Finder pulse() => find.ancestor(
      of: find.byKey(const ValueKey('computer-browser-status-dot')),
      matching: find.byType(Animate),
    );
    await tester.pumpWidget(
      _host(steps: [step(true)], disableAnimations: false),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(pulse(), findsOneWidget);
    await tester.pumpWidget(
      _host(steps: [step(false)], disableAnimations: false),
    );
    await tester.pumpAndSettle();
    expect(pulse(), findsNothing);
    await tester.pumpWidget(_host(steps: [step(true)]));
    await tester.pumpAndSettle();
    expect(pulse(), findsNothing);
    await tester.pumpWidget(
      _host(steps: [step(true)], disableAnimations: false),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(pulse(), findsOneWidget);
    final stopped = ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      arguments: {'action': 'read', 'url': 'https://ya.ru'},
      loading: true,
      metadata: {
        'computer': {'status': 'stopped'},
      },
    );
    await tester.pumpWidget(_host(steps: [stopped], disableAnimations: false));
    await tester.pumpAndSettle();
    expect(pulse(), findsNothing);
    final dot = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('computer-browser-status-dot')),
    );
    expect((dot.decoration as BoxDecoration).color, const Color(0xFF9CA3AF));
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets('a running browser step names the live page and action', (
    tester,
  ) async {
    final browser = BrowserAgentSession.instance;
    addTearDown(() {
      browser.setOwnerConversationId(null);
      browser.pageUrl.value = null;
      browser.currentActivity.value = null;
    });
    browser.setOwnerConversationId('chat');
    browser.pageStarted('https://dzen.ru/feed');
    browser.recordActivity(action: 'read');
    final step = ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      arguments: const {},
      loading: true,
    );
    await tester.pumpWidget(_host(steps: [step], conversationId: 'chat'));
    await tester.pump();
    expect(find.text('Browser · dzen.ru'), findsOneWidget);
    expect(find.text('Reading page'), findsOneWidget);
    expect(find.text('Browser action'), findsNothing);

    // Another chat's browser never names this chat's step.
    await tester.pumpWidget(_host(steps: [step], conversationId: 'other'));
    await tester.pump();
    expect(find.text('Browser · dzen.ru'), findsNothing);
  });

  testWidgets('active panel fits 60dp with a 64 by 40 thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(_host(steps: [_command()]));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height,
      lessThanOrEqualTo(60),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('computer-step-thumbnail:command')),
      ),
      const Size(64, 40),
    );
    // The composer's own Stop ends the reply; the panel has no second one.
    expect(find.byTooltip('Stop'), findsNothing);
    expect(find.byIcon(Lucide.Square), findsNothing);
  });

  for (final sample in [
    (
      name: 'browser',
      tool: 'browser_use',
      arguments: {'action': 'read', 'url': 'https://ya.ru'},
    ),
    (name: 'command', tool: 'shell', arguments: {'command': 'echo ready'}),
    (
      name: 'file',
      tool: 'read_file',
      arguments: {'path': '/workspace/notes.md'},
    ),
    (
      name: 'image',
      tool: 'generate_image',
      arguments: {'prompt': 'a small landscape'},
    ),
    (name: 'tool', tool: 'lookup_weather', arguments: {'city': 'Paris'}),
    (name: 'plan', tool: 'update_plan', arguments: {'plan': []}),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('${sample.name} uses one compact row at 320dp scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final step = ComputerStep(
          id: sample.name,
          toolName: sample.tool,
          arguments: sample.arguments,
          loading: true,
        );
        await tester.pumpWidget(
          _host(steps: [step], scale: scale, locale: const Locale('ru')),
        );
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byKey(ComputerStatusPanel.panelKey));
        final thumbnail = tester.getRect(
          find.byKey(ValueKey('computer-step-thumbnail:${sample.name}')),
        );
        expect(panel.top, greaterThanOrEqualTo(0));
        expect(panel.bottom, lessThanOrEqualTo(140));
        expect(thumbnail.size, const Size(64, 40));
        final preview = tester.widget<ComputerStepThumbnail>(
          find.byType(ComputerStepThumbnail),
        );
        expect(preview.borderRadius, 10);
        if (scale == 1) {
          expect(panel.height, inInclusiveRange(56, 60));
        }
        for (final key in [
          ComputerStatusPanel.previousKey,
          ComputerStatusPanel.nextKey,
        ]) {
          final target = tester.getRect(find.byKey(key));
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
          expect(target.left, greaterThanOrEqualTo(thumbnail.right));
          expect(target.top, greaterThanOrEqualTo(panel.top));
          expect(target.right, lessThanOrEqualTo(panel.right));
          expect(target.bottom, lessThanOrEqualTo(panel.bottom));
          expect(target.center.dy, closeTo(panel.center.dy, 0.1));
          final button = tester.widget<IconButton>(find.byKey(key));
          expect((button.icon as Icon).size, 16);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final action in ['done', 'read']) {
    testWidgets('browser $action inherits the last page in its response', (
      tester,
    ) async {
      final prior = ComputerStep(
        id: 'open',
        toolName: 'browser_use',
        arguments: {'action': 'open', 'url': 'https://wttr.in/Paris'},
        content: '{"ok":true,"url":"https://ya.ru/search"}',
      );
      final current = ComputerStep(
        id: 'current',
        toolName: 'browser_use',
        arguments: {'action': action},
        loading: action != 'done',
        content: action == 'done'
            ? '{"ok":true,"action":"done","summary":"finished"}'
            : null,
      );
      await tester.pumpWidget(_host(steps: [prior, current]));
      await tester.pumpAndSettle();
      expect(find.text('Browser · ya.ru'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('computer-browser-domain')),
        findsOneWidget,
      );
      expect(find.text('ya.ru'), findsOneWidget);
      expect(find.text('wttr.in'), findsNothing);
      final thumbnail = tester.widget<ComputerStepThumbnail>(
        find.byType(ComputerStepThumbnail),
      );
      expect(thumbnail.browserPageUrl, isNull);
      expect(
        find.descendant(
          of: find.byType(ComputerStepThumbnail),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('browser page inheritance never survives a response change', (
    tester,
  ) async {
    final prior = ComputerStep(
      id: 'open',
      toolName: 'browser_use',
      arguments: {'action': 'open', 'url': 'https://ya.ru'},
    );
    ComputerStep done(String id) => ComputerStep(
      id: id,
      toolName: 'browser_use',
      arguments: {'action': 'done'},
      content: '{"ok":true,"action":"done","summary":"finished"}',
    );
    await tester.pumpWidget(_host(steps: [prior, done('first-done')]));
    await tester.pumpAndSettle();
    expect(find.text('Browser · ya.ru'), findsOneWidget);
    await tester.pumpWidget(_host(steps: [done('next-done')]));
    await tester.pumpAndSettle();
    expect(find.text('Browser · ya.ru'), findsNothing);
    expect(find.text('ya.ru'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inherited browser domain honors the current launch filter', (
    tester,
  ) async {
    final prior = ComputerStep(
      id: 'open',
      toolName: 'browser_use',
      arguments: {'action': 'open', 'url': 'https://ya.ru'},
    );
    const filter = ToolDisplayRedaction(
      text: _redactYandexDomain,
      value: _keepDisplayValue,
    );
    final filtered = await filter.run(() async {
      return ComputerStep(
        id: 'done',
        toolName: 'browser_use',
        arguments: {'action': 'done'},
        content: '{"ok":true,"action":"done"}',
      );
    });
    await tester.pumpWidget(_host(steps: [prior, filtered]));
    await tester.pumpAndSettle();
    expect(find.text('Browser · ya.ru'), findsNothing);
    expect(find.text('ya.ru'), findsNothing);
    expect(find.textContaining('[REDACTED]'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active panel fits narrow landscape with scaled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(steps: [_command()], scale: 1.3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Russian active panel fits scaled 320dp landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(steps: [_command()], scale: 1.3, locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed response becomes a 48dp row', (tester) async {
    await tester.pumpWidget(
      _host(
        steps: [_command(loading: false, content: 'done')],
        generating: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height, 48);
    expect(find.byTooltip('Stop'), findsNothing);
    expect(find.text('Done · 1 action'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.byType(ComputerStepThumbnail), findsNothing);
  });

  testWidgets('completed browser response uses the common 48dp summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        steps: [
          ComputerStep(
            id: 'browser',
            toolName: 'browser_use',
            arguments: {'action': 'done'},
            content: '{"ok":true,"action":"done","summary":"finished"}',
          ),
        ],
        generating: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height, 48);
    expect(find.text('Done · 1 action'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.byType(ComputerStepThumbnail), findsNothing);
    expect(
      find.byKey(const ValueKey('computer-browser-preview')),
      findsNothing,
    );
    expect(find.byKey(ComputerStatusPanel.previousKey), findsNothing);
    expect(find.byKey(ComputerStatusPanel.nextKey), findsNothing);
  });

  testWidgets('background-only response collapses to a 48dp row', (
    tester,
  ) async {
    final registry = ToolRunRegistry();
    final run = registry.start(
      'job',
      'shell',
      command: 'serve',
      conversationId: 'chat',
    );
    await tester.pumpWidget(
      _host(
        steps: [
          ComputerStep(
            id: 'job',
            toolName: 'shell',
            arguments: {'background': true},
            run: run,
          ),
        ],
        generating: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop'), findsNothing);
    expect(find.byType(ComputerStepThumbnail), findsNothing);
    expect(tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height, 48);
    await tester.pumpWidget(const SizedBox());
    run.complete(status: ToolRunStatus.succeeded);
    run.dispose();
    registry.dispose();
  });

  testWidgets('response cancellation survives a selected completed step', (
    tester,
  ) async {
    final step = ComputerStep(
      id: 'command',
      toolName: 'shell',
      arguments: {'command': 'echo done'},
      content: 'done',
      metadata: {
        'computer': {'responseStopped': true},
      },
    );
    await tester.pumpWidget(_host(steps: [step], generating: false));
    await tester.pumpAndSettle();
    expect(find.text('Stopped · 1 action'), findsOneWidget);
    expect(find.textContaining('AI working'), findsNothing);
    expect(find.byTooltip('Stop'), findsNothing);
  });

  for (final stopped in [false, true]) {
    testWidgets(
      'Russian scaled terminal row fits at 320dp (stopped=$stopped)',
      (tester) async {
        final step = ComputerStep(
          id: 'command',
          toolName: 'shell',
          arguments: {'command': 'echo done'},
          content: 'done',
          metadata: {
            'computer': {'responseStopped': stopped},
          },
        );
        await tester.pumpWidget(
          _host(
            steps: [step],
            generating: false,
            scale: 1.3,
            locale: const Locale('ru'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height,
          48,
        );
        expect(
          find.text(
            stopped ? 'Остановлено · 1 действие' : 'Готово · 1 действие',
          ),
          findsOneWidget,
        );
        expect(find.text('Посмотреть'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'shell thumbnail shows the command while output is empty, never result JSON',
    (tester) async {
      final step = ComputerStep(
        id: 'command',
        toolName: 'shell',
        arguments: {'command': 'serve', 'background': true},
        content: '{"background":true,"job_id":"job","status":"running"}',
      );
      await tester.pumpWidget(_host(steps: [step]));
      await tester.pumpAndSettle();
      final thumbnail = find.byType(ComputerStepThumbnail);
      expect(
        find.descendant(
          of: thumbnail,
          matching: find.textContaining('background'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: thumbnail, matching: find.text(r'$ serve')),
        findsOneWidget,
      );
    },
  );

  testWidgets('shell thumbnail follows the final four real output lines', (
    tester,
  ) async {
    final registry = ToolRunRegistry();
    final run = registry.start('job', 'shell', command: 'serve');
    final step = ComputerStep(id: 'command', toolName: 'shell', run: run);
    await tester.pumpWidget(_host(steps: [step]));
    run.appendStdout(
      Uint8List.fromList(utf8.encode('old\none\ntwo\nthree\nfour')),
    );
    await tester.pump(ToolRun.notifyInterval);
    final thumbnail = find.byType(ComputerStepThumbnail);
    expect(
      find.descendant(
        of: thumbnail,
        matching: find.text('one\ntwo\nthree\nfour'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: thumbnail, matching: find.textContaining('old')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    run.complete(status: ToolRunStatus.succeeded);
    run.dispose();
    registry.dispose();
  });

  testWidgets(
    'blank browser preview shows a globe and keeps its domain outside',
    (tester) async {
      await tester.pumpWidget(
        _host(
          steps: [
            ComputerStep(
              id: 'browser',
              toolName: 'browser_use',
              arguments: {'url': 'https://example.com/page'},
              loading: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final thumbnail = find.byType(ComputerStepThumbnail);
      expect(
        find.descendant(of: thumbnail, matching: find.byIcon(Lucide.Globe)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: thumbnail, matching: find.text('example.com')),
        findsNothing,
      );
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('Browser · example.com'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('computer-step-thumbnail:browser')),
        ),
        const Size(64, 40),
      );
    },
  );

  testWidgets('plan thumbnail uses the checklist icon', (tester) async {
    await tester.pumpWidget(
      _host(
        steps: [
          ComputerStep(
            id: 'plan',
            toolName: 'update_plan',
            arguments: {'plan': []},
            loading: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ComputerStepThumbnail),
        matching: find.byIcon(Lucide.ListChecks),
      ),
      findsOneWidget,
    );
  });
}

String _redactYandexDomain(String value) =>
    value.replaceAll('ya.ru', '[REDACTED]');

Object? _keepDisplayValue(Object? value) => value;
