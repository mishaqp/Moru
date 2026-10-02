import 'dart:convert';
import 'dart:typed_data';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_step_thumbnail.dart';
import 'package:Kelivo/features/home/widgets/computer_status_panel.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required List<ComputerStep> steps,
  bool generating = true,
  double scale = 1,
  double width = 320,
  Locale locale = const Locale('en'),
  String? conversationId,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  locale: locale,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 240),
        textScaler: TextScaler.linear(scale),
        viewInsets: const EdgeInsets.only(bottom: 100),
      ),
      child: Align(
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
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Browser action'), findsNothing);

    // Another chat's browser never names this chat's step.
    await tester.pumpWidget(_host(steps: [step], conversationId: 'other'));
    await tester.pump();
    expect(find.text('Browser · dzen.ru'), findsNothing);
  });

  testWidgets('active panel fits 88dp with a 76 by 56 thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(_host(steps: [_command()]));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height,
      lessThanOrEqualTo(88),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('computer-step-thumbnail:command')),
      ),
      const Size(76, 56),
    );
    // The composer's own Stop ends the reply; the panel has no second one.
    expect(find.byTooltip('Stop'), findsNothing);
    expect(find.byIcon(Lucide.Square), findsNothing);
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

  testWidgets('browser placeholder includes its domain', (tester) async {
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
      findsOneWidget,
    );
  });

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
