import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import '../api/tool_call_cancellation.dart';

import 'mini_app_device.dart';
import 'mini_app_expressions.dart';
import 'mini_app_manifest.dart';
import 'mini_app_permissions.dart';
import 'mini_app_store.dart';

enum MiniAppInvocationSource { button, chat, acp, background, wifi }

class MiniAppInvocation {
  const MiniAppInvocation({
    required this.source,
    this.isAllowed,
    this.fullTrust,
    this.approve,
    this.cancelled,
    this.forceConfirmation = false,
  });
  final MiniAppInvocationSource source;
  final bool Function()? isAllowed;
  final bool Function()? fullTrust;
  final Future<void>? cancelled;
  final bool forceConfirmation;
  final Future<bool> Function(
    MiniApp app,
    MiniAppAction action,
    Map<String, dynamic> arguments,
  )?
  approve;
  bool get isAi =>
      source == MiniAppInvocationSource.chat ||
      source == MiniAppInvocationSource.acp;
}

class MiniAppToolBinding {
  const MiniAppToolBinding(this.app, this.action);
  final MiniApp app;
  final MiniAppAction action;
  String get appId => app.id;
  String get actionName => action.name;
}

/// Every new UI/AI/device entry goes through the same live authorization.
class MiniAppRuntime {
  MiniAppRuntime({
    required this.store,
    MiniAppDeviceService? device,
    DateTime Function()? now,
  }) : device = device ?? MiniAppDeviceService(),
       _now = now ?? DateTime.now,
       permissions = MiniAppPermissions(store) {
    _storageSub = store.dataChanges.listen((event) => _refresh(event.appId));
    _permissionSub = permissions.changes.listen((id) {
      _cancelStaleRequests(id);
      _refresh(id);
      unawaited(_syncDeviceWatch());
    });
    _lifecycleSub = store.lifecycleChanges.listen(_cancelStaleRequests);
    store.addListener(_storeChanged);
  }

  final MiniAppStore store;
  final MiniAppDeviceService device;
  final MiniAppPermissions permissions;
  final DateTime Function() _now;
  final StreamController<({String appId, Map<String, dynamic> state})>
  _changes = StreamController.broadcast();
  late final StreamSubscription<({String appId, int revision})> _storageSub;
  late final StreamSubscription<String> _permissionSub;
  late final StreamSubscription<String> _lifecycleSub;
  final Set<_Request> _activeRequests = {};
  final Map<String, Set<StreamController<Map<String, dynamic>>>> _watchers = {};
  StreamSubscription<Map<String, dynamic>>? _deviceSub;
  int _watchEpoch = 0;
  final Map<String, int> _refreshEpochs = {};
  bool _disposed = false;
  static Future<void> _mutationTail = Future.value();

  Stream<({String appId, Map<String, dynamic> state})> get changes =>
      _changes.stream;

  static String toolNameFor(String appId, String actionName) {
    String safe(String value, int max) {
      final result = value.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');
      return result.substring(0, result.length > max ? max : result.length);
    }

    final digest = sha256
        .convert(utf8.encode('$appId\u0000$actionName'))
        .toString()
        .substring(0, 16);
    return 'ma_${safe(appId, 18)}_${safe(actionName, 24)}_$digest';
  }

  /// Model invocation token. Publication timestamps alone can coincide after
  /// a clock reset; include the full manifest's schemas, policies and executors.
  /// Historical rollback IDs remain MiniAppStore.versionOf's numeric stamps.
  static String actionVersionOf(MiniApp app) =>
      '${MiniAppStore.versionOf(app)}:${sha256.convert(utf8.encode(jsonEncode(app.toJson())))}';

  List<Map<String, dynamic>> toolDefinitions() {
    final bindings = <String, MiniAppToolBinding?>{};
    for (final app in store.apps) {
      for (final action in app.actions) {
        final name = toolNameFor(app.id, action.name);
        // An actual hash collision fails closed instead of routing to an app.
        bindings[name] = bindings.containsKey(name)
            ? null
            : MiniAppToolBinding(app, action);
      }
    }
    return [
      for (final entry in bindings.entries)
        if (entry.value != null)
          {
            'type': 'function',
            'function': {
              'name': entry.key,
              'description':
                  '${entry.value!.app.name}: ${entry.value!.action.description}',
              'parameters': entry.value!.action.inputSchema,
            },
          },
    ];
  }

  MiniAppToolBinding? resolveTool(String name) {
    MiniAppToolBinding? found;
    for (final app in store.apps) {
      for (final action in app.actions) {
        if (toolNameFor(app.id, action.name) != name) {
          continue;
        }
        if (found != null) {
          return null;
        }
        found = MiniAppToolBinding(app, action);
      }
    }
    return found;
  }

  Future<Map<String, dynamic>> execute(
    String appId,
    String actionName,
    Map<String, dynamic> arguments, {
    required MiniAppInvocation invocation,
    MiniApp? expectedApp,
  }) => _executeAction(
    appId,
    actionName,
    arguments,
    invocation: invocation,
    expectedApp: expectedApp,
  );

