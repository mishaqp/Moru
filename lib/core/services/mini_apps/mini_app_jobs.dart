import 'dart:convert';

import 'package:flutter/services.dart';

import 'mini_app_reminders.dart';
import 'mini_app_store.dart';

/// Where jobs are scheduled: the native planner of scheduled tasks, which
/// wakes Moru, runs the job through [ScheduledTasksService] and keeps the
/// last runs.
class MiniAppJobScheduler {
  const MiniAppJobScheduler({
    required this.save,
    required this.delete,
    required this.list,
    required this.runNow,
  });

  final Future<void> Function(Map<String, Object?> job) save;
  final Future<void> Function(String id) delete;

  /// The app's scheduled jobs as the planner keeps them: definition,
  /// `nextRunAt` and `runs`, newest first.
  final Future<List<Map<String, dynamic>>> Function(String appId) list;
  final Future<void> Function(String id) runNow;

  static const MethodChannel _channel = MethodChannel('app.scheduled_tasks');

  static final MiniAppJobScheduler platform = MiniAppJobScheduler(
    save: (job) => _channel.invokeMethod<void>('saveJob', job),
    delete: (id) => _channel.invokeMethod<void>('deleteJob', {'id': id}),
    list: (appId) async => [
      for (final raw
          in await _channel.invokeListMethod<String>('listJobs', {
                'appId': appId,
              }) ??
              const <String>[])
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
    ],
    runNow: (id) => _channel.invokeMethod<void>('runNow', {'id': id}),
  );

  /// Schedules nothing, e.g. for the check after publishing.
  static final MiniAppJobScheduler none = MiniAppJobScheduler(
    save: (_) async {},
    delete: (_) async {},
    list: (_) async => const [],
    runNow: (_) async {},
  );
}

/// One run of a job, newest first in [MiniAppJob.runs].
class MiniAppJobRun {
  const MiniAppJobRun({
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.error,
  });

  /// `running`, `completed`, `failed` or `interrupted`.
  final String status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? error;

