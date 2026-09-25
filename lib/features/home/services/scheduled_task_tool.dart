import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/scheduled_task.dart';
import '../../../core/services/scheduled_task_schedule.dart';

class _ToolFailure implements Exception {
  const _ToolFailure(this.error, this.message);

  final String error;
  final String message;
}

/// The `manage_scheduled_tasks` local tool: lets the model list, create,
/// change and delete the scheduled tasks shown in Settings > Scheduled tasks.
///
/// Storage stays with [ScheduledTasksService]; this class only reads the
/// current list through [tasks] and writes through [save] and [delete].
class ScheduledTaskTool {
  ScheduledTaskTool({
    required this.tasks,
    required this.save,
    required this.delete,
    required this.assistantNames,
    required this.callerAssistantId,
    this.conversationId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const String toolName = 'manage_scheduled_tasks';

  static const String actionList = 'list';
  static const String actionCreate = 'create';
  static const String actionUpdate = 'update';
  static const String actionDelete = 'delete';

  static const List<String> actions = [
    actionList,
    actionCreate,
    actionUpdate,
    actionDelete,
  ];

  static const List<String> repeats = ['once', 'daily', 'weekdays', 'custom'];

  final Future<List<ScheduledTask>> Function() tasks;
  final Future<void> Function(ScheduledTask task) save;
  final Future<void> Function(String id) delete;

  /// Assistant id to display name, read from the live provider.
  final Map<String, String> assistantNames;

  /// The assistant running the chat; new tasks use it by default.
  final String callerAssistantId;

  /// The chat that called the tool, the target of `target: "this_chat"`.
  final String? conversationId;
  final DateTime Function() _now;

  static String actionOf(Map<String, dynamic> args) =>
      (args['action'] ?? '').toString().trim().toLowerCase();

  /// Creating, changing and deleting tasks need the user's OK.
  static bool requiresApproval(Map<String, dynamic> args) =>
      actionOf(args) != actionList;

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'List, create, change and delete scheduled tasks. A scheduled task '
          'sends its prompt to an assistant at a set time, either in a new chat '
          'or as a follow-up in this chat, and can notify the user with the '
          'reply. Times use the device\'s local time zone; each result '
          'includes the current local time. Call "list" before changing or '
          'deleting a task to get its id. "create", "update" and "delete" ask '
          'the user for confirmation.',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions,
            'description':
                'list: all tasks with their next run. create: new task (name, '
                'prompt, time and repeat required). update: change task_id, '
                'only the fields you pass. delete: remove task_id.',
          },
          'task_id': {
            'type': 'string',
            'description': 'Target task for update and delete, from "list".',
          },
          'name': {'type': 'string', 'description': 'Short task name.'},
          'prompt': {
            'type': 'string',
            'description':
                'The message sent to the assistant when the task runs, written '
                'as the user\'s instruction (e.g. "Summarize today\'s news").',
          },
          'time': {
            'type': 'string',
            'description': 'Local time of day, 24-hour "HH:mm".',
          },
          'repeat': {
            'type': 'string',
            'enum': repeats,
            'description':
                'once: on "date". daily: every day. weekdays: Monday to '
                'Friday. custom: on "weekdays".',
          },
          'date': {
            'type': 'string',
            'description': 'For repeat "once": the day, "yyyy-MM-dd".',
          },
          'weekdays': {
            'type': 'array',
            'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
            'description': 'For repeat "custom": 1 = Monday … 7 = Sunday.',
          },
          'start_date': {
            'type': 'string',
            'description':
                'Optional first day for repeating tasks, "yyyy-MM-dd".',
          },
          'end_date': {
            'type': 'string',
            'description':
                'Optional last day for repeating tasks, "yyyy-MM-dd".',
          },
          'target': {
            'type': 'string',
            'enum': ['new_chat', 'this_chat'],
            'description':
                'new_chat (default): each run starts a new conversation. '
                'this_chat: each run continues the current conversation.',
          },
          'assistant_id': {
            'type': 'string',
            'description':
                'Assistant that runs the task. Defaults to the current one.',
          },
          'enabled': {
            'type': 'boolean',
            'description': 'Turn the task on or off. Default true.',
          },
          'notify': {
            'type': 'boolean',
            'description':
                'Show a notification with the reply when the task runs. '
                'Default true.',
          },
        },
        'required': ['action'],
      },
    },
  };

  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final action = actionOf(args);
      final Map<String, dynamic> result;
      switch (action) {
        case actionList:
          result = {'tasks': (await tasks()).map(_summary).toList()};
        case actionCreate:
          result = await _create(args);
        case actionUpdate:
          result = await _update(args);
        case actionDelete:
          result = await _delete(args);
        default:
          throw _ToolFailure(
            'invalid_action',
            'Unknown action "$action". Use one of: ${actions.join(', ')}.',
          );
      }
      return jsonEncode({'ok': true, 'now': _iso(_now()), ...result});
    } on _ToolFailure catch (e) {
      return jsonEncode({'ok': false, 'error': e.error, 'message': e.message});
    }
  }

  Map<String, dynamic> _summary(ScheduledTask task) {
    final last = task.runs.isEmpty ? null : task.runs.last;
    return {
      'id': task.id,
      'name': task.name,
      'prompt': task.prompt,
      'time': task.timeLabel,
      'repeat': task.repeat.name,
      if (task.onceDate != null) 'date': ScheduledTask.dateKey(task.onceDate),
      if (task.repeat == ScheduledTaskRepeat.custom) 'weekdays': task.weekdays,
      if (task.startDate != null)
        'start_date': ScheduledTask.dateKey(task.startDate),
      if (task.endDate != null) 'end_date': ScheduledTask.dateKey(task.endDate),
      'target': switch (task.mode) {
        ScheduledTaskMode.newChat => 'new_chat',
        ScheduledTaskMode.followUp =>
          task.conversationId == conversationId ? 'this_chat' : 'other_chat',
        ScheduledTaskMode.regenerate => 'regenerate_message',
      },
      'assistant': assistantNames[task.assistantId] ?? task.assistantId,
      'enabled': task.enabled,
      'notify': task.notify,
      'next_run': task.enabled ? _iso(task.nextRunAt) : null,
      if (last != null) 'last_run': {'status': last.status},
    };
  }

  Future<Map<String, dynamic>> _create(Map<String, dynamic> args) async {
    final name = _string(args, 'name');
    final prompt = _string(args, 'prompt');
    if (name == null || prompt == null) {
      throw const _ToolFailure(
        'missing_field',
        '"name" and "prompt" are required.',
      );
    }
    if (_string(args, 'time') == null || _string(args, 'repeat') == null) {
      throw const _ToolFailure(
        'missing_field',
        '"time" and "repeat" are required.',
      );
    }
    final task = _apply(
      args,
      ScheduledTask(
        id: const Uuid().v4(),
        name: name,
        prompt: prompt,
        assistantId: callerAssistantId,
        hour: 0,
        minute: 0,
      ),
    );
    await _save(task);
    return {'created': _summary(await _find(task.id))};
  }

  Future<Map<String, dynamic>> _update(Map<String, dynamic> args) async {
    final current = await _find(_string(args, 'task_id'));
    final task = _apply(args, current);
    await _save(task);
    return {'updated': _summary(await _find(task.id))};
  }

  Future<Map<String, dynamic>> _delete(Map<String, dynamic> args) async {
    final task = await _find(_string(args, 'task_id'));
    await delete(task.id);
    return {
      'deleted': {'id': task.id, 'name': task.name},
    };
  }

  Future<ScheduledTask> _find(String? id) async {
    if (id == null) {
      throw const _ToolFailure('missing_field', '"task_id" is required.');
    }
    for (final task in await tasks()) {
      if (task.id == id) return task;
    }
    throw _ToolFailure(
      'not_found',
      'No scheduled task with id "$id". Call "list" to get the ids.',
    );
  }

  Future<void> _save(ScheduledTask task) async {
    try {
      validateScheduledTask(task);
      if (task.enabled && nextScheduledTaskRun(task, _now()) == null) {
        throw const _ToolFailure(
          'schedule_ended',
          'This schedule has no future run. Pick a later date or time.',
        );
      }
    } on ArgumentError catch (e) {
      throw _ToolFailure('invalid_task', '${e.message}');
    }
    try {
      await save(task);
    } on PlatformException catch (e) {
      throw _ToolFailure(e.message ?? e.code, 'The task was not saved.');
    } on StateError catch (e) {
      throw _ToolFailure(e.message, 'The task was not saved.');
    }
  }

  /// [base] with the schedule fields from [args] applied.
  ScheduledTask _apply(Map<String, dynamic> args, ScheduledTask base) {
    var hour = base.hour, minute = base.minute;
    final time = _string(args, 'time');
    if (time != null) {
      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
      hour = int.tryParse(match?.group(1) ?? '') ?? -1;
      minute = int.tryParse(match?.group(2) ?? '') ?? -1;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        throw _ToolFailure(
          'invalid_time',
          'Use "HH:mm" for time, not "$time".',
        );
      }
    }

    var weekdays = base.weekdays;
    var onceDate = base.onceDate;
    var startDate = base.startDate, endDate = base.endDate;
    final repeat = _string(args, 'repeat');
    if (repeat != null && !repeats.contains(repeat)) {
      throw _ToolFailure(
        'invalid_repeat',
        'Use one of: ${repeats.join(', ')}.',
      );
    }
    if (repeat == 'once' || repeat == null && base.onceDate != null) {
      onceDate = _date(args, 'date') ?? base.onceDate;
      if (onceDate == null) {
        throw const _ToolFailure(
          'missing_field',
          '"date" is required for repeat "once".',
        );
      }
      weekdays = const [1, 2, 3, 4, 5, 6, 7];
      startDate = null;
      endDate = null;
    } else {
      onceDate = null;
      switch (repeat) {
        case 'daily':
          weekdays = const [1, 2, 3, 4, 5, 6, 7];
        case 'weekdays':
          weekdays = const [1, 2, 3, 4, 5];
      }
      if (repeat == 'custom' || args.containsKey('weekdays')) {
        final raw = args['weekdays'];
        final days = raw is List
            ? {
                for (final day in raw)
                  if (day is num) day.toInt() else int.tryParse('$day') ?? 0,
              }
            : const <int>{};
        if (days.isEmpty || days.any((day) => day < 1 || day > 7)) {
          throw const _ToolFailure(
            'invalid_weekdays',
            '"weekdays" needs days from 1 (Monday) to 7 (Sunday).',
          );
        }
        weekdays = days.toList()..sort();
      }
      if (args.containsKey('start_date')) startDate = _date(args, 'start_date');
      if (args.containsKey('end_date')) endDate = _date(args, 'end_date');
    }

    var mode = base.mode;
    var targetConversation = base.conversationId;
    switch (_string(args, 'target')) {
      case null:
        break;
      case 'new_chat':
        if (mode == ScheduledTaskMode.regenerate) {
          throw const _ToolFailure(
            'invalid_target',
            'This task regenerates a message; its target cannot change here.',
          );
        }
        mode = ScheduledTaskMode.newChat;
        targetConversation = null;
      case 'this_chat':
        if (mode == ScheduledTaskMode.regenerate) {
          throw const _ToolFailure(
            'invalid_target',
            'This task regenerates a message; its target cannot change here.',
          );
        }
        if (conversationId == null) {
          throw const _ToolFailure(
            'invalid_target',
            'There is no current chat to continue.',
          );
        }
        mode = ScheduledTaskMode.followUp;
        targetConversation = conversationId;
      case final other:
        throw _ToolFailure(
          'invalid_target',
          'Use "new_chat" or "this_chat", not "$other".',
        );
    }

    final assistantId = _string(args, 'assistant_id') ?? base.assistantId;
    if (!assistantNames.containsKey(assistantId)) {
      throw _ToolFailure('invalid_assistant', 'No assistant "$assistantId".');
    }

    return ScheduledTask(
      id: base.id,
      name: _string(args, 'name') ?? base.name,
      prompt: _string(args, 'prompt') ?? base.prompt,
      assistantId: assistantId,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      enabled: args['enabled'] is bool ? args['enabled'] as bool : base.enabled,
      nextRunAt: base.nextRunAt,
      runs: base.runs,
      mode: mode,
      conversationId: targetConversation,
      messageId: base.messageId,
      modelProvider: base.modelProvider,
      modelId: base.modelId,
      onceDate: onceDate,
      startDate: startDate,
      endDate: endDate,
      exhausted: base.exhausted,
      allowPreparation: base.allowPreparation,
      preparationPrompt: base.preparationPrompt,
      contextPolicy: base.contextPolicy,
      unavailablePolicy: base.unavailablePolicy,
      notify: args['notify'] is bool ? args['notify'] as bool : base.notify,
      showPreview: base.showPreview,
      preparationWindowMinutes: base.preparationWindowMinutes,
      maxPrepareAttempts: base.maxPrepareAttempts,
      preparationCooldownMinutes: base.preparationCooldownMinutes,
      revision: base.revision,
      scheduleRevision: base.scheduleRevision,
    );
  }

  static String? _string(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(Map<String, dynamic> args, String key) {
    final text = _string(args, key);
    if (text == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    final date = match == null
        ? null
        : DateTime(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
            int.parse(match.group(3)!),
          );
    if (date == null || ScheduledTask.dateKey(date) != text) {
      throw _ToolFailure('invalid_date', 'Use "yyyy-MM-dd" for $key.');
    }
    return date;
  }

  static String? _iso(DateTime? time) {
    if (time == null) return null;
    final local = time.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    String two(int value) => value.abs().toString().padLeft(2, '0');
    final stamp = local.toIso8601String().split('.').first;
    return '$stamp$sign${two(offset.inHours)}:${two(offset.inMinutes % 60)}';
  }
}
