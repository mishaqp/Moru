import 'dart:convert';

import '../../../core/services/api/tool_call_cancellation.dart';
import '../../../core/services/mini_apps/mini_app_jobs.dart';
import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../mini_apps/mini_app_specification.dart';

class _ToolFailure implements Exception {
  const _ToolFailure(this.error, this.message);

  final String error;
  final String message;
}

/// The `mini_apps` local tool: the chat reads and changes the data of the
/// user's mini apps, e.g. "I drank a glass of water", without opening them.
class MiniAppDataTool {
  const MiniAppDataTool({
    required this.store,
    this.jobs,
    this.serverStatus,
    this.runtime,
    this.invocation,
  });

  static const String toolName = 'mini_apps';

  static const String actionSpec = 'spec';
  static const String actionList = 'list';
  static const String actionRead = 'read';
  static const String actionState = 'state';
  static const String actionWrite = 'write';
  static const String actionRemove = 'remove';
  static const String actionErrors = 'errors';
  static const String actionVersions = 'versions';
  static const String actionRollback = 'rollback';
  static const String actionJobs = 'jobs';
  static const String actionRunJob = 'run_job';
  static const String actionServer = 'server';
  static const String actionDeleteJob = 'delete_job';
  static const String actionDelete = 'delete';

  static const List<String> actions = [
    actionSpec,
    actionList,
    actionRead,
    actionState,
    actionWrite,
    actionRemove,
    actionErrors,
    actionVersions,
    actionRollback,
    actionJobs,
    actionRunJob,
    actionServer,
    actionDeleteJob,
    actionDelete,
  ];

  /// Deleting an app or a job goes through the user's approval.
  static bool requiresApproval(Map<String, dynamic> args) {
    final action = actionOf(args);
    return action == actionDelete || action == actionDeleteJob;
  }

  /// Larger reads return only the keys, so one app cannot flood the context.
  static const int maxReadChars = 20000;

  /// Bound model-facing snapshots; native panels and app subscriptions keep
  /// their full state. Action results embed the same snapshot under `state`.
  static Map<String, dynamic> stateForModel(Map<String, dynamic> result) {
    final bounded = Map<String, dynamic>.of(result);
    final state = bounded['state'];
    if (state is Map) {
      bounded['state'] = stateForModel(Map<String, dynamic>.from(state));
    }
    Map<String, dynamic> boundEvidence(Map entry) {
      final evidence = Map<String, dynamic>.from(entry);
      final child = evidence['result'];
      if (child is Map) {
        evidence['result'] = stateForModel(Map<String, dynamic>.from(child));
      }
      return evidence;
    }

    for (final key in ['completedSteps', 'failedSteps']) {
      final steps = bounded[key];
      if (steps is List) {
        bounded[key] = [
          for (final entry in steps)
            if (entry is Map) boundEvidence(entry) else entry,
        ];
      }
    }
    final failed = bounded['failedStep'];
    if (failed is Map) bounded['failedStep'] = boundEvidence(failed);
    final data = bounded['data'];
    if (data is Map && jsonEncode(data).length > maxReadChars) {
      bounded.remove('data');
      bounded['data_omitted'] = true;
      bounded['data_key_count'] = data.length;
      bounded['data_keys'] = [
        for (final key in data.keys.take(100))
          key.toString().length > 128
              ? '${key.toString().substring(0, 128)}…'
              : key.toString(),
      ];
      bounded['note'] =
          'The app data is large. Read a specific key with mini_apps.read. '
          'This preview contains at most 100 keys, each at most 128 characters.';
    }
    return bounded;
  }

  final MiniAppStore store;
  final MiniAppRuntime? runtime;
  final MiniAppInvocation? invocation;

  /// Background jobs; `jobs` and `run_job` are unavailable without them.
  final MiniAppJobs? jobs;

  /// State and output of an app's server (MiniAppServers.status).
  final Map<String, Object?> Function(String appId)? serverStatus;