  Future<Map<String, dynamic>> _executeAction(
    String appId,
    String actionName,
    Map<String, dynamic> arguments, {
    required MiniAppInvocation invocation,
    MiniApp? expectedApp,
    _Request? parent,
    _SequenceRun? sequence,
    bool mutationLaneHeld = false,
  }) async {
    _Request? pending;
    try {
      if (_disposed) {
        _deny('runtime_closed', 'The mini app runtime is closed.');
      }
      await store.load();
      if (parent != null) {
        await _authorize(parent);
      }
      final app = _app(appId);
      if (expectedApp != null && !identical(app, expectedApp)) {
        _deny(
          'app_changed',
          'The mini app changed after its actions were read.',
        );
      }
      final action = app.actions.where((a) => a.name == actionName).firstOrNull;
      if (action == null) {
        _deny('action_not_found', 'This mini app action no longer exists.');
      }
      final args = MiniAppJsonSchema.arguments(action.inputSchema, arguments);
      final request = _Request(
        app,
        action,
        invocation,
        args,
        parent?.generation ?? store.generationFor(app.id),
      );
      request.permissionVersion = parent?.permissionVersion;
      pending = request;
      _activeRequests.add(request);
      final kind = action.executor['kind'];
      String? nativeHandler;
      List<Map<String, dynamic>> steps = [];
      Map<String, dynamic>? undo;
      if (kind == 'native') {
        nativeHandler = action.executor['handler'] as String;
        _nativeArguments(nativeHandler, args);
      } else if (kind == 'preset') {
        steps = [
          for (final step in action.executor['steps'] as List)
            {
              'handler': step['handler'],
              'args': _substitute(step['args'], args),
            },
        ];
        for (final step in steps) {
          _nativeArguments(
            step['handler'] as String,
            Map<String, dynamic>.from(step['args'] as Map),
          );
        }
      }
      await _authorize(request);
      if (nativeHandler != null) {
        final operations = await _selectDndOperations(request, [
          {'handler': nativeHandler, 'args': args},
        ]);
        nativeHandler = operations.single['handler'] as String;
        if (nativeHandler == 'device.root.dnd.set') {
          request.operations = operations;
        }
      } else if (kind == 'preset') {
        steps = await _selectDndOperations(request, steps);
      }
      if (request.extraRoot) await _authorize(request);
      if (kind == 'restore') {
        undo = await store.readHostData(appId, 'undo.json');
        _assertLive(request);
        steps = _undoSteps(undo);
        request.extraPermissions = {
          for (final step in steps)
            ...MiniAppDeviceService.permissionsFor(step['handler'] as String),
        };
        request.extraRoot = steps.any(
          (s) =>
              MiniAppDeviceService.requiresConfirmation(s['handler'] as String),
        );
        request.operations = [
          for (final step in steps.reversed)
            {
              'handler': step['handler'],
              'args': _restoreArguments(
                step['handler'] as String,
                Map<String, dynamic>.from(step['args'] as Map),
                Map<String, dynamic>.from(step['before'] as Map),
              ),
            },
        ];
        await _authorize(request);
      }
      if (kind == 'preset') {
        request.operations = steps;
      }
      if (invocation.source == MiniAppInvocationSource.background &&
          (action.isMutation || kind == 'preset' || kind == 'restore')) {
        _deny(
          'background_denied',
          'Background jobs can only read mini app state and device data.',
        );
      }
      if (kind == 'sequence') {
        final run = sequence ?? _SequenceRun();
        Future<Map<String, dynamic>> performSequence(bool held) async {
          await _authorize(request);
          return _sequence(request, run, mutationLaneHeld: held);
        }

        // Each referenced action performs its own normal approval. Holding the
        // outer mutation lane avoids interleaving without recursively queuing.
        if (action.isMutation && !mutationLaneHeld) {
          return await _serializeMutation(() => performSequence(true));
        }
        return await performSequence(mutationLaneHeld);
      }
      await _approval(request);
      await _authorize(request);
      _assertConsent(request);
      if (kind == 'state') {
        await store.updateState(
          appId,
          (data) async {
            await _authorize(request);
            _assertConsent(request);
            final template = Map<String, dynamic>.from(
              action.executor['patch'] as Map,
            );
            final patch = action.executor['expressions'] == true
                ? MiniAppExpressions.evaluatePatch(
                    template,
                    data: data,
                    arguments: args,
                    now: _now(),
                  )
                : Map<String, dynamic>.from(_substitute(template, args) as Map);
            _merge(data, patch);
          },
          expected: app,
          check: () {
            _assertLive(request);
            _assertConsent(request);
          },
        );
        final nextState = await state(appId, invocation: invocation);
        _publishState(appId, nextState);
        return {'status': 'applied', 'state': nextState};
      }
      Future<Map<String, dynamic>> perform() async {
        await _authorize(request);
        _assertConsent(request);
        if (kind == 'preset') {
          return _preset(request, steps);
        }
        if (kind == 'restore') {
          return _restore(request, steps, undo!);
        }
        Map<String, dynamic>? nativeOutcome;
        if (action.isMutation) {
          nativeOutcome = {'handler': nativeHandler, 'status': 'unknown'};
          request.stepResults.add(nativeOutcome);
          request.mutationAttempted = true;
        }
        final native = await _runNative(request, nativeHandler!, args);
        nativeOutcome?['status'] = native['status'] ?? 'failed';
        _assertLive(request);
        final nextState = await state(appId, invocation: invocation);
        if (invocation.source != MiniAppInvocationSource.background) {
          _publishState(appId, nextState);
        }
        return _result(native, nextState);
      }

      if ((action.isMutation || kind == 'restore') && !mutationLaneHeld) {
        return await _serializeMutation(perform);
      }
      return await perform();
    } on MiniAppException catch (e) {
      return _interrupted(pending, _failure(e));
    } catch (_) {
      return _interrupted(pending, {
        'status': 'failed',
        'code': 'execution_failed',
        'message': 'The mini app action failed.',
      });
    } finally {
      if (pending != null) {
        pending.active = false;
        _activeRequests.remove(pending);
      }
    }
  }

