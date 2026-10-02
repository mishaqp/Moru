import 'dart:convert';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/computer_response_scope.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

Widget _host(ChatMessage message, {List<ToolUIPart>? live}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ToolRunRegistry()),
    ChangeNotifierProvider(create: (_) => ToolApprovalService()),
    ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
    ChangeNotifierProvider(
      create: (_) => SettingsProvider(createBusinessTestPreferences()),
    ),
    ChangeNotifierProvider(
      create: (_) =>
          AssistantProvider(preferences: createBusinessTestPreferences()),
    ),
    ChangeNotifierProvider(
      create: (_) => TtsProvider(preferences: createBusinessTestPreferences()),
    ),
    ChangeNotifierProvider(
      create: (_) => UserProvider(preferences: createBusinessTestPreferences()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ChatMessageWidget(
        message: message,
        toolParts: live,
        showModelIcon: false,
        showToolCards: true,
      ),
    ),
  ),
);

void main() {
  testWidgets('an open response retains completed run output after eviction', (
    tester,
  ) async {
    final registry = ToolRunRegistry();
    final updates = ValueNotifier<int>(0);
    addTearDown(registry.dispose);
    addTearDown(updates.dispose);
    final run = registry.start(
      'call',
      'shell',
      conversationId: 'chat',
      responseId: 'reply',
    );
    run.appendStdout(utf8.encode('retained output'));
    run.complete(status: ToolRunStatus.succeeded);
    List<Map<String, dynamic>> events() => [
      {
        'id': 'call',
        'name': 'shell',
        'arguments': {'command': 'echo'},
        'content': 'saved fallback',
      },
    ];
    final message = ChatMessage(
      id: 'reply',
      role: 'assistant',
      conversationId: 'chat',
      content: '',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: registry,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ComputerToolSource(
            readMessages: () => [message],
            readSteps: (_) => computerStepsFromEvents(events()),
            updates: updates,
            child: ComputerResponseScope(
              responseId: 'reply',
              conversationId: 'chat',
              steps: computerStepsFromEvents(events()),
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ComputerResponseScope.showForStep(
                    context,
                    computerStepsFromEvents(events()).single,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('retained output'), findsOneWidget);
    registry.evict('call', conversationId: 'chat');
    updates.value++;
    await tester.pump();
    expect(find.text('retained output'), findsOneWidget);
    expect(find.text('saved fallback'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('a reused foreground call only attaches its response-owned run', () {
    final registry = ToolRunRegistry();
    addTearDown(registry.dispose);
    final old = registry.start(
      'same-call',
      'shell',
      conversationId: 'chat',
      responseId: 'old',
    );
    old.complete(status: ToolRunStatus.succeeded);
    final newer = registry.start(
      'same-call',
      'shell',
      conversationId: 'chat',
      responseId: 'new',
    );
    final saved = computerStepsFromEvents([
      {'id': 'same-call', 'name': 'shell', 'content': 'old output'},
    ]);
    expect(
      withComputerRuns(saved, registry, 'chat', responseId: 'old').single.run,
      isNull,
    );
    expect(
      withComputerRuns(saved, registry, 'chat', responseId: 'new').single.run,
      same(newer),
    );
    final retained = [saved.single.withRun(old)];
    expect(
      withComputerRuns(
        retained,
        registry,
        'chat',
        responseId: 'old',
      ).single.run,
      same(old),
    );
    newer.complete(status: ToolRunStatus.cancelled);
  });
  test('an expired explicit job never binds an unrelated reused call ID', () {
    final registry = ToolRunRegistry();
    final newer = registry.start(
      'same-call',
      'shell',
      conversationId: 'chat',
      runtimeRunId: 'job-second',
    );
    final steps = computerStepsFromEvents([
      {
        'id': 'same-call',
        'name': 'shell',
        'content': jsonEncode({'job_id': 'job-first'}),
      },
    ]);
    expect(withComputerRuns(steps, registry, 'chat').single.run, isNull);
    newer.dispose();
    registry.dispose();
  });

  test(
    'a saved background job resolves its runtime ID before reused call ID',
    () {
      final registry = ToolRunRegistry();
      final first = registry.start(
        'same-call',
        'shell',
        conversationId: 'chat',
        runtimeRunId: 'job-first',
      );
      final second = registry.start(
        'same-call',
        'shell',
        conversationId: 'chat',
        runtimeRunId: 'job-second',
      );
      final steps = computerStepsFromEvents([
        {
          'id': 'same-call',
          'name': 'shell',
          'content': jsonEncode({'job_id': 'job-first'}),
        },
      ]);
      expect(withComputerRuns(steps, registry, 'chat').single.run, same(first));
      first.dispose();
      second.dispose();
      registry.dispose();
    },
  );

  test('missing, empty and whitespace tool IDs get distinct stable IDs', () {
    final events = [
      {'name': 'shell', 'content': 'first'},
      {'id': '', 'name': 'shell', 'content': 'second'},
      {'id': '  ', 'name': 'shell', 'content': 'third'},
      {'id': 'real-call', 'name': 'shell', 'content': 'fourth'},
    ];
    expect(computerStepsFromEvents(events).map((step) => step.id), [
      'shell-0',
      'shell-1',
      'shell-2',
      'real-call',
    ]);
  });

  for (final restored in [true, false]) {
    testWidgets(
      '${restored ? 'restored' : 'live'} empty-ID siblings open and page without duplicates',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = [
          {
            'name': 'builtin_search',
            'arguments': <String, dynamic>{},
            'content': '{}',
          },
          {
            'id': 'real-file-call',
            'name': 'read_file',
            'arguments': {'path': '/workspace/example.txt'},
            'content': 'existing file',
          },
          {
            'name': 'shell',
            'arguments': {'command': 'echo first'},
            'content': 'first result',
          },
          {
            'id': '',
            'name': 'shell',
            'arguments': {'command': 'echo second'},
            'content': 'second result',
          },
        ];
        final message = ChatMessage(
          id: 'reply',
          conversationId: 'chat',
          role: 'assistant',
          content: '',
          parts: restored
              ? [for (final event in events) ToolCallPart(jsonEncode(event))]
              : const [],
        );
        await tester.pumpWidget(
          _host(
            message,
            live: restored
                ? null
                : [
                    for (final event in events)
                      ToolUIPart(
                        id: event['id'] as String? ?? '',
                        toolName: event['name'] as String,
                        arguments: event['arguments'] as Map<String, dynamic>,
                        content: event['content'] as String,
                      ),
                  ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Run command').last);
        await tester.pumpAndSettle();
        expect(find.text('4 / 4'), findsOneWidget);
        expect(find.text('second result'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('computer-previous-step')));
        await tester.pumpAndSettle();
        expect(find.text('3 / 4'), findsOneWidget);
        expect(find.text('first result'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Run command').first);
        await tester.pumpAndSettle();
        expect(find.text('3 / 4'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('computer-next-step')));
        await tester.pumpAndSettle();
        expect(find.text('4 / 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
