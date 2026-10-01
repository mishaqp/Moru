import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../features/home/services/tool_approval_service.dart';
import '../models/mobile_background_settings.dart';
import '../providers/settings_provider.dart';
import 'notification_service.dart';

enum BackgroundTaskPhase { requesting, generating, thinking, tool, retrying }

enum BackgroundTaskOutcome { completed, failed, cancelled, interrupted }

class MobileBackgroundStatus {
  const MobileBackgroundStatus([this.values = const {}]);

  final Map<String, dynamic> values;
  bool flag(String key) => values[key] == true;
  String text(String key) => values[key]?.toString() ?? '';
}

class _BackgroundTask {
  _BackgroundTask({
    required this.id,
    required this.conversationId,
    required this.assistantMessageId,
    required this.title,
    required this.cancel,
    required this.startedAt,
    required this.scheduled,
    this.beforeRuntimeStop,
    this.scheduledNotify = true,
    this.scheduledPreview = true,
  });

  final String id;
  final String conversationId;
  final String assistantMessageId;
  final String title;
  final Future<void> Function() cancel;
  final Future<void> Function()? beforeRuntimeStop;
  final DateTime startedAt;
  final bool scheduled;
  final bool scheduledNotify, scheduledPreview;
  BackgroundTaskPhase phase = BackgroundTaskPhase.requesting;
  String toolName = '';
  int tokens = 0;
  bool interrupted = false;
  bool runtimeStopped = false;
}

