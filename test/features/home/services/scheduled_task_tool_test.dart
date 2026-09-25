import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/scheduled_task.dart';
import 'package:Kelivo/features/home/services/scheduled_task_tool.dart';

void main() {
  // Friday 2026-09-25 10:00 local time.
  final now = DateTime(2026, 9, 25, 10);
  late List<ScheduledTask> stored;
  late List<String> deleted;

  ScheduledTaskTool tool({
    String? conversationId = 'c1',
    Future<void> Function(ScheduledTask task)? save,
  }) => ScheduledTaskTool(
    tasks: () async => stored,
    save:
        save ??
        (task) async {
          stored = [
            for (final t in stored)
              if (t.id != task.id) t,
            task,
          ];
        },
    delete: (id) async {
      deleted.add(id);
      stored = stored.where((t) => t.id != id).toList();
    },
    assistantNames: const {'a1': 'Helper', 'a2': 'Writer'},
    callerAssistantId: 'a1',
    conversationId: conversationId,
    now: () => now,
  );

  Future<Map<String, dynamic>> run(
    Map<String, dynamic> args, {
    ScheduledTaskTool? using,
  }) async =>
      jsonDecode(await (using ?? tool()).execute(args)) as Map<String, dynamic>;

  setUp(() {
    stored = [];
    deleted = [];
  });

  test('only list runs without approval', () {
    expect(ScheduledTaskTool.requiresApproval({'action': 'list'}), isFalse);
    for (final action in ['create', 'update', 'delete', 'bogus']) {
      expect(ScheduledTaskTool.requiresApproval({'action': action}), isTrue);
    }
  });

  test(
    'create a daily task for a new chat with the calling assistant',
    () async {
      final result = await run({
        'action': 'create',
        'name': 'News',
        'prompt': 'Summarize the news',
        'time': '8:30',
        'repeat': 'daily',
      });

      expect(result['ok'], isTrue);
      expect(result['now'], startsWith('2026-09-25T10:00:00'));
      final task = stored.single;
      expect(task.name, 'News');
      expect(task.assistantId, 'a1');
      expect((task.hour, task.minute), (8, 30));
      expect(task.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(task.mode, ScheduledTaskMode.newChat);
      expect(task.conversationId, isNull);
      expect(task.enabled, isTrue);
      expect(result['created'], containsPair('repeat', 'daily'));
      expect(result['created'], containsPair('target', 'new_chat'));
      expect(result['created'], containsPair('assistant', 'Helper'));
    },
  );

  test('a one-off follow-up continues the calling chat', () async {
    final result = await run({
      'action': 'create',
      'name': 'Check in',
      'prompt': 'Ask how the exam went',
      'time': '18:00',
      'repeat': 'once',
      'date': '2026-09-26',
      'target': 'this_chat',
    });

    expect(result['ok'], isTrue);
    final task = stored.single;
    expect(task.mode, ScheduledTaskMode.followUp);
    expect(task.conversationId, 'c1');
    expect(task.onceDate, DateTime(2026, 9, 26));
    expect(result['created'], containsPair('target', 'this_chat'));
    expect(result['created'], containsPair('date', '2026-09-26'));
  });

  test('update changes only the given fields and keeps the rest', () async {
    stored = [
      const ScheduledTask(
        id: 't1',
        name: 'Gym',
        prompt: 'Remind me to train',
        assistantId: 'a1',
        hour: 7,
        minute: 0,
        weekdays: [1, 3, 5],
        notify: false,
        revision: 4,
      ),
    ];

    final result = await run({
      'action': 'update',
      'task_id': 't1',
      'time': '07:45',
      'weekdays': [2, 4],
    });

    expect(result['ok'], isTrue);
    final task = stored.single;
    expect((task.hour, task.minute), (7, 45));
    expect(task.weekdays, [2, 4]);
    expect(task.prompt, 'Remind me to train');
    expect(task.notify, isFalse);
    expect(task.revision, 4);
    expect(result['updated'], containsPair('repeat', 'custom'));
  });

  test('delete removes the task by id', () async {
    stored = [
      const ScheduledTask(
        id: 't1',
        name: 'Gym',
        prompt: 'Train',
        assistantId: 'a1',
        hour: 7,
        minute: 0,
      ),
    ];
    final result = await run({'action': 'delete', 'task_id': 't1'});
    expect(result['ok'], isTrue);
    expect(result['deleted'], {'id': 't1', 'name': 'Gym'});
    expect(deleted, ['t1']);
  });

  test('invalid requests are reported to the model without saving', () async {
    Future<String?> error(Map<String, dynamic> args) async {
      final result = await run(args);
      expect(result['ok'], isFalse);
      return result['error'] as String?;
    }

    const base = {
      'action': 'create',
      'name': 'X',
      'prompt': 'Y',
      'time': '09:00',
      'repeat': 'daily',
    };
    expect(await error({...base, 'time': '25:00'}), 'invalid_time');
    expect(await error({...base, 'repeat': 'hourly'}), 'invalid_repeat');
    expect(await error({...base, 'repeat': 'once'}), 'missing_field');
    expect(
      await error({...base, 'repeat': 'once', 'date': '2026-09-24'}),
      'schedule_ended',
    );
    expect(
      await error({...base, 'repeat': 'once', 'date': '2026-02-30'}),
      'invalid_date',
    );
    expect(
      await error({
        ...base,
        'repeat': 'custom',
        'weekdays': [0],
      }),
      'invalid_weekdays',
    );
    expect(await error({...base, 'assistant_id': 'nope'}), 'invalid_assistant');
    expect(await error({'action': 'update', 'task_id': 'nope'}), 'not_found');
    expect(await error({'action': 'rename'}), 'invalid_action');
    expect(stored, isEmpty);
  });

  test('this_chat needs a chat and a native refusal is passed on', () async {
    final noChat = tool(conversationId: null);
    final result = await run({
      'action': 'create',
      'name': 'X',
      'prompt': 'Y',
      'time': '09:00',
      'repeat': 'daily',
      'target': 'this_chat',
    }, using: noChat);
    expect(result['error'], 'invalid_target');

    final refusing = tool(
      save: (_) async =>
          throw PlatformException(code: 'error', message: 'schedule_ended'),
    );
    final refused = await run({
      'action': 'create',
      'name': 'X',
      'prompt': 'Y',
      'time': '09:00',
      'repeat': 'daily',
    }, using: refusing);
    expect(refused['error'], 'schedule_ended');
  });

  test('list shows each task with its next run', () async {
    stored = [
      ScheduledTask(
        id: 't1',
        name: 'News',
        prompt: 'Summarize',
        assistantId: 'a2',
        hour: 8,
        minute: 0,
        nextRunAt: DateTime(2026, 9, 26, 8),
        mode: ScheduledTaskMode.followUp,
        conversationId: 'other',
      ),
    ];
    final result = await run({'action': 'list'});
    final task = (result['tasks'] as List).single as Map;
    expect(task['id'], 't1');
    expect(task['time'], '08:00');
    expect(task['assistant'], 'Writer');
    expect(task['target'], 'other_chat');
    expect(task['next_run'], startsWith('2026-09-26T08:00:00'));
  });
}