  static String actionOf(Map<String, dynamic> args) =>
      (args['action'] ?? '').toString().trim().toLowerCase();

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Read and change the data of the user\'s Moru mini apps (native panels and web '
          'apps such as a water tracker or a shopping list) without opening '
          'them. Call "spec" before authoring native panels: complete manifest, screen, '
          'executors, expressions, bindings, permissions and publishable Focus example; no app_id needed. '
          '"state" reads current app and device state, whether open or closed. '
          'Declared actions are separate ma_ tools and share the app buttons\' executor, '
          'capabilities and confirmations. Version-2 data writes/removes also require '
          'the app\'s granted actions.ai capability. Never claim a setting was applied when the '
          'result only says opened_settings, unsupported or unknown_after_timeout. '
          'Call "list" first: it shows each app\'s id, what it does, '
          'how it stores its data and its keys. Keep the stored format '
          'exactly as the app expects; read a key before writing it. An open '
          'app redraws when its data changes. To fix an app, read its '
          '"errors": the journal of script errors, console errors and failed '
          'moru.* calls the current version hit while the user used it '
          '(republishing clears it). "versions" lists the earlier code Moru '
          'kept (the last 5); "rollback" puts one back without touching the '
          'data. "jobs" lists the app\'s background jobs (moru.jobs) with '
          'their next and last runs; "run_job" starts one now to test it, '
          'then read "jobs" and "errors" about 30 s later. "server" shows '
          'whether the app\'s server runs and its latest output. "delete_job" '
          'removes a background job and "delete" removes a whole app with its '
          'data, versions and jobs; both ask the user first.',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions,
            'description':
                'spec: native panel authoring specification and complete examples (no app_id). '
                'list: installed apps. read: one key of app_id, or all its '
                'stored data without key. state: current app/device snapshot of app_id. '
                'write: set key of app_id to value. '
                'remove: delete key of app_id. errors: error journal of '
                'app_id, oldest first; clear: true empties it after reading. '
                'versions: earlier versions of app_id. rollback: restore '
                'version of app_id. jobs: background jobs of app_id. '
                'run_job: run job of app_id now. server: state and output '
                'of the server of app_id. delete_job: remove job of app_id. '
                'delete: remove app_id with all its data.',
          },
          'app_id': {'type': 'string', 'description': 'App id from "list".'},
          'key': {'type': 'string', 'description': 'Storage key.'},
          'value': {'description': 'JSON value to store under key.'},
          'clear': {
            'type': 'boolean',
            'description': 'errors: empty the journal after reading it.',
          },
          'version': {
            'type': 'string',
            'description': 'rollback: a version from "versions".',
          },
          'job': {
            'type': 'string',
            'description': 'run_job, delete_job: a job id from "jobs".',
          },
        },
        'required': ['action'],
      },
    },
  };

  Future<String> execute(Map<String, dynamic> args) async {
    try {
      if (actionOf(args) == actionSpec) {
        return jsonEncode({
          'ok': true,
          'specification': MiniAppSpecification.document,
        });
      }
      await store.load();
      final action = actionOf(args);
      final Map<String, dynamic> result;
      switch (action) {
        case actionList:
          result = {'apps': await _list()};
        case actionRead:
          result = await _read(args);
        case actionState:
          final app = _app(args);
          final executor = runtime;
          if (executor == null) {
            throw const _ToolFailure(
              'unavailable',
              'App state is unavailable here.',
            );
          }
          return jsonEncode(
            stateForModel(await executor.state(app.id, invocation: invocation)),
          );
        case actionWrite:
          final app = _app(args);
          final key = _key(args);
          if (!args.containsKey('value')) {
            throw const _ToolFailure('missing_value', '"value" is required.');
          }
          await _changeData(app, key, value: args['value']);
          result = {'written': key};
        case actionRemove:
          final app = _app(args);
          final key = _key(args);
          await _changeData(app, key, remove: true);
          result = {'removed': key};
        case actionErrors:
          final app = _app(args);
          final entries = await store.readErrors(app.id);
          if (args['clear'] == true) await store.clearErrors(app.id);
          result = {
            'errors': [
              for (final entry in entries)
                {
                  'at': entry.at.toIso8601String(),
                  'message': entry.message,
                  if (entry.count > 1) 'count': entry.count,
                },
            ],
            if (args['clear'] == true) 'cleared': true,
          };
        case actionVersions:
          final app = _app(args);
          result = {
            'current': app.updatedAt.toIso8601String(),
            'versions': [
              for (final version in await store.versions(app.id))
                {
                  'version': MiniAppStore.versionOf(version),
                  'published': version.updatedAt.toIso8601String(),
                  if (version.name != app.name) 'name': version.name,
                },
            ],
          };
        case actionRollback:
          final app = _app(args);
          final version = '${args['version'] ?? ''}'.trim();
          if (version.isEmpty) {
            throw const _ToolFailure(
              'missing_version',
              '"version" is required. Call "versions" to get them.',
            );
          }
          final restored = await store.rollback(app.id, version);
          result = {
            'restored': version,
            'published': restored.updatedAt.toIso8601String(),
          };
        case actionJobs:
          final app = _app(args);
          result = {
            'jobs': [
              for (final job in await _jobs().list(app.id))
                {
                  ...job.toJson()..remove('lastRun'),
                  'runs': [for (final run in job.runs) run.toJson()],
                },
            ],
          };
        case actionServer:
          final app = _app(args);
          final status = serverStatus;
          if (status == null) {
            throw const _ToolFailure(
              'unavailable',
              'App servers are not available here.',
            );
          }
          result = {'command': app.serverCommand, ...status(app.id)};
        case actionRunJob:
          final app = _app(args);
          final job = '${args['job'] ?? ''}'.trim();
          await _jobs().runNow(app.id, job);
          result = {
            'started': job,
            'note':
                'The job runs in the background for up to 30 s. Read "jobs" '
                'for its result and "errors" for what went wrong.',
          };
        case actionDeleteJob:
          final app = _app(args);
          final job = '${args['job'] ?? ''}'.trim();
          final jobs = _jobs();
          if (!(await store.readJobs(app.id)).containsKey(job)) {
            throw _ToolFailure(
              'not_found',
              'No job "$job". Call "jobs" to get the ids.',
            );
          }
          await jobs.remove(app.id, job);
          result = {'deleted_job': job};
        case actionDelete:
          final app = _app(args);
          await store.delete(app.id);
          result = {'deleted': app.id};
        default:
          throw _ToolFailure(
            'invalid_action',
            'Unknown action "$action". Use one of: ${actions.join(', ')}.',
          );
      }
      return jsonEncode({'ok': true, ...result});
    } on _ToolFailure catch (e) {
      return jsonEncode({'ok': false, 'error': e.error, 'message': e.message});
    } on MiniAppException catch (e) {
      return jsonEncode({'ok': false, 'error': e.code, 'message': e.message});
    }
  }

  Future<List<Map<String, dynamic>>> _list() async => [
    for (final app in store.apps)
      {
        'id': app.id,
        'name': app.name,
        if (app.description.isNotEmpty) 'description': app.description,
        if (app.dataHelp.isNotEmpty) 'data': app.dataHelp,
        'keys': await store.storageKeys(app.id),
        if (app.formatVersion >= 2) ...{
          'engine': app.uiEngine.name,
          'permissions': app.permissions.toList()..sort(),
          'actions': [
            for (final action in app.actions)
              {
                'name': action.name,
                'description': action.description,
                'tool': MiniAppRuntime.toolNameFor(app.id, action.name),
              },
          ],
        },
      },
  ];

  Future<void> _changeData(
    MiniApp app,
    String key, {
    Object? value,
    bool remove = false,
  }) async {
    if (app.formatVersion < 2) {
      if (remove) {
        await store.storageRemove(app.id, key);
      } else {
        await store.storageSet(app.id, key, value);
      }
      return;
    }
    final executor = runtime;
    final request = invocation;
    if (executor == null ||
        !identical(executor.store, store) ||
        request == null) {
      throw const _ToolFailure(
        'permission_required',
        'Changing this app requires a current AI invocation and actions.ai.',
      );
    }
    if (!request.isAi) {
      throw const _ToolFailure(
        'invocation_denied',
        'This data tool is available only to the current chat or ACP invocation.',
      );
    }
    if (key.length > MiniAppStore.maxKeyLength) {
      throw const _ToolFailure(
        'invalid_key',
        'Keys must be 1-${MiniAppStore.maxKeyLength} characters.',
      );
    }
    final generation = store.generationFor(app.id);
    final grantVersion = executor.permissions.versionFor(app.id);
    final owner = ToolCallCancellation.current;
    var lifetimeCancelled = false;
    request.cancelled?.then((_) => lifetimeCancelled = true);
    void check() {
      if (lifetimeCancelled ||
          owner?.isCancelled() == true ||
          request.isAllowed?.call() == false) {
        throw const MiniAppException(
          'invocation_cancelled',
          'This invocation is no longer allowed.',
        );
      }
      if (!identical(store.byId(app.id), app) ||
          store.generationFor(app.id) != generation) {
        throw const MiniAppException(
          'app_changed',
          'The mini app changed while the write was pending.',
        );
      }
      if (executor.permissions.versionFor(app.id) != grantVersion) {
        throw const MiniAppException(
          'permission_required',
          'Mini app permissions changed while the write was pending.',
        );
      }
    }

    check();
    final grants = await executor.permissions.granted(app.id);
    check();
    if (!grants.contains('actions.ai')) {
      throw const _ToolFailure(
        'permission_required',
        'Grant actions.ai on the app screen before the AI can change its data.',
      );
    }
    await store.updateState(
      app.id,
      (data) {
        if (remove) {
          data.remove(key);
        } else {
          data[key] = value;
        }
      },
      expected: app,
      check: check,
    );
  }

  Future<Map<String, dynamic>> _read(Map<String, dynamic> args) async {
    final app = _app(args);
    final key = args['key'];
    if (key is String && key.isNotEmpty) {
      return {'key': key, 'value': await store.storageGet(app.id, key)};
    }
    final all = await store.storageAll(app.id);
    if (jsonEncode(all).length > maxReadChars) {
      return {
        'keys': all.keys.toList(),
        'note': 'The data is large; read one key at a time.',
      };
    }
    return {'data': all};
  }

  MiniAppJobs _jobs() {
    final jobs = this.jobs;
    if (jobs == null) {
      throw const _ToolFailure(
        'unavailable',
        'Background jobs are not available here.',
      );
    }
    return jobs;
  }

  MiniApp _app(Map<String, dynamic> args) {
    final id = '${args['app_id'] ?? ''}'.trim();
    final app = store.byId(id);
    if (app == null) {
      throw _ToolFailure(
        'not_found',
        'No mini app "$id". Call "list" to get the ids.',
      );
    }
    return app;
  }

  static String _key(Map<String, dynamic> args) {
    final key = args['key'];
    if (key is! String || key.isEmpty) {
      throw const _ToolFailure('missing_key', '"key" is required.');
    }
    return key;
  }
}
