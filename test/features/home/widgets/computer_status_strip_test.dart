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
  VoidCallback? onStop,
  ComputerToolSource? source,
}) {
  final strip = ComposerStatusStrip(
    conversationId: conversationId,
    generating: generating,
    steps: steps,
    responseId: responseId,
    onStop: onStop,
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
    'Stop becomes available for a new background job in the same chat',
    (tester) async {
      final registry = ToolRunRegistry();
      final first = registry.start('first', 'shell', conversationId: 'chat');
      await tester.pumpWidget(
        _host(registry: registry, generating: false, responseId: null),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(ComputerStatusPanel.stopKey))
            .onPressed,
        isNull,
      );
      first.complete(status: ToolRunStatus.cancelled);
      final second = registry.start('second', 'shell', conversationId: 'chat');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(ComputerStatusPanel.stopKey))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
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
      );
      final browser = ComputerStep(
        id: 'current-browser',
        toolName: 'browser_use',
        arguments: {'action': 'observe'},
        loading: true,
      );
      await tester.pumpWidget(_host(registry: registry, steps: [browser]));
      await tester.pumpAndSettle();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      oldRun.complete(status: ToolRunStatus.succeeded);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      oldRun.dispose();
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
      );
      await tester.pumpWidget(
        _host(registry: registry, steps: [], generating: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Computer'));
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
    );
    await tester.pumpWidget(_host(registry: registry));
    await tester.pumpAndSettle();
    expect(find.text('Computer'), findsOneWidget);
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
      expect(find.text('Computer'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('computer-step-thumbnail:step')),
        findsOneWidget,
      );
      if (name == 'read_file') {
        expect(find.text('notes.md'), findsWidgets);
        expect(find.textContaining('Opening lines'), findsOneWidget);
      } else {
        expect(find.text('Browser'), findsOneWidget);
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
      expect(find.text('Computer'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      await tester.pump(ComposerStatusStrip.resultDuration);
      await tester.pumpAndSettle();
      expect(find.byType(ComputerStatusPanel), findsNothing);
      await tester.pumpWidget(
        _host(registry: registry, steps: [active], responseId: 'reply-2'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Computer'), findsOneWidget);
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
      expect(find.text('Computer'), findsNothing);
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
      expect(find.text('Computer'), findsOneWidget);
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
      expect(find.text('Computer'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
      updates.dispose();
    },
  );

  testWidgets(
    'narrow scaled strip has 48dp controls and Stop stops the response once',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final registry = ToolRunRegistry();
      var stopped = 0;
      final step = ComputerStep(
        id: 'a',
        toolName: 'shell',
        arguments: {'command': 'a very long command with arguments'},
        loading: true,
      );
      await tester.pumpWidget(
        _host(registry: registry, steps: [step], onStop: () => stopped++),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in [
        ComputerStatusPanel.previousKey,
        ComputerStatusPanel.nextKey,
        ComputerStatusPanel.stopKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
      await tester.pumpAndSettle();
      expect(stopped, 1);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    },
  );
}
