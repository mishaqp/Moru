import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_response_scope.dart';
import 'package:Kelivo/features/chat/widgets/computer_sheet.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/computer_status_panel.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Widget _host({
  required ToolRunRegistry registry,
  List<ComputerStep>? steps,
  bool generating = true,
  String? conversationId = 'chat',
  String? responseId = 'reply',
  ComputerToolSource? source,
}) {
  final strip = ComposerStatusStrip(
    conversationId: conversationId,
    generating: generating,
    steps: steps,
    responseId: responseId,
  );
  return ChangeNotifierProvider.value(
    value: registry,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: source == null
              ? strip
              : ComputerToolSource(
                  readMessages: source.readMessages,
                  readSteps: source.readSteps,
                  updates: source.updates,
                  child: strip,
                ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'source cancellation clears response activity before the composer props refresh',
    (tester) async {
      final registry = ToolRunRegistry();
      final updates = ChangeNotifier();
      var messages = [
        ChatMessage(
          id: 'reply',
          role: 'assistant',
          content: '',
          conversationId: 'chat',
          isStreaming: true,
        ),
      ];
      var steps = [
        ComputerStep(
          id: 'plan',
          toolName: 'update_plan',
          arguments: {'plan': []},
          loading: true,
        ),
      ];
      final source = ComputerToolSource(
        readMessages: () => messages,
        readSteps: (_) => steps,
        updates: updates,
        child: const SizedBox(),
      );
      void cancel() {
        messages = [
          ChatMessage(
            id: 'reply',
            role: 'assistant',
            content: '',
            conversationId: 'chat',
          ),
        ];
        steps = [
          ComputerStep(
            id: 'plan',
            toolName: 'update_plan',
            arguments: {'plan': []},
            metadata: {
              'computer': {'status': 'stopped', 'responseStopped': true},
            },
          ),
        ];
        updates.notifyListeners();
      }

      await tester.pumpWidget(_host(registry: registry, source: source));
      await tester.pumpAndSettle();
      // The composer's Stop cancels the reply; the strip follows the source.
      cancel();
      await tester.pumpAndSettle();
      expect(find.text('Stopped · 1 action'), findsOneWidget);
      expect(
        tester
            .widget<ComputerStatusPanel>(find.byType(ComputerStatusPanel))
            .generating,
        isFalse,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      updates.dispose();
    },
  );

  testWidgets(
    'generation Stop preserves the background job and its output controls',
    (tester) async {
      final registry = ToolRunRegistry();
      final job = registry.start(
        'background',
        'shell',
        command: 'serve project',
        conversationId: 'chat',
        responseId: 'previous',
        background: true,
      );
      final pending = ComputerStep(
        id: 'plan',
        toolName: 'update_plan',
        arguments: {'plan': []},
        loading: true,
      );
      await tester.pumpWidget(_host(registry: registry, steps: [pending]));
      await tester.pumpAndSettle();
      expect(job.status, ToolRunStatus.running);
      final cancelled = ComputerStep(
        id: 'plan',
        toolName: 'update_plan',
        arguments: {'plan': []},
        metadata: {
          'computer': {'status': 'stopped', 'responseStopped': true},
        },
      );
      final output = ComputerStep(
        id: 'output',
        toolName: 'shell_output',
        arguments: {'job_id': job.runtimeRunId},
        content: jsonEncode({'job_id': job.runtimeRunId, 'status': 'running'}),
        metadata: {
          'computer': {'responseStopped': true},
        },
      );
      await tester.pumpWidget(
        _host(
          registry: registry,
          steps: [cancelled, output],
          generating: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(job.status, ToolRunStatus.running);
      expect(
        tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height,
        48,
      );
      expect(find.textContaining('Stopped ·'), findsOneWidget);
      await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
      await tester.pumpAndSettle();
      job.appendStdout(
        Uint8List.fromList(utf8.encode('background still live')),
      );
      await tester.pump(ToolRun.notifyInterval);
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('background still live'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.byTooltip('Open terminal'),
        ),
        findsOneWidget,
      );
      expect(find.text('AI is working…'), findsNothing);
      Navigator.of(tester.element(find.byType(ComputerSheet))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _host(registry: registry, steps: [pending], responseId: 'next'),
      );
      await tester.pumpAndSettle();
      // The next reply is live again, not left in the stopped state.
      expect(find.textContaining('Stopped ·'), findsNothing);
      expect(find.byKey(ComputerStatusPanel.previousKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      job.complete(status: ToolRunStatus.succeeded);
      job.dispose();
      registry.dispose();
    },
  );

  testWidgets(
    'an older background job does not steal the current working step',
    (tester) async {
      final registry = ToolRunRegistry();
      final oldRun = registry.start(
        'old',
        'shell',
        command: 'old server',
        conversationId: 'chat',
        background: true,
        responseId: 'previous',
      );
      final browser = ComputerStep(
        id: 'current-browser',
        toolName: 'browser_use',
        arguments: {'action': 'observe'},
        loading: true,
      );
      await tester.pumpWidget(_host(registry: registry, steps: [browser]));
      await tester.pumpAndSettle();
      expect(find.textContaining('Browser'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      oldRun.complete(status: ToolRunStatus.succeeded);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      oldRun.dispose();
      registry.dispose();
    },
  );

  testWidgets(
    'open sheet retains supplied steps when a source-only response changes in the same chat',
    (tester) async {
      final registry = ToolRunRegistry();
      final updates = ChangeNotifier();
      var messages = [
        ChatMessage(
          id: 'first-reply',
          role: 'assistant',
          content: '',
          conversationId: 'chat',
          isStreaming: true,
        ),
      ];
      final source = ComputerToolSource(
        readMessages: () => messages,
        readSteps: (_) => [],
        updates: updates,
        child: const SizedBox(),
      );
      final first = ComputerStep(
        id: 'first',
        toolName: 'read_file',
        arguments: {'path': 'first.md'},
        content: 'first response content',
      );
      await tester.pumpWidget(
        _host(
          registry: registry,
          steps: [first],
          source: source,
          responseId: null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
      await tester.pumpAndSettle();
      messages = [
        ChatMessage(
          id: 'second-reply',
          role: 'assistant',
          content: '',
          conversationId: 'chat',
          isStreaming: true,
        ),
      ];
      final second = ComputerStep(
        id: 'second',
        toolName: 'read_file',
        arguments: {'path': 'second.md'},
        content: 'second response private content',
      );
      await tester.pumpWidget(
        _host(
          registry: registry,
          steps: [second],
          source: source,
          responseId: null,
        ),
      );
      updates.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('first response content'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('second response private content'),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      updates.dispose();
    },
  );

  testWidgets(
    'open sheet retains original live steps after its response leaves the source',
    (tester) async {
      final registry = ToolRunRegistry();
      final updates = ChangeNotifier();
      var response = 'first-reply';
      var steps = [
        ComputerStep(
          id: 'first',
          toolName: 'read_file',
          arguments: {'path': 'first.md'},
          content: 'first live content',
        ),
      ];
      List<ChatMessage> messages() => [
        ChatMessage(
          id: response,
          role: 'assistant',
          content: '',
          conversationId: 'chat',
          isStreaming: true,
        ),
      ];
      final source = ComputerToolSource(
        readMessages: messages,
        readSteps: (id) => id == response ? steps : [],
        updates: updates,
        child: const SizedBox(),
      );
      await tester.pumpWidget(
        _host(registry: registry, source: source, responseId: null),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
      await tester.pumpAndSettle();
      response = 'second-reply';
      steps = [
        ComputerStep(
          id: 'second',
          toolName: 'read_file',
          arguments: {'path': 'second.md'},
          content: 'second private content',
        ),
      ];
      updates.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('first live content'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('second private content'),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      updates.dispose();
    },
  );

  testWidgets(
    'open sheet retains completed foreground output after registry eviction',
    (tester) async {
      final registry = ToolRunRegistry();
      final updates = ChangeNotifier();
      final run = registry.start(
        'command',
        'shell',
        command: 'echo ready',
        conversationId: 'chat',
        responseId: 'reply',
      );
      run.appendStdout(
        Uint8List.fromList(utf8.encode('retained foreground output')),
      );
      var complete = false;
      final source = ComputerToolSource(
        readMessages: () => [
          ChatMessage(
            id: 'reply',
            role: 'assistant',
            content: '',
            conversationId: 'chat',
            isStreaming: true,
          ),
        ],
        readSteps: (_) => [
          ComputerStep(
            id: 'command',
            toolName: 'shell',
            arguments: {'command': 'echo ready'},
            loading: !complete,
            content: complete ? 'saved summary' : null,
          ),
        ],
        updates: updates,
        child: const SizedBox(),
      );
      await tester.pumpWidget(_host(registry: registry, source: source));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
      await tester.pumpAndSettle();
      complete = true;
      run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
      updates.notifyListeners();
      await tester.pumpAndSettle();
      registry.evict('command', conversationId: 'chat');
      updates.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('retained foreground output'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      updates.dispose();
    },
  );

  testWidgets(
    'open sheet never adopts a successor foreground run in the same chat',
    (tester) async {
      final registry = ToolRunRegistry();
      final first = ComputerStep(
        id: 'first',
        toolName: 'read_file',
        arguments: {'path': 'first.md'},
        content: 'original response result',
      );
      await tester.pumpWidget(_host(registry: registry, steps: [first]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
      await tester.pumpAndSettle();
      final next = registry.start(
        'next',
        'shell',
        command: 'successor private command',
        conversationId: 'chat',
        responseId: 'reply-2',
      );
      final second = ComputerStep(
        id: 'next',
        toolName: 'shell',
        arguments: {'command': 'successor private command'},
        loading: true,
      );
      await tester.pumpWidget(
        _host(registry: registry, steps: [second], responseId: 'reply-2'),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('successor private command'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('original response result'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      next.complete(status: ToolRunStatus.succeeded);
      next.dispose();
      registry.dispose();
    },
  );

  testWidgets(
    'open sheet stays with its original chat and retains finished background output',
    (tester) async {
      final registry = ToolRunRegistry();
      final original = registry.start(
        'old',
        'shell',
        command: 'original server',
        conversationId: 'chat',
        background: true,
        responseId: 'reply',
      );
      await tester.pumpWidget(
        _host(registry: registry, steps: [], generating: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
      await tester.pumpAndSettle();
      expect(find.byType(ComputerSheet), findsOneWidget);
      await tester.pumpWidget(
        _host(
          registry: registry,
          steps: [],
          generating: false,
          conversationId: 'other-chat',
          responseId: 'other-reply',
        ),
      );
      final other = registry.start(
        'other',
        'shell',
        command: 'other private command',
        conversationId: 'other-chat',
        background: true,
        responseId: 'other-reply',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('other private command'),
        ),
        findsNothing,
      );
      original.appendStdout(
        Uint8List.fromList(utf8.encode('original final output')),
      );
      original.complete(status: ToolRunStatus.succeeded);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.textContaining('original final output'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ComputerSheet),
          matching: find.byTooltip('Open terminal'),
        ),
        findsOneWidget,
      );
      other.complete(status: ToolRunStatus.succeeded);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      original.dispose();
      other.dispose();
      registry.dispose();
    },
  );

  testWidgets('every running command uses the Computer strip', (tester) async {
    final registry = ToolRunRegistry();
    final run = registry.start(
      'command',
      'shell',
      command: 'echo ready',
      conversationId: 'chat',
      responseId: 'reply',
    );
    await tester.pumpWidget(_host(registry: registry));
    await tester.pumpAndSettle();
    expect(find.byKey(ComputerStatusPanel.panelKey), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('echo ready'), findsOneWidget);
    run.appendStdout(Uint8List.fromList(utf8.encode('first\nlatest line')));
    await tester.pump(ToolRun.notifyInterval);
    expect(find.textContaining('latest line'), findsOneWidget);
    run.complete(status: ToolRunStatus.succeeded);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    run.dispose();
    registry.dispose();
  });

  for (final name in ['browser_use', 'read_file']) {
    testWidgets('Computer strip supports $name without a shell run', (
      tester,
    ) async {
      final registry = ToolRunRegistry();
      final step = ComputerStep(
        id: 'step',
        toolName: name,
        arguments: name == 'browser_use'
            ? {'action': 'observe', 'url': 'https://example.com'}
            : {'path': '/workspace/notes.md'},
        content: name == 'read_file' ? 'Opening lines\nMore notes' : null,
        loading: true,
      );
      await tester.pumpWidget(_host(registry: registry, steps: [step]));
      await tester.pumpAndSettle();
      expect(find.byKey(ComputerStatusPanel.panelKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('computer-step-thumbnail:step')),
        findsOneWidget,
      );
      if (name == 'read_file') {
        expect(find.text('notes.md'), findsWidgets);
        expect(find.textContaining('Opening lines'), findsOneWidget);
      } else {
        expect(find.textContaining('Browser'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    });
  }

  testWidgets(
    'follows newest running step and respects manually viewed running step',
    (tester) async {
      final registry = ToolRunRegistry();
      var steps = [
        ComputerStep(
          id: 'a',
          toolName: 'read_file',
          arguments: {'path': 'first.md'},
          loading: true,
        ),
        ComputerStep(
          id: 'b',
          toolName: 'read_file',
          arguments: {'path': 'second.md'},
          loading: true,
        ),
      ];
      await tester.pumpWidget(_host(registry: registry, steps: steps));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(ComputerStatusPanel.previousKey));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      steps = [
        ...steps,
        ComputerStep(
          id: 'c',
          toolName: 'read_file',
          arguments: {'path': 'third.md'},
          loading: true,
        ),
      ];
      await tester.pumpWidget(_host(registry: registry, steps: steps));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      steps = [
        ComputerStep(
          id: 'a',
          toolName: 'read_file',
          arguments: {'path': 'first.md'},
          content: 'done',
        ),
        ...steps.skip(1),
      ];
      await tester.pumpWidget(_host(registry: registry, steps: steps));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    },
  );

  testWidgets(
    'shows final result then collapses and next reply shows its steps',
    (tester) async {
      final registry = ToolRunRegistry();
      final active = ComputerStep(
        id: 'a',
        toolName: 'read_file',
        arguments: {'path': 'notes.md'},
        loading: true,
      );
      final done = ComputerStep(
        id: 'a',
        toolName: 'read_file',
        arguments: {'path': 'notes.md'},
        content: 'saved',
      );
      await tester.pumpWidget(_host(registry: registry, steps: [active]));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _host(registry: registry, steps: [done], generating: false),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ComputerStatusPanel.panelKey), findsOneWidget);
      expect(find.text('Done · 1 action'), findsOneWidget);
      await tester.pump(ComposerStatusStrip.resultDuration);
      await tester.pumpAndSettle();
      expect(find.byType(ComputerStatusPanel), findsNothing);
      await tester.pumpWidget(
        _host(registry: registry, steps: [active], responseId: 'reply-2'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ComputerStatusPanel.panelKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    },
  );

  testWidgets(
    'listens to tool events in regular chats and clears previous response on user message',
    (tester) async {
      final registry = ToolRunRegistry();
      final updates = ChangeNotifier();
      var messages = [
        ChatMessage(
          id: 'user',
          role: 'user',
          content: 'work',
          conversationId: 'chat',
        ),
        ChatMessage(
          id: 'answer',
          role: 'assistant',
          content: '',
          conversationId: 'chat',
          isStreaming: true,
        ),
      ];
      var steps = <ComputerStep>[];
      final source = ComputerToolSource(
        readMessages: () => messages,
        readSteps: (id) => id == 'answer' ? steps : [],
        updates: updates,
        child: const SizedBox(),
      );
      await tester.pumpWidget(
        _host(registry: registry, source: source, responseId: null),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ComputerStatusPanel.panelKey), findsNothing);
      steps = [
        ComputerStep(
          id: 'browser',
          toolName: 'browser_use',
          arguments: {'action': 'observe'},
          loading: true,
        ),
      ];
      updates.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(ComputerStatusPanel.panelKey), findsOneWidget);
      messages = [
        ...messages,
        ChatMessage(
          id: 'next-user',
          role: 'user',
          content: 'next',
          conversationId: 'chat',
        ),
      ];
      updates.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(ComputerStatusPanel.panelKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      updates.dispose();
    },
  );

  testWidgets('narrow scaled strip has compact 48dp pager controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final registry = ToolRunRegistry();
    final step = ComputerStep(
      id: 'a',
      toolName: 'shell',
      arguments: {'command': 'a very long command with arguments'},
      loading: true,
    );
    await tester.pumpWidget(_host(registry: registry, steps: [step]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final key in [
      ComputerStatusPanel.previousKey,
      ComputerStatusPanel.nextKey,
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(find.byTooltip('Stop'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    registry.dispose();
  });
}