  static MiniAppJobRun? fromJson(Object? raw) {
    if (raw is! Map || raw['startedAt'] is! int) return null;
    return MiniAppJobRun(
      status: '${raw['status'] ?? 'failed'}',
      startedAt: DateTime.fromMillisecondsSinceEpoch(raw['startedAt'] as int),
      finishedAt: raw['finishedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(raw['finishedAt'] as int)
          : null,
      error: raw['error'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status,
    'at': startedAt.toIso8601String(),
    'error': ?error,
  };
}

/// A job as the app defined it, with what the planner knows about it.
class MiniAppJob {
  const MiniAppJob({
    required this.id,
    required this.time,
    required this.run,
    this.days,
    this.nextRunAt,
    this.runs = const [],
  });

  final String id;

  /// "HH:mm".
  final String time;

  /// Weekdays 1 (Monday) to 7, or null for every day.
  final List<int>? days;

  /// Global function of the app that the job calls.
  final String run;
  final DateTime? nextRunAt;
  final List<MiniAppJobRun> runs;

  Map<String, Object?> toJson() => {
    'id': id,
    'time': time,
    'days': ?days,
    'run': run,
    'nextRunAt': ?nextRunAt?.toIso8601String(),
    'lastRun': ?(runs.isEmpty ? null : runs.first.toJson()),
  };
}

/// Background jobs a mini app sets with `moru.jobs`: at a time of day Moru
/// opens the app out of sight and calls one of its functions, e.g. to check
/// the weather and send a notification. Definitions are kept with the app,
/// so a restored backup schedules them again.
class MiniAppJobs {
  MiniAppJobs({required this.store, required this.scheduler});

  static const int maxJobs = 10;

  final MiniAppStore store;
  final MiniAppJobScheduler scheduler;

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,40}$');
  static final RegExp _function = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]{0,63}$');

  /// The planner's id of job [id] of [appId].
  static String scheduledId(String appId, String id) => 'miniapp:$appId:$id';

  /// Adds or replaces job [id]: `{time: "HH:mm", days?: [1..7], run:
  /// "functionName"}`.
  Future<void> set(String appId, String id, Object? raw) async {
    if (!_id.hasMatch(id)) {
      throw const MiniAppException(
        'invalid_job',
        'Job ids are 1-40 letters, digits, "-" or "_".',
      );
    }
    final job = normalize(raw);
    final all = await store.readJobs(appId);
    if (!all.containsKey(id) && all.length >= maxJobs) {
      throw const MiniAppException(
        'too_many_jobs',
        'An app may keep at most $maxJobs jobs.',
      );
    }
    all[id] = job;
    await store.writeJobs(appId, all);
    await _schedule(appId, id, job);
  }

  Future<void> remove(String appId, String id) async {
    final all = await store.readJobs(appId);
    if (all.remove(id) == null) return;
    await store.writeJobs(appId, all);
    await scheduler.delete(scheduledId(appId, id));
  }

  /// Runs job [id] now, in the background like a scheduled run.
  Future<void> runNow(String appId, String id) async {
    final all = await store.readJobs(appId);
    if (all[id] is! Map) {
      throw MiniAppException('not_found', 'No job "$id".');
    }
    // Make sure the planner knows it, e.g. right after a restore.
    await _schedule(appId, id, Map<String, dynamic>.from(all[id] as Map));
    try {
      await scheduler.runNow(scheduledId(appId, id));
    } on PlatformException catch (e) {
      throw MiniAppException(
        'run_failed',
        e.message == 'task_running'
            ? 'The job is already running.'
            : e.message ?? e.code,
      );
    }
  }

  /// The app's jobs with their next and last runs, ordered by id.
  Future<List<MiniAppJob>> list(String appId) async {
    final all = await store.readJobs(appId);
    final scheduled = {
      for (final job in await scheduler.list(appId)) '${job['id']}': job,
    };
    final ids = all.keys.toList()..sort();
    return [
      for (final id in ids)
        if (all[id] case final Map job)
          _merge(id, job, scheduled[scheduledId(appId, id)]),
    ];
  }

  static MiniAppJob _merge(String id, Map job, Map<String, dynamic>? state) {
    final next = state?['nextRunAt'];
    return MiniAppJob(
      id: id,
      time: '${job['time']}',
      days: (job['days'] as List?)?.cast<int>(),
      run: '${job['run']}',
      nextRunAt: next is int ? DateTime.fromMillisecondsSinceEpoch(next) : null,
      runs: [
        for (final raw in state?['runs'] as List? ?? const [])
          ?MiniAppJobRun.fromJson(raw),
      ],
    );
  }

  /// Schedules every stored job again; after a backup restore this brings
  /// the restored apps' jobs back.
  Future<void> rescheduleAll() async {
    await store.load();
    for (final app in store.apps) {
      final all = await store.readJobs(app.id);
      for (final entry in all.entries) {
        try {
          await _schedule(app.id, entry.key, normalize(entry.value));
        } on MiniAppException {
          // A damaged or refused job stays unscheduled; the others still get
          // scheduled and the app can set it again.
        }
      }
    }
  }

  /// Unschedules every job of the app, for example before it is deleted.
  Future<void> cancelAll(String appId) async {
    for (final id in (await store.readJobs(appId)).keys) {
      await scheduler.delete(scheduledId(appId, id));
    }
  }

  /// Checks a job definition and keeps only what the job needs.
  static Map<String, dynamic> normalize(Object? raw) {
    if (raw is! Map) {
      throw const MiniAppException(
        'invalid_job',
        'A job is an object with "time" and "run".',
      );
    }
    final function = '${raw['run'] ?? ''}'.trim();
    if (!_function.hasMatch(function)) {
      throw const MiniAppException(
        'invalid_job',
        '"run" must name a global function of the app, e.g. "checkWeather".',
      );
    }
    final Map<String, dynamic> when;
    try {
      when = MiniAppReminders.normalize(raw);
    } on MiniAppException catch (e) {
      throw MiniAppException('invalid_job', e.message);
    }
    return {'time': when['time'], 'days': ?when['days'], 'run': function};
  }

  Future<void> _schedule(
    String appId,
    String id,
    Map<String, dynamic> job,
  ) async {
    final parts = (job['time'] as String).split(':');
    try {
      await _save(appId, id, job, parts);
    } on PlatformException catch (e) {
      throw MiniAppException(
        'schedule_failed',
        'Moru could not schedule the job: ${e.message ?? e.code}',
      );
    }
  }

  Future<void> _save(
    String appId,
    String id,
    Map<String, dynamic> job,
    List<String> parts,
  ) async {
    await scheduler.save({
      'id': scheduledId(appId, id),
      'kind': 'miniAppJob',
      'appId': appId,
      'jobId': id,
      'run': job['run'],
      'hour': int.parse(parts[0]),
      'minute': int.parse(parts[1]),
      'weekdays': (job['days'] as List?)?.cast<int>() ?? [1, 2, 3, 4, 5, 6, 7],
    });
  }
}