  Future<Map<String, dynamic>> _sequence(
    _Request request,
    _SequenceRun run, {
    required bool mutationLaneHeld,
  }) async {
    if (run.stack.contains(request.action.name) || run.stack.length >= 8) {
      _deny(
        'invalid_executor',
        'Sequence has a cycle or exceeds eight levels.',
      );
    }
    run.stack.add(request.action.name);
    final completed = <Map<String, dynamic>>[];
    final failed = <Map<String, dynamic>>[];
    final feedback = <Map<String, dynamic>>[];
    Map<String, dynamic> finish(Map<String, dynamic>? failure) {
      final restricted = const {
        'denied',
        'permission_required',
      }.contains(failure?['status']);
      final safeCompleted = restricted
          ? completed
                .map((step) => _withoutState(step) as Map<String, dynamic>)
                .toList()
          : completed;
      final safeFailed = restricted
          ? failed
                .map((step) => _withoutState(step) as Map<String, dynamic>)
                .toList()
          : failed;
      return {
        'status': failure == null
            ? 'applied'
            : const {
                'denied',
                'permission_required',
              }.contains(failure['status'])
            ? failure['status']
            : 'failed',
        if (failure?['code'] is String) 'code': failure!['code'],
        if (failure?['message'] is String) 'message': failure!['message'],
        'partial':
            failure != null &&
            (completed.isNotEmpty ||
                failed.any(
                  (step) => (step['result'] as Map)['partial'] == true,
                )),
        'completedSteps': safeCompleted,
        if (safeFailed.isNotEmpty) 'failedStep': safeFailed.first,
        'failedSteps': safeFailed,
        if (feedback.isNotEmpty) 'steps': feedback,
      };
    }

    try {
      final steps = request.action.executor['steps'] as List;
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i] as Map;
        Map<String, dynamic> result;
        try {
          await _authorize(request);
          if (++run.expanded > 32) {
            _deny(
              'invalid_executor',
              'Sequence exceeds 32 expanded action invocations.',
            );
          }
          final args = Map<String, dynamic>.from(
            _substitute(
                  step['arguments'] ?? const <String, dynamic>{},
                  request.arguments,
                )
                as Map,
          );
          result = await _executeAction(
            request.app.id,
            step['action'] as String,
            args,
            invocation: request.invocation,
            parent: request,
            sequence: run,
            mutationLaneHeld: mutationLaneHeld,
          );
          // A step may have completed just before a live source/grant changes.
          // Retain its outcome, then recheck before any subsequent step.
        } on MiniAppException catch (error) {
          result = _failure(error);
        } catch (_) {
          result = {
            'status': 'failed',
            'code': 'execution_failed',
            'message': 'The sequence step failed.',
          };
        }
        final evidence = <String, dynamic>{
          'index': i,
          'action': step['action'],
          'result': result,
        };
        if (result['steps'] is List) {
          feedback.addAll(
            (result['steps'] as List)
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .take(256 - feedback.length),
          );
        }
        if (result['status'] == 'applied') {
          completed.add(evidence);
        } else {
          failed.add(evidence);
        }
        try {
          await _authorize(request);
        } on MiniAppException catch (error) {
          return finish(_failure(error));
        }
        if (result['status'] != 'applied') {
          if (step['onFailure'] != 'continue' || !_canContinue(result)) {
            return finish(result);
          }
        }
      }
      return finish(
        failed.isEmpty
            ? null
            : Map<String, dynamic>.from(failed.first['result'] as Map),
      );
    } finally {
      run.stack.removeLast();
    }
  }

  static bool _canContinue(Map result) {
    if (!const {'failed', 'unsupported'}.contains(result['status']) ||
        result['code'] != null && result['code'] != 'execution_failed') {
      return false;
    }
    for (final key in ['steps', 'failedSteps']) {
      final entries = result[key];
      if (entries is List) {
        for (final entry in entries.whereType<Map>()) {
          final nested = entry['result'] is Map
              ? entry['result'] as Map
              : entry;
          if (!const {
                'applied',
                'failed',
                'unsupported',
                'conflict',
              }.contains(nested['status']) ||
              nested['code'] != null && nested['code'] != 'execution_failed' ||
              nested['status'] == 'failed' && !_canContinue(nested)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  static Object? _withoutState(Object? value) => value is Map
      ? {
          for (final entry in value.entries)
            if (entry.key != 'state')
              entry.key as String: _withoutState(entry.value),
        }
      : value is List
      ? value.map(_withoutState).toList()
      : value;

  Future<Map<String, dynamic>> state(
    String appId, {
    MiniAppInvocation? invocation,
  }) async {
    try {
      await store.load();
      final app = _app(appId);
      final generation = store.generationFor(appId);
      _checkSource(invocation);
      var grants = await permissions.granted(appId);
      _checkSource(invocation);
      if (!identical(store.byId(appId), app)) {
        _deny('app_changed', 'The mini app changed while reading state.');
      }
      if (invocation?.isAi == true && !grants.contains('actions.ai')) {
        _missing({'actions.ai'});
      }
      Map<String, dynamic> snapshot = {};
      if (grants.any((g) => g.startsWith('device.') && g.endsWith('.read'))) {
        snapshot = await device.snapshot();
        _checkSource(invocation);
        if (!identical(store.byId(appId), app)) {
          _deny('app_changed', 'The mini app changed while reading state.');
        }
        grants = await permissions.granted(appId);
        _checkSource(invocation);
        if (invocation?.isAi == true && !grants.contains('actions.ai')) {
          _missing({'actions.ai'});
        }
      }
      final data = await store.storageAll(appId);
      _checkSource(invocation);
      if (!identical(store.byId(appId), app)) {
        _deny('app_changed', 'The mini app changed while reading state.');
      }
      // The final read catches revocation during either device or storage I/O.
      grants = await permissions.granted(appId);
      _checkSource(invocation);
      if (!identical(store.byId(appId), app) ||
          generation != store.generationFor(appId)) {
        _deny('app_changed', 'The mini app changed while reading state.');
      }
      if (invocation?.isAi == true && !grants.contains('actions.ai')) {
        _missing({'actions.ai'});
      }
      return {
        'data': data,
        'device': _filteredDevice(snapshot, grants),
        'revision': store.dataRevisionFor(appId),
      };
    } on MiniAppException catch (e) {
      return _failure(e);
    } catch (_) {
      return {
        'status': 'failed',
        'code': 'state_failed',
        'message': 'The mini app state could not be read.',
      };
    }
  }

  StreamSubscription<Map<String, dynamic>> watch(
    String appId,
    void Function(Map<String, dynamic>) listener,
  ) {
    late StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        if (_disposed) {
          unawaited(controller.close());
          return;
        }
        _watchers.putIfAbsent(appId, () => {}).add(controller);
        _refresh(appId);
        unawaited(_syncDeviceWatch());
      },
      onCancel: () async {
        _watchers[appId]?.remove(controller);
        if (_watchers[appId]?.isEmpty == true) {
          _watchers.remove(appId);
        }
        await _syncDeviceWatch();
      },
    );
    return controller.stream.listen(listener);
  }

  void _storeChanged() {
    _cancelStaleRequests();
    for (final id in _watchers.keys.toList()) {
      _refresh(id);
    }
    unawaited(_syncDeviceWatch());
  }

  Future<void> _syncDeviceWatch() async {
    final epoch = ++_watchEpoch;
    var needed = false;
    for (final id in _watchers.keys.toList()) {
      if (store.byId(id) == null) {
        continue;
      }
      try {
        final grants = await permissions.granted(id);
        if (grants.any((g) => g.startsWith('device.') && g.endsWith('.read'))) {
          needed = true;
        }
      } catch (_) {}
    }
    if (epoch != _watchEpoch) {
      return;
    }
    if (_disposed || !needed) {
      final sub = _deviceSub;
      _deviceSub = null;
      await sub?.cancel();
    } else {
      _deviceSub ??= device.changes.listen(
        (snapshot) {
          for (final id in _watchers.keys.toList()) {
            _refresh(id, snapshot: snapshot);
          }
        },
        onError: (Object _) {
          for (final id in _watchers.keys.toList()) {
            _refresh(id);
          }
        },
      );
    }
  }

  void _refresh(String id, {Map<String, dynamic>? snapshot}) {
    if (_disposed) {
      return;
    }
    final epoch = (_refreshEpochs[id] ?? 0) + 1;
    _refreshEpochs[id] = epoch;
    unawaited(() async {
      Map<String, dynamic> value;
      if (snapshot == null) {
        value = await state(id);
      } else {
        try {
          final app = _app(id);
          final grants = await permissions.granted(id);
          final data = await store.storageAll(id);
          if (!identical(store.byId(id), app)) {
            return;
          }
          final liveGrants = await permissions.granted(id);
          value = {
            'data': data,
            'device': _filteredDevice(
              snapshot,
              grants.intersection(liveGrants),
            ),
            'revision': store.dataRevisionFor(id),
          };
        } catch (_) {
          return;
        }
      }
      if (_disposed || epoch != _refreshEpochs[id]) {
        return;
      }
      _publishState(id, value);
    }());
  }

  void _publishState(String id, Map<String, dynamic> value) {
    if (_disposed) {
      return;
    }
    _refreshEpochs[id] = (_refreshEpochs[id] ?? 0) + 1;
    _changes.add((appId: id, state: value));
    for (final controller
        in _watchers[id]?.toList() ??
            <StreamController<Map<String, dynamic>>>[]) {
      if (!controller.isClosed) {
        controller.add(value);
      }
    }
  }

  Future<void> _authorize(_Request request) async {
    _assertLive(request, checkGrants: false);
    final grants = await permissions.granted(request.app.id);
    _assertLive(request, checkGrants: false);
    final required = {
      ...request.action.permissions,
      ...request.extraPermissions,
      if (request.invocation.isAi) 'actions.ai',
    };
    final missing = required.difference(grants);
    if (missing.isNotEmpty) {
      _missing(missing);
    }
    final version = permissions.versionFor(request.app.id);
    if (request.permissionVersion != null &&
        request.permissionVersion != version) {
      throw const MiniAppException(
        'permission_required',
        'Mini app permissions changed while the action was pending.',
      );
    }
    request.permissionVersion ??= version;
  }

  /// Select once before consent. Revocation afterwards cancels the request;
  /// it must never silently switch to a different operation or approval policy.
  Future<List<Map<String, dynamic>>> _selectDndOperations(
    _Request request,
    List<Map<String, dynamic>> operations,
  ) async {
    if (!operations.any((op) => op['handler'] == 'device.audio.dnd.set')) {
      return operations;
    }
    final grants = await permissions.granted(request.app.id);
    _assertLive(request);
    if (!grants.contains('device.root.dnd')) return operations;
    request.extraPermissions.add('device.root.dnd');
    request.extraRoot = true;
    return [
      for (final operation in operations)
        if (operation['handler'] == 'device.audio.dnd.set')
          {...operation, 'handler': 'device.root.dnd.set'}
        else
          operation,
    ];
  }

  void _assertLive(_Request request, {bool checkGrants = true}) {
    if (request.owner?.isCancelled() == true || request.lifetimeCancelled) {
      _deny('invocation_cancelled', 'This invocation was cancelled.');
    }
    _checkSource(request.invocation);
    if (_disposed ||
        !identical(store.byId(request.app.id), request.app) ||
        store.generationFor(request.app.id) != request.generation) {
      _deny(
        'app_changed',
        'The mini app changed while the action was pending.',
      );
    }
    if (checkGrants &&
        permissions.versionFor(request.app.id) != request.permissionVersion) {
      throw const MiniAppException(
        'permission_required',
        'Mini app permissions changed while the action was pending.',
      );
    }
  }

  static void _checkSource(MiniAppInvocation? invocation) {
    if (invocation?.source == MiniAppInvocationSource.wifi) {
      _deny(
        'wifi_denied',
        'New mini app capabilities are unavailable over Wi-Fi.',
      );
    }
    if (invocation?.isAllowed?.call() == false) {
      _deny('invocation_cancelled', 'This invocation is no longer allowed.');
    }
  }

  bool _needsApproval(_Request request) =>
      request.action.requiresConfirmation ||
      request.extraRoot ||
      request.invocation.forceConfirmation && request.action.isMutation ||
      request.invocation.isAi && request.action.isMutation;

  Future<void> _approval(_Request request) async {
    if (!_needsApproval(request)) {
      return;
    }
    if (request.invocation.source == MiniAppInvocationSource.background) {
      _deny(
        'background_denied',
        'Background actions cannot request confirmation.',
      );
    }
    if (request.invocation.fullTrust?.call() == true) {
      return;
    }
    final approve = request.invocation.approve;
    if (approve == null) {
      throw const MiniAppException(
        'permission_required',
        'This action needs explicit confirmation.',
      );
    }
    final effectiveAction =
        request.extraRoot || request.extraPermissions.isNotEmpty
        ? MiniAppAction(
            name: request.action.name,
            description: request.action.description,
            inputSchema: request.action.inputSchema,
            permissions: {
              ...request.action.permissions,
              ...request.extraPermissions,
            },
            danger: request.extraRoot
                ? MiniAppDanger.root
                : request.action.danger,
            executor: request.action.executor,
          )
        : request.action;
    final presented =
        jsonDecode(
              jsonEncode({
                ...request.arguments,
                // Empty native operation lists must also override user input.
                if (const {
                  'native',
                  'preset',
                  'restore',
                }.contains(request.action.executor['kind']))
                  'operations': request.operations,
              }),
            )
            as Map<String, dynamic>;
    final accepted = await Future.any<bool>([
      approve(request.app, effectiveAction, presented),
      request.cancelled.then((_) => false),
    ]);
    _assertLive(request);
    if (!accepted) {
      _deny('approval_denied', 'The action was declined.');
    }
    request.approved = true;
  }

  void _assertConsent(_Request request) {
    _assertLive(request);
    if (_needsApproval(request) &&
        !request.approved &&
        request.invocation.fullTrust?.call() != true) {
      throw const MiniAppException(
        'permission_required',
        'This action needs explicit confirmation.',
      );
    }
  }

  Future<Map<String, dynamic>> _preset(
    _Request request,
    List<Map<String, dynamic>> steps,
  ) async {
    final record = <String, dynamic>{
      'version': 1,
      'steps': <Map<String, dynamic>>[],
    };
    final results = request.stepResults;
    var partial = false;
    // Preserve a pending restore instead of silently losing an earlier preset.
    final previous = await store.readHostData(request.app.id, 'undo.json');
    await _authorize(request);
    if (_undoSteps(previous).isNotEmpty) {
      _deny(
        'restore_pending',
        'Restore or resolve the previous preset before applying another.',
      );
    }
    for (final step in steps) {
      final handler = step['handler'] as String;
      final args = Map<String, dynamic>.from(step['args'] as Map);
      final before = await device.snapshot();
      await _authorize(request);
      _assertConsent(request);
      final fields = _restoreFields(handler, args, before);
      var restorable = fields != null;
      if (fields != null) {
        try {
          _nativeArguments(handler, _restoreArguments(handler, args, fields));
        } on MiniAppException {
          restorable = false;
        }
      }
      if (!restorable) {
        results.add({
          'handler': handler,
          'status': 'unsupported',
          'message':
              'The previous setting is unavailable; no change was attempted.',
        });
        partial = true;
        continue;
      }
      final outcome = <String, dynamic>{
        'handler': handler,
        'status': 'unknown',
      };
      results.add(outcome);
      request.mutationAttempted = true;
      final native = await _runNative(request, handler, args);
      final status = native['status'] as String? ?? 'failed';
      outcome.addAll({
        'status': status,
        if (native['message'] is String) 'message': native['message'],
      });
      // Persist an attempted operation before another await. A timeout may
      // have changed Android; preserve only verified readback as restorable.
      final after = await device.snapshot();
      final applied = {
        for (final path in fields!.keys) path: _path(after, path),
      };
      final valid = applied.values.every((v) => v != null);
      final changed =
          valid &&
          fields.keys.any((path) => !_equal(fields[path], applied[path]));
      // A user may change DND while the root manager is asking for access.
      // A definite refusal cannot own that change, even if the modes coincide.
      // An interrupted command owns only verified readback of its requested mode.
      final isDnd =
          handler == 'device.audio.dnd.set' || handler == 'device.root.dnd.set';
      final owned =
          !isDnd ||
          const {'applied', 'unknown_after_timeout'}.contains(status) &&
              applied['audio.dnd'] == args['mode'];
      if (changed && owned) {
        (record['steps'] as List).add({
          'handler': handler,
          'args': args,
          'before': fields,
          'applied': applied,
        });
        await _saveUndo(request, record);
      }
      if (status != 'applied' || !valid) {
        partial = true;
      }
      await _authorize(request);
      _assertConsent(request);
    }
    return {
      'status': partial ? 'failed' : 'applied',
      'partial': partial,
      'steps': results,
      'conflicts': <String>[],
      'state': await state(request.app.id, invocation: request.invocation),
    };
  }

  Future<Map<String, dynamic>> _restore(
    _Request request,
    List<Map<String, dynamic>> steps,
    Map<String, dynamic> record,
  ) async {
    final remaining = List<Map<String, dynamic>>.from(steps);
    final results = request.stepResults;
    final conflicts = request.stepConflicts;
    var partial = false;
    for (final step in steps.reversed) {
      final handler = step['handler'] as String;
      final actual = await device.snapshot();
      await _authorize(request);
      _assertConsent(request);
      final applied = Map<String, dynamic>.from(step['applied'] as Map);
      final before = Map<String, dynamic>.from(step['before'] as Map);
      final different = applied.keys
          .where((path) => !_equal(_path(actual, path), applied[path]))
          .toList();
      if (different.isNotEmpty) {
        conflicts.addAll(different);
        results.add({
          'handler': handler,
          'status': 'conflict',
          'message': 'The setting changed after this preset and was preserved.',
        });
        remaining.remove(step);
        partial = true;
        await _saveUndo(request, {'version': 1, 'steps': remaining});
        continue;
      }
      final args = _restoreArguments(
        handler,
        Map<String, dynamic>.from(step['args'] as Map),
        before,
      );
      _nativeArguments(handler, args);
      _assertConsent(request);
      final outcome = <String, dynamic>{
        'handler': handler,
        'status': 'unknown',
      };
      results.add(outcome);
      request.mutationAttempted = true;
      final native = await _runNative(request, handler, args);
      final status = native['status'] as String? ?? 'failed';
      outcome['status'] = status;
      final after = await device.snapshot();
      final verified = before.keys.every(
        (path) => _equal(_path(after, path), before[path]),
      );
      if (verified) {
        remaining.remove(step);
      } else {
        partial = true;
      }
      if (status != 'applied') {
        partial = true;
      }
      outcome['status'] = verified && status == 'applied'
          ? 'applied'
          : status == 'applied'
          ? 'failed'
          : status;
      await _saveUndo(request, {'version': 1, 'steps': remaining});
      await _authorize(request);
      _assertConsent(request);
    }
    return {
      'status': partial ? 'failed' : 'applied',
      'partial': partial,
      'steps': results,
      'conflicts': conflicts,
      'state': await state(request.app.id, invocation: request.invocation),
    };
  }

  Future<void> _saveUndo(_Request request, Map<String, dynamic> record) async {
    // Preserve verified changes even if permission was revoked after execution,
    // but never attach old undo records to a replaced or deleted application.
    if (!identical(store.byId(request.app.id), request.app) ||
        store.generationFor(request.app.id) != request.generation) {
      _deny('app_changed', 'The mini app changed during the preset.');
    }
    await store.updateHostData(request.app.id, 'undo.json', (map) {
      map.clear();
      map.addAll(record);
    });
  }

  static List<Map<String, dynamic>> _undoSteps(Map<String, dynamic> record) {
    final raw = record['steps'];
    if (raw == null) {
      return [];
    }
    if (record['version'] != 1 || raw is! List || raw.length > 8) {
      _deny('invalid_undo', 'The host restore record is invalid.');
    }
    final steps = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map ||
          !reversibleHandlers.contains(item['handler']) ||
          item['args'] is! Map ||
          item['before'] is! Map ||
          item['applied'] is! Map) {
        _deny('invalid_undo', 'The host restore record is invalid.');
      }
      steps.add(Map<String, dynamic>.from(item));
    }
    return steps;
  }

  static Map<String, dynamic>? _restoreFields(
    String handler,
    Map<String, dynamic> args,
    Map<String, dynamic> state,
  ) {
    final paths = switch (handler) {
      'device.screen.brightness.set' => [
        'screen.brightness',
        if (args.containsKey('mode')) 'screen.brightnessMode',
      ],
      'device.screen.timeout.set' => ['screen.timeoutMs'],
      'device.audio.volume.set' => ['audio.volumes.${args['stream']}.value'],
      'device.audio.dnd.set' || 'device.root.dnd.set' => ['audio.dnd'],
      'device.flashlight.set' => ['flashlight.enabled'],
      'device.root.power_save.set' => ['battery.powerSave'],
      'device.root.wifi.set' => ['connectivity.wifiEnabled'],
      'device.root.bluetooth.set' => ['connectivity.bluetoothEnabled'],
      'device.root.data.set' => ['connectivity.mobileDataEnabled'],
      'device.root.airplane.set' => ['connectivity.airplaneMode'],
      _ => <String>[],
    };
    final fields = {for (final path in paths) path: _path(state, path)};
    if (fields.isEmpty || fields.values.any((v) => v == null)) {
      return null;
    }
    return fields;
  }

  static Map<String, dynamic> _restoreArguments(
    String handler,
    Map<String, dynamic> original,
    Map<String, dynamic> before,
  ) => switch (handler) {
    'device.screen.brightness.set' => {
      'value': before['screen.brightness'],
      if (before.containsKey('screen.brightnessMode'))
        'mode': before['screen.brightnessMode'],
    },
    'device.screen.timeout.set' => {'milliseconds': before['screen.timeoutMs']},
    'device.audio.volume.set' => {
      'stream': original['stream'],
      'value': before['audio.volumes.${original['stream']}.value'],
    },
    'device.audio.dnd.set' ||
    'device.root.dnd.set' => {'mode': before['audio.dnd']},
    _ => {'enabled': before.values.single},
  };

  static Map<String, dynamic> _filteredDevice(
    Map<String, dynamic> snapshot,
    Set<String> grants,
  ) => {
    for (final group in [
      'battery',
      'screen',
      'audio',
      'connectivity',
      'flashlight',
      'system',
    ])
      if (grants.contains('device.$group.read') && snapshot.containsKey(group))
        group: snapshot[group],
  };

  static Object? _path(Map<String, dynamic> root, String path) {
    Object? value = root;
    for (final part in path.split('.')) {
      if (value is! Map) {
        return null;
      }
      value = value[part];
    }
    return value;
  }

  static Object? _substitute(Object? template, Map<String, dynamic> args) {
    if (template is Map) {
      if (template.length == 1 && template[r'$arg'] is String) {
        final name = template[r'$arg'];
        if (!args.containsKey(name)) {
          throw MiniAppException(
            'invalid_arguments',
            'Missing substituted argument "$name".',
          );
        }
        return args[name];
      }
      return {
        for (final e in template.entries)
          e.key as String: _substitute(e.value, args),
      };
    }
    if (template is List) {
      return template.map((v) => _substitute(v, args)).toList();
    }
    return template;
  }

  static void _merge(Map<String, dynamic> target, Map<String, dynamic> patch) {
    for (final entry in patch.entries) {
      if (entry.value is Map && target[entry.key] is Map<String, dynamic>) {
        _merge(
          target[entry.key] as Map<String, dynamic>,
          Map<String, dynamic>.from(entry.value as Map),
        );
      } else {
        target[entry.key] = entry.value;
      }
    }
  }

  static void _nativeArguments(String handler, Map<String, dynamic> args) {
    final schema = MiniAppDeviceService.inputSchemaFor(handler);
    if (schema == null) {
      _deny('unknown_handler', 'Unknown native device handler.');
    }
    MiniAppJsonSchema.validate(schema, args);
  }

  static Future<T> _serializeMutation<T>(Future<T> Function() perform) {
    final next = _mutationTail.catchError((Object _) {}).then((_) => perform());
    _mutationTail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  MiniApp _app(String id) {
    final app = store.byId(id);
    if (app == null) {
      _deny('not_found', 'This mini app is no longer installed.');
    }
    return app;
  }

  bool _requestCancelled(_Request request) =>
      _disposed ||
      request.lifetimeCancelled ||
      request.owner?.isCancelled() == true ||
      request.invocation.isAllowed?.call() == false ||
      !identical(store.byId(request.app.id), request.app) ||
      store.generationFor(request.app.id) != request.generation ||
      request.permissionVersion != null &&
          permissions.versionFor(request.app.id) != request.permissionVersion;

  void _cancelStaleRequests([String? id]) {
    for (final request in _activeRequests.toList()) {
      if ((id == null || request.app.id == id) && _requestCancelled(request)) {
        request.cancel();
      }
    }
  }

  Future<Map<String, dynamic>> _runNative(
    _Request request,
    String handler,
    Map<String, dynamic> args,
  ) async {
    _assertConsent(request);
    final cancellation = ToolCallCancellation(
      isCancelled: () => _requestCancelled(request),
      cancelled: request.cancelled,
    );
    return cancellation.run(() => device.execute(handler, args));
  }

  static Map<String, dynamic> _result(
    Map<String, dynamic> native,
    Map<String, dynamic> state,
  ) => {
    'status': native['status'] ?? 'failed',
    if (native['message'] is String) 'message': native['message'],
    'state': state,
  };
  static Map<String, dynamic> _failure(MiniAppException e) => {
    'status': e.code == 'permission_required'
        ? 'permission_required'
        : const {
            'invalid_arguments',
            'invalid_expression',
            'invalid_schema',
            'storage_full',
          }.contains(e.code)
        ? 'failed'
        : 'denied',
    'code': e.code,
    'message': e.message,
  };
  static Map<String, dynamic> _interrupted(
    _Request? request,
    Map<String, dynamic> failure,
  ) => {
    ...failure,
    // Keep bounded operation evidence without exposing device state after a
    // source, lifetime or permission check interrupts a multi-step change.
    if (request?.mutationAttempted == true) ...{
      'partial': true,
      'steps': request!.stepResults,
      'conflicts': request.stepConflicts,
    },
  };
  static Never _deny(String code, String message) =>
      throw MiniAppException(code, message);
  static Never _missing(Set<String> capabilities) => throw MiniAppException(
    'permission_required',
    'Required mini app grants: ${(capabilities.toList()..sort()).join(', ')}.',
  );
  static bool _equal(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final request in _activeRequests.toList()) {
      request.cancel();
    }
    ++_watchEpoch;
    store.removeListener(_storeChanged);
    await _storageSub.cancel();
    await _permissionSub.cancel();
    await _lifecycleSub.cancel();
    await _deviceSub?.cancel();
    _deviceSub = null;
    final controllers = [for (final set in _watchers.values) ...set];
    _watchers.clear();
    for (final controller in controllers) {
      unawaited(controller.close());
    }
    permissions.dispose();
    unawaited(_changes.close());
  }
}

class _SequenceRun {
  final List<String> stack = [];
  int expanded = 0;
}

class _Request {
  _Request(
    this.app,
    this.action,
    this.invocation,
    this.arguments,
    this.generation,
  ) : owner = ToolCallCancellation.current {
    invocation.cancelled?.then((_) {
      if (active) {
        lifetimeCancelled = true;
        cancel();
      }
    });
    owner?.cancelled.then((_) {
      if (active) {
        cancel();
      }
    });
  }
  final MiniApp app;
  final MiniAppAction action;
  final MiniAppInvocation invocation;
  final Map<String, dynamic> arguments;
  final int generation;
  final ToolCallCancellation? owner;
  final Completer<void> _cancelled = Completer<void>();
  Future<void> get cancelled => _cancelled.future;
  bool lifetimeCancelled = false;
  bool active = true;
  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  int? permissionVersion;
  Set<String> extraPermissions = {};
  List<Map<String, dynamic>> operations = [];
  final List<Map<String, dynamic>> stepResults = [];
  final List<String> stepConflicts = [];
  bool mutationAttempted = false;
  bool extraRoot = false;
  bool approved = false;
}
