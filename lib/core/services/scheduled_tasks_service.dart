import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/scheduled_task.dart';
import 'package:flutter/widgets.dart';

class ScheduledRunCancellation {
  bool cancelled = false;
  Future<void> Function()? onCancel;
  Future<void> cancel() async {
    cancelled = true;
    await onCancel?.call();
  }

  void check() {
    if (cancelled) throw StateError('cancelled');
  }
}

typedef ScheduledTaskExecutor =
    Future<Map<String, Object?>> Function(
      ScheduledTask task,
      ScheduledRunCancellation cancellation,
      Future<void> Function(String conversationId) onConversation,
    );

/// Runs one background job of a mini app: calls [function] of app [appId].
/// Throws when the job failed.
typedef MiniAppJobExecutor =
    Future<void> Function(
      String appId,
      String jobId,
      String function,
      ScheduledRunCancellation cancellation,
    );

class ScheduledTasksService extends ChangeNotifier {
  ScheduledTasksService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.scheduled_tasks') {
    _channel.setMethodCallHandler(_handle);
  }
  static final ScheduledTasksService instance = ScheduledTasksService();

  final MethodChannel _channel;
  ScheduledTaskExecutor? _executor;

  /// Runs the planner's mini app jobs (kind `miniAppJob`).
  MiniAppJobExecutor? miniAppJobs;
  final _active = <String, ScheduledRunCancellation>{};
  List<ScheduledTask> tasks = const [];
  bool exactAlarms = false;
  bool loaded = false;
  String? error;
  bool _disposed = false;

  Future<void> attach(ScheduledTaskExecutor executor) async {
    _executor = executor;
    try {
      await _channel.invokeMethod<void>('ready');
      await refresh();
    } catch (e) {
      _recordError(e);
    }
  }

  void detach(ScheduledTaskExecutor executor) {
    if (!identical(_executor, executor)) return;
    _executor = null;
    for (final cancellation in _active.values.toList()) {
      unawaited(cancellation.cancel().catchError(_recordError));
    }
  }

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'changed':
        await refresh();
      case 'run':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final id = args['runId'] as String;
        if (_active.containsKey(id)) return;
        final cancellation = ScheduledRunCancellation();
        _active[id] = cancellation;
        final task = jsonDecode(args['task'] as String) as Map<String, dynamic>;
        unawaited(
          task['kind'] == 'miniAppJob'
              ? _executeJob(id, task, cancellation)
              : _execute(id, ScheduledTask.fromJson(task), cancellation),
        );
      case 'cancel':
        await _active[call.arguments]?.cancel();
    }
  }

  Future<void> _execute(
    String id,
    ScheduledTask task,
    ScheduledRunCancellation cancellation,
  ) async {
    Map<String, Object?> result;
    try {
      final executor = _executor;
      cancellation.check();
      if (executor == null) throw StateError('runner_not_ready');
      result = await executor(
        task,
        cancellation,
        (conversationId) => _channel.invokeMethod<void>('conversation', {
          'runId': id,
          'conversationId': conversationId,
        }),
      );
    } catch (e) {
      try {
        await cancellation.cancel();
      } catch (_) {
        // Still report the original execution failure if cleanup also fails.
      }
      result = {'status': 'failed', 'error': e.toString()};
    }
    try {
      await _channel.invokeMethod<void>('finish', {'runId': id, ...result});
    } catch (e) {
      _recordError(e);
    } finally {
      _active.remove(id);
      await refresh();
    }
  }

  Future<void> _executeJob(
    String id,
    Map<String, dynamic> job,
    ScheduledRunCancellation cancellation,
  ) async {
    Map<String, Object?> result;
    try {
      final executor = miniAppJobs;
      if (executor == null) throw StateError('runner_not_ready');
      await executor(
        job['appId'] as String,
        job['jobId'] as String,
        job['run'] as String,
        cancellation,
      );
      result = {'status': 'completed'};
    } catch (e) {
      result = {
        'status': 'failed',
        'error': e is StateError ? e.message : e.toString(),
      };
    }
    try {
      await _channel.invokeMethod<void>('finish', {'runId': id, ...result});
    } catch (e) {
      _recordError(e);
    } finally {
      _active.remove(id);
    }
  }

  void _apply(Map<Object?, Object?> data) {
    if (_disposed) return;
    tasks = (data['tasks'] as List)
        .map(
          (raw) => ScheduledTask.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          ),
        )
        .toList();
    exactAlarms = data['exactAlarms'] == true;
    loaded = true;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      _apply((await _channel.invokeMapMethod<Object?, Object?>('list'))!);
    } catch (e) {
      _recordError(e);
    }
  }

  void _recordError(Object e) {
    if (_disposed) return;
    error = e.toString();
    loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> save(ScheduledTask task, {bool? enabled}) async {
    _apply(
      (await _channel.invokeMapMethod<Object?, Object?>(
        'save',
        task.toJson(enabled: enabled),
      ))!,
    );
  }

  Future<void> delete(String id) async {
    _apply(
      (await _channel.invokeMapMethod<Object?, Object?>('delete', {'id': id}))!,
    );
  }

  Future<void> runNow(String id) async {
    _apply(
      (await _channel.invokeMapMethod<Object?, Object?>('runNow', {'id': id}))!,
    );
  }

  Future<void> requestPermission() => _channel.invokeMethod<void>('permission');
}