/// Owns background task identities. Native code receives whole snapshots
/// on one serial channel; a late update/finish cannot resurrect a removed run.
class MobileBackgroundCoordinator extends ChangeNotifier
    with WidgetsBindingObserver {
  MobileBackgroundCoordinator({
    TargetPlatform? platform,
    MethodChannel? channel,
    this.notificationSender,
  }) : platform = platform ?? defaultTargetPlatform,
       _channel = channel ?? const MethodChannel('app.mobile_background');

  static final instance = MobileBackgroundCoordinator();
  final TargetPlatform platform;
  final MethodChannel _channel;
  final ChatCompletionNotificationSender? notificationSender;
  final Map<String, _BackgroundTask> _tasks = {};
  final Map<String, _BackgroundTask> _finishingTasks = {};
  final Set<String> _runtimeStoppedTasks = {};
  final Map<String, String> _pendingTaskTransfers = {};
  MobileBackgroundSettings _settings = const MobileBackgroundSettings();
  MobileBackgroundSettings get settings => _settings;
  MobileBackgroundStatus status = const MobileBackgroundStatus();
  String? lastError;
  AppLocalizations? _l10n;
  bool _initialized = false;
  bool _foreground = true;
  bool get isForeground => _foreground;
  bool get hasActiveWork =>
      _tasks.isNotEmpty || (status.values['activeOwners'] as num? ?? 0) > 0;
  bool get supported => platform == TargetPlatform.android;
  String get backgroundShellRunningText =>
      _l10n?.backgroundShellRunning ?? 'Running a background command';
  String get backgroundServerRunningText =>
      _l10n?.backgroundServerRunning ?? 'Running a mini app server';
  String get backgroundProtectionUnavailableText =>
      _l10n?.backgroundProtectionUnavailable ??
      'Background protection unavailable';
  String? Function()? visibleConversation;

  /// Whether [taskId] (this task's own id -- see [finish]) belongs to a
  /// browser Ask-AI request whose own UI is, right now, the visible,
  /// foreground surface showing (or about to show) its result, for the
  /// exact conversation [conversationId] names. Distinct from
  /// [visibleConversation]: the browser page is pushed as its own route on
  /// top of Home, so Home's own "is this conversation on screen" check can
  /// never by itself see the browser's Ask-AI surface, and checking only
  /// "is the browser open" would also suppress a notification for a
  /// different, unrelated run or a browser covered by another screen. Set
  /// by `HomePageController._setupBrowserAskAi` to
  /// `BrowserAgentSession.instance.consumeVisibleAskAiTask`.
  bool Function(String taskId, String conversationId)? visibleBrowserAskAiTask;
  Future<void>? _tail;
  Timer? _updateTimer;
  int _revision = 0;
  int _approvalRevision = 0;
  ToolApprovalService? _approvals;
  Future<void>? _approvalTail;
  String? _approvalSnapshotKey;
  bool _disposed = false;
  final Set<String> _reportedShellResults = {};

  /// Bind the process coordinator to the actual Provider-owned approval gate.
  void bindApprovals(ToolApprovalService service) {
    if (identical(_approvals, service)) return;
    _approvals?.removeListener(reconcileApprovals);
    _approvals = service;
    service.addListener(reconcileApprovals);
    _approvalSnapshotKey = null;
    reconcileApprovals();
  }

  void cancelRunApprovals(String conversationId, String generationRunId) {
    _approvals?.cancelForRun(conversationId, generationRunId);
    reconcileApprovals();
  }

  /// Serialize notification mirrors independently of resource operations/ACKs.
  void reconcileApprovals() {
    if (!supported || _disposed) return;
    final previous = _approvalTail;
    _approvalTail =
        (previous == null
                ? Future<void>.sync(_sendApprovalSnapshot)
                : previous.then((_) => _sendApprovalSnapshot()))
            .catchError(_recordError);
  }

  Future<void> _sendApprovalSnapshot() async {
    if (_disposed) return;
    await initialize();
    final l = _l10n;
    final pending = _settings.notificationsEnabled
        ? (_approvals?.pendingRequests ?? const <ToolApprovalRequest>[])
              .where(
                (request) =>
                    request.hasLiveOwner &&
                    !(_foreground &&
                        visibleConversation?.call() == request.conversationId),
              )
              .map(
                (request) => {
                  'approvalId': request.approvalId,
                  'conversationId': request.conversationId,
                  'generationRunId': request.generationRunId,
                  'assistantMessageId': request.assistantMessageId,
                  'title': l?.notificationApprovalTitle ?? 'Approval needed',
                  'body':
                      l?.notificationApprovalBody ??
                      'An agent is waiting for your decision.',
                },
              )
              .toList()
        : const [];
    final snapshot = <String, Object?>{
      'version': 1,
      'settings': {
        'enabled': _settings.notificationsEnabled,
        'privacyMode': _settings.privacyMode,
      },
      'pending': pending,
      'labels': {
        'allow': l?.notificationApprovalAllow ?? 'Allow',
        'deny': l?.notificationApprovalDeny ?? 'Deny',
        'open': l?.backgroundOpenChat ?? 'Open chat',
        'staleTitle':
            l?.notificationApprovalStaleTitle ?? 'Approval no longer available',
        'staleBody':
            l?.notificationApprovalStaleBody ??
            'Open the chat to check this request.',
        'privateTitle': l?.notificationApprovalTitle ?? 'Approval needed',
        'privateBody':
            l?.notificationApprovalBody ??
            'An agent is waiting for your decision.',
        'channelName': l?.notificationApprovalChannelName ?? 'Agent approvals',
        'channelDescription':
            l?.notificationApprovalChannelDescription ??
            'Decisions requested by a running agent or tool.',
      },
    };
    final key = jsonEncode(snapshot);
    if (key == _approvalSnapshotKey) return;
    snapshot['revision'] = ++_approvalRevision;
    await _channel.invokeMethod<void>('syncApprovals', snapshot);
    _approvalSnapshotKey = key;
  }

  @visibleForTesting
  Set<String> get activeTaskIds => Set.unmodifiable(_tasks.keys);

  bool wasInterrupted(String id) => _tasks[id]?.interrupted == true;

  bool isTaskStopping(String id) {
    final task = _tasks[id] ?? _finishingTasks[id];
    return task?.runtimeStopped == true || task?.interrupted == true;
  }

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    _initialized = true;
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleNativeCall);
    await _enqueue(() async {
      final pending = await _channel.invokeMethod<Object?>(
        'takePendingConversation',
      );
      NotificationService.openNativeConversationTarget(pending);
    });
  }

  /// Settings can finish loading after the last frame before going background.
  /// Read them after loading, without requiring another widget rebuild.
  Future<void> configureFromSettings(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) async {
    await settings.loaded;
    await configure(settings.mobileBackground, l10n);
  }

  Future<void> configure(
    MobileBackgroundSettings settings,
    AppLocalizations l10n,
  ) async {
    final changed =
        jsonEncode(_settings.toJson()) != jsonEncode(settings.toJson()) ||
        _l10n?.localeName != l10n.localeName;
    _settings = settings;
    _l10n = l10n;
    await NotificationService.configureLocalizations(l10n);
    await initialize();
    if (changed) {
      reconcileApprovals();
      await _sync();
    }
  }

  Future<void> start({
    required String id,
    required String conversationId,
    String assistantMessageId = '',
    required String title,
    required Future<void> Function() cancel,
    Future<void> Function()? beforeRuntimeStop,
    bool scheduled = false,
    bool scheduledNotify = true,
    bool scheduledPreview = true,
  }) async {
    if (!supported || _tasks.containsKey(id)) return;
    _tasks[id] = _BackgroundTask(
      id: id,
      conversationId: conversationId,
      assistantMessageId: assistantMessageId,
      title: title,
      cancel: cancel,
      beforeRuntimeStop: beforeRuntimeStop,
      startedAt: DateTime.now(),
      scheduled: scheduled,
      scheduledNotify: scheduledNotify,
      scheduledPreview: scheduledPreview,
    );
    notifyListeners();
    await initialize();
    await _sync();
  }

  /// Replace a preparation lease with its persisted execution in one snapshot.
  /// Native foreground ownership never passes through an empty task list.
  Future<bool> transferTask({
    required String fromId,
    required String id,
    required String conversationId,
    required String assistantMessageId,
    required String title,
    required Future<void> Function() cancel,
    Future<void> Function()? beforeRuntimeStop,
  }) async {
    final previous = _tasks[fromId];
    if (previous == null ||
        previous.conversationId != conversationId ||
        _tasks.containsKey(id)) {
      return false;
    }
    final next =
        _BackgroundTask(
            id: id,
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            title: title,
            cancel: cancel,
            beforeRuntimeStop: beforeRuntimeStop,
            startedAt: previous.startedAt,
            scheduled: previous.scheduled,
            scheduledNotify: previous.scheduledNotify,
            scheduledPreview: previous.scheduledPreview,
          )
          ..interrupted = previous.interrupted
          ..runtimeStopped = previous.runtimeStopped;
    _tasks.remove(fromId);
    _tasks[id] = next;
    if (next.runtimeStopped) _runtimeStoppedTasks.add(id);
    _pendingTaskTransfers[fromId] = id;
    notifyListeners();
    try {
      await _sync();
    } finally {
      if (_pendingTaskTransfers[fromId] == id) {
        _pendingTaskTransfers.remove(fromId);
        _runtimeStoppedTasks.remove(fromId);
      }
    }
    return true;
  }

  void update(
    String id, {
    required BackgroundTaskPhase phase,
    int? tokens,
    String toolName = '',
  }) {
    final task = _tasks[id];
    if (task == null) return;
    task.phase = phase;
    task.toolName = toolName;
    if (tokens != null) task.tokens = tokens;
    _updateTimer ??= Timer(const Duration(milliseconds: 500), () {
      _updateTimer = null;
      unawaited(_sync());
    });
  }

  Future<void> finish(
    String id,
    BackgroundTaskOutcome outcome, {
    bool resultPersisted = true,
    String? replyPreview,
  }) async {
    final task = _tasks.remove(id);
    if (task == null) return;
    _finishingTasks[id] = task;
    _approvals?.cancelForRun(task.conversationId, task.id);
    reconcileApprovals();
    notifyListeners();
    if (task.runtimeStopped) {
      outcome = BackgroundTaskOutcome.cancelled;
    } else if (task.interrupted) {
      outcome = BackgroundTaskOutcome.interrupted;
    }
    _cancelUpdateTimer();
    final snapshot = _snapshot(
      terminal: {
        ..._taskMap(task),
        'outcome': outcome.name,
        'detail': _outcomeText(outcome),
        'finishedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
    try {
      await _enqueue(() async {
        final l10n = _l10n;
        // Evaluated here, at the moment the notification would actually be
        // sent, not when finish() was first called: "is the browser's own
        // Ask-AI surface visible right now" is a live question, not one this
        // could answer earlier and cache.
        final suppressedByVisibleBrowserAskAi =
            _foreground &&
            (visibleBrowserAskAiTask?.call(id, task.conversationId) ?? false);
        if (resultPersisted &&
            !task.runtimeStopped &&
            (task.scheduled
                ? task.scheduledNotify
                : _settings.notificationsEnabled) &&
            outcome != BackgroundTaskOutcome.cancelled &&
            !(_foreground &&
                visibleConversation?.call() == task.conversationId) &&
            !suppressedByVisibleBrowserAskAi) {
          try {
            await _publishResult(
              conversationId: task.conversationId,
              generationRunId: task.id,
              assistantMessageId: task.assistantMessageId,
              outcome: outcome,
              title: _settings.privacyMode || task.title.trim().isEmpty
                  ? (l10n?.backgroundTaskTitle ?? 'Moru')
                  : task.title,
              body:
                  (!task.scheduled || task.scheduledPreview) &&
                      !_settings.privacyMode &&
                      outcome == BackgroundTaskOutcome.completed &&
                      replyPreview?.trim().isNotEmpty == true
                  ? replyPreview!.trim().characters.take(200).toString()
                  : _outcomeText(outcome),
            );
          } catch (error) {
            _recordError(error);
          }
        }
        // Earlier queued updates retain their active-task snapshot, so the
        // native runtime keeps the task until this notification is posted.
        await _sendSnapshot(snapshot);
      });
    } finally {
      if (identical(_finishingTasks[id], task)) _finishingTasks.remove(id);
      _runtimeStoppedTasks.remove(id);
    }
  }

  Future<void> _publishResult({
    required String conversationId,
    required String generationRunId,
    required String assistantMessageId,
    required BackgroundTaskOutcome outcome,
    required String title,
    required String body,
    String? privateBody,
  }) async {
    final sender = notificationSender;
    if (sender != null) {
      await sender(conversationId: conversationId, title: title, body: body);
      return;
    }
    await _channel.invokeMethod<void>('showResult', {
      'conversationId': conversationId,
      'generationRunId': generationRunId,
      'assistantMessageId': assistantMessageId,
      'outcome': outcome.name,
      'title': title,
      'body': body,
      'privateTitle': _l10n?.backgroundTaskTitle ?? 'Moru',
      'privateBody': privateBody ?? _outcomeText(outcome),
    });
  }

  /// Shell completion belongs to the actual job, after the chat turn ended.
  Future<void> reportBackgroundShellResult({
    required String id,
    required String conversationId,
    required bool succeeded,
  }) async {
    if (!supported ||
        id.isEmpty ||
        conversationId.isEmpty ||
        !_reportedShellResults.add(id)) {
      return;
    }
    await initialize();
    await _enqueue(() async {
      if (!_settings.notificationsEnabled ||
          (_foreground && visibleConversation?.call() == conversationId)) {
        return;
      }
      final outcome = succeeded
          ? BackgroundTaskOutcome.completed
          : BackgroundTaskOutcome.failed;
      final body = succeeded
          ? (_l10n?.backgroundShellCompleted ?? 'Background command finished')
          : (_l10n?.backgroundShellFailed ?? 'Background command failed');
      await _publishResult(
        conversationId: conversationId,
        generationRunId: id,
        assistantMessageId: '',
        outcome: outcome,
        title: _l10n?.backgroundTaskTitle ?? 'Moru',
        body: body,
        privateBody: body,
      );
    });
  }

  String _outcomeText(BackgroundTaskOutcome outcome) => switch (outcome) {
    BackgroundTaskOutcome.completed =>
      _l10n?.backgroundCompleted ?? 'Generation complete',
    BackgroundTaskOutcome.failed =>
      _l10n?.backgroundFailed ?? 'Generation failed',
    BackgroundTaskOutcome.cancelled =>
      _l10n?.backgroundCancelled ?? 'Generation cancelled',
    BackgroundTaskOutcome.interrupted =>
      _l10n?.backgroundInterrupted ?? 'Background generation interrupted',
  };

  Map<String, Object?> _taskMap(_BackgroundTask task) {
    final detail = switch (task.phase) {
      BackgroundTaskPhase.requesting => _l10n?.backgroundRequesting,
      BackgroundTaskPhase.generating => _l10n?.backgroundGenerating,
      BackgroundTaskPhase.thinking => _l10n?.backgroundThinking,
      BackgroundTaskPhase.tool => _l10n?.backgroundToolRunning,
      BackgroundTaskPhase.retrying => _l10n?.backgroundRetrying,
    };
    return {
      'id': task.id,
      'conversationId': task.conversationId,
      'title': _settings.privacyMode
          ? (_l10n?.backgroundTaskTitle ?? 'Moru')
          : task.title,
      'detail': _settings.privacyMode
          ? (_l10n?.backgroundWorking ?? 'Working')
          : '${detail ?? task.phase.name}${task.phase == BackgroundTaskPhase.tool && task.toolName.isNotEmpty ? ': ${task.toolName}' : ''}',
      'tokens': _settings.privacyMode ? 0 : task.tokens,
      'startedAt': task.startedAt.millisecondsSinceEpoch,
    };
  }

  Future<void> _sync() {
    _cancelUpdateTimer();
    final snapshot = _snapshot();
    return _enqueue(() => _sendSnapshot(snapshot));
  }

  Map<String, dynamic> _snapshot({Map<String, Object?>? terminal}) => {
    'revision': ++_revision,
    'settings': {
      ..._settings.toJson(),
      'completionSeconds': _settings.completionVisibility.seconds,
    },
    'tasks': _tasks.values.map(_taskMap).toList(),
    'terminal': terminal,
    'labels': {
      'app': 'Moru',
      'working': _l10n?.backgroundWorking ?? 'Working',
      'tasks': _l10n?.backgroundTasks ?? 'Tasks',
      'stop': _l10n?.backgroundStopTasks ?? 'Stop tasks',
      'open': _l10n?.backgroundOpenChat ?? 'Open chat',
      'close': _l10n?.commonClose ?? 'Close',
      'completed': _l10n?.backgroundCompleted ?? 'Generation complete',
      'interrupted':
          _l10n?.backgroundInterrupted ?? 'Background generation interrupted',
      'stale': _l10n?.backgroundStale ?? 'Open Kelivo to check the task.',
    },
  };

  Future<void> _sendSnapshot(Map<String, dynamic> snapshot) async {
    // Stop also covers a claimed FIFO successor whose snapshot is still
    // queued behind the finishing owner. Such an old snapshot must not promote
    // a stopped run after the native Stop has released foreground resources.
    (snapshot['tasks'] as List<Map<String, Object?>>).removeWhere(
      (task) => _runtimeStoppedTasks.contains(task['id']),
    );
    final terminal = snapshot['terminal'] as Map<String, Object?>?;
    if (terminal != null && _runtimeStoppedTasks.contains(terminal['id'])) {
      terminal['outcome'] = BackgroundTaskOutcome.cancelled.name;
      terminal['detail'] = _outcomeText(BackgroundTaskOutcome.cancelled);
    }
    // Redact queued payloads as well when privacy was enabled while a previous
    // native call was still in flight.
    if (_settings.privacyMode) {
      snapshot['settings'] = {
        ...snapshot['settings'] as Map<String, dynamic>,
        'privacyMode': true,
      };
      void redact(Map<String, Object?> task, {bool terminal = false}) {
        task['title'] = _l10n?.backgroundTaskTitle ?? 'Moru';
        if (!terminal) task['detail'] = _l10n?.backgroundWorking ?? 'Working';
        task['tokens'] = 0;
      }

      for (final task in snapshot['tasks'] as List<Map<String, Object?>>) {
        redact(task);
      }
      final terminal = snapshot['terminal'] as Map<String, Object?>?;
      if (terminal != null) redact(terminal, terminal: true);
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'sync',
      snapshot,
    );
    if (result != null) {
      status = MobileBackgroundStatus(result);
      notifyListeners();
    }
  }

  Future<void> refreshStatus() => _enqueue(() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getStatus');
    if (result != null) {
      final next = MobileBackgroundStatus(result);
      final permissionChanged =
          status.flag('notificationsAuthorized') !=
              next.flag('notificationsAuthorized') ||
          status.flag('approvalChannelEnabled') !=
              next.flag('approvalChannelEnabled');
      status = next;
      if (permissionChanged) {
        _approvalSnapshotKey = null;
        reconcileApprovals();
      }
    }
    notifyListeners();
  });

  /// Called only by explicit settings actions. Neither sync nor status requests
  /// permissions, including when the app is reopened with enabled settings.
  Future<void> requestPermission(String permission) =>
      _settingsAction('requestPermission', permission);

  Future<void> openSettings(String destination) =>
      _settingsAction('openSettings', destination);

  Future<void> _settingsAction(String method, String argument) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, argument);
    } catch (error) {
      _recordError(error);
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'approvalAction') {
      final args = call.arguments;
      if (args is! Map || _disposed || !_settings.notificationsEnabled) {
        return {'status': 'stale'};
      }
      final choice = args['action'];
      final keys = [
        'approvalId',
        'conversationId',
        'generationRunId',
        'assistantMessageId',
      ];
      if ((choice != 'allow' && choice != 'deny') ||
          keys.any((key) => args[key] is! String)) {
        return {'status': 'stale'};
      }
      final outcome =
          _approvals?.resolveNotificationApproval(
            approvalId: args['approvalId'] as String,
            conversationId: args['conversationId'] as String,
            generationRunId: args['generationRunId'] as String,
            assistantMessageId: args['assistantMessageId'] as String,
            approved: choice == 'allow',
          ) ??
          ToolApprovalActionStatus.stale;
      return {'status': outcome.name};
    } else if (call.method == 'openConversation') {
      NotificationService.openNativeConversationTarget(call.arguments);
    } else if (call.method == 'cancelTasks' || call.method == 'interrupted') {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      final ids = (args['ids'] as List? ?? []).cast<String>().toSet();
      ids.addAll([
        for (final id in ids)
          if (_pendingTaskTransfers[id] case final actualId?) actualId,
      ]);
      final owners = {..._finishingTasks, ..._tasks};
      final affectedConversations = owners.values
          .where((task) => ids.contains(task.id))
          .map((task) => task.conversationId)
          .toSet();
      final tasks = owners.values
          .where((task) => affectedConversations.contains(task.conversationId))
          .toList();
      if (call.method == 'interrupted') {
        _recordError(args['reason'] ?? 'background_interrupted');
        for (final task in tasks) {
          task.interrupted = true;
        }
      }
      // A channel callback must not wait for cancellation to call back into the
      // same native sync queue.
      final holds = <String, Future<void>>{};
      for (final task in tasks) {
        if (call.method == 'cancelTasks') {
          task.runtimeStopped = true;
          _runtimeStoppedTasks.add(task.id);
          _approvals?.cancelForRun(task.conversationId, task.id);
        }
        unawaited(
          Future<void>.sync(() async {
            try {
              if (task.runtimeStopped) {
                await holds.putIfAbsent(
                  task.conversationId,
                  () => Future<void>.sync(() async {
                    await task.beforeRuntimeStop?.call();
                  }),
                );
              }
            } finally {
              await task.cancel();
            }
          }).catchError(_recordError),
        );
      }
    } else if (call.method == 'statusChanged') {
      unawaited(refreshStatus());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(_sync());
      unawaited(refreshStatus());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
    }
    reconcileApprovals();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (!supported) return Future<void>.value();
    final previous = _tail;
    final next = previous == null
        ? Future<void>.sync(operation)
        : previous.then((_) => operation());
    return _tail = next.catchError(_recordError);
  }

  void _recordError(Object error) {
    lastError = error.toString();
    debugPrint('[MobileBackground] $error');
    notifyListeners();
  }

  void _cancelUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  @visibleForTesting
  Future<void> flush() async {
    if (_updateTimer != null) await _sync();
    await _tail;
    await _approvalTail;
  }

  @override
  void dispose() {
    _disposed = true;
    _approvals?.removeListener(reconcileApprovals);
    _cancelUpdateTimer();
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
