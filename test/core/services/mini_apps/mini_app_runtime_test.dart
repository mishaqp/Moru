import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class FakeDevice extends MiniAppDeviceService {
  FakeDevice() {
    events = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        listeners++;
        if (!attached.isCompleted) {
          attached.complete();
        }
      },
      onCancel: () => listeners--,
    );
  }
  late StreamController<Map<String, dynamic>> events;
  int listeners = 0;
  final attached = Completer<void>();
  final calls = <String>[];
  String? fail;
  String? unsupported;
  String unsupportedStatus = 'unsupported';
  Completer<void>? pendingSnapshot;
  final snapshotEntered = Completer<void>();
  Completer<void>? pendingNative;
  Future<void> Function()? afterMutation;
  final nativeEntered = Completer<void>();
  Map<String, dynamic> current = {
    'battery': {'level': 45, 'powerSave': false},
    'screen': {
      'brightness': 120,
      'brightnessMode': 'automatic',
      'timeoutMs': 60000,
    },
    'audio': {
      'dnd': 'all',
      'volumes': {
        'music': {'value': 6, 'max': 15},
      },
    },
    'connectivity': {'wifiEnabled': true},
  };
  @override
  Stream<Map<String, dynamic>> get changes => events.stream;
  @override
  Future<Map<String, dynamic>> snapshot() async {
    if (pendingSnapshot != null && !snapshotEntered.isCompleted) {
      snapshotEntered.complete();
    }
    await pendingSnapshot?.future;
    return jsonDecode(jsonEncode(current)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    calls.add(handler);
    if (pendingNative != null) {
      final cancellation = ToolCallCancellation.current;
      if (!nativeEntered.isCompleted) {
        nativeEntered.complete();
      }
      await Future.any<void>([
        pendingNative!.future,
        if (cancellation != null) cancellation.cancelled,
      ]);
      if (cancellation?.isCancelled() == true) {
        return {'status': 'denied'};
      }
    }
    if (handler == fail) {
      return {
        'status': 'permission_required',
        'message': 'Android access missing',
      };
    }
    if (handler == unsupported) {
      return {
        'status': unsupportedStatus,
        'message': 'Unavailable on this Android version',
      };
    }
    switch (handler) {
      case 'device.screen.brightness.set':
        (current['screen'] as Map)['brightness'] = args['value'];
        if (args.containsKey('mode')) {
          (current['screen'] as Map)['brightnessMode'] = args['mode'];
        }
      case 'device.screen.timeout.set':
        (current['screen'] as Map)['timeoutMs'] = args['milliseconds'];
      case 'device.root.wifi.set':
        (current['connectivity'] as Map)['wifiEnabled'] = args['enabled'];
    }
    await afterMutation?.call();
    return {'status': 'applied', 'state': await snapshot()};
  }
}

class ControlledStore extends MiniAppStore {
  ControlledStore({required super.root});
  int loads = 0;
  int? trigger;
  Future<void> Function()? beforeLoad;
  @override
  Future<void> load() async {
    loads++;
    if (loads == trigger) {
      final callback = beforeLoad;
      beforeLoad = null;
      await callback?.call();
    }
    await super.load();
  }
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late FakeDevice device;
  var clock = 0;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-runtime-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
      now: () => DateTime(2026, 1, 1, 0, 0, clock++),
    );
    device = FakeDevice();
    runtime = MiniAppRuntime(store: store, device: device);
  });
  tearDown(() async {
    await runtime.dispose();
    await device.events.close();
    await temp.delete(recursive: true);
  });

  Map<String, dynamic> stateAction({Map<String, dynamic>? schema}) => {
    'name': 'save',
    'description': 'Save value',
    'permissions': [],
    'danger': 'write',
    'inputSchema':
        schema ??
        {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
            'note': {'type': 'string'},
          },
          'required': ['value'],
          'additionalProperties': false,
        },
    'executor': {
      'kind': 'state',
      'patch': {
        'saved': {r'$arg': 'value'},
      },
    },
  };
  Map<String, dynamic> nativeAction(
    String handler, {
    String name = 'set',
    String danger = 'write',
    Map<String, dynamic>? schema,
  }) => {
    'name': name,
    'description': 'Device action',
    'permissions': MiniAppDeviceService.permissionsFor(handler).toList(),
    'danger': danger,
    'inputSchema': schema ?? MiniAppDeviceService.inputSchemaFor(handler),
    'executor': {'kind': 'native', 'handler': handler},
  };
  Map<String, dynamic> sequenceAction(
    List<Map<String, dynamic>> steps, {
    String name = 'start',
    List<String> permissions = const [],
    String danger = 'write',
  }) => {
    'name': name,
    'description': 'Run ordered actions',
    'permissions': permissions,
    'danger': danger,
    'inputSchema': {'type': 'object'},
    'executor': {'kind': 'sequence', 'steps': steps},
  };
  Future<MiniApp> install({
    String id = 'panel',
    List<Map<String, dynamic>>? actions,
    List<String> permissions = const [
      'actions.ai',
      'device.battery.read',
      'device.screen.read',
    ],
  }) async {
    final source = await temp.createTemp('source-');
    await File(p.join(source.path, MiniAppStore.manifestFile)).writeAsString(
      jsonEncode({
        'id': id,
        'name': 'Panel',
        'formatVersion': 2,
        'permissions': permissions,
        'actions': actions ?? [stateAction()],
      }),
    );
    await File(p.join(source.path, 'index.html')).writeAsString('panel');
    return (await store.install(source)).app;
  }

  const button = MiniAppInvocation(source: MiniAppInvocationSource.button);
  MiniAppInvocation ai({
    Future<bool> Function(MiniApp, MiniAppAction, Map<String, dynamic>)?
    approve,
    bool Function()? isAllowed,
    bool Function()? fullTrust,
  }) => MiniAppInvocation(
    source: MiniAppInvocationSource.chat,
    approve: approve,
    isAllowed: isAllowed,
    fullTrust: fullTrust,
  );

  test(
    'sequence rechecks grants after the final applied step and retains only safe completed evidence',
    () async {
      await install(
        actions: [
          sequenceAction([
            {
              'action': 'save',
              'arguments': {'value': 1},
            },
          ]),
          stateAction(),
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.battery.read',
        true,
      );
      device.pendingSnapshot = Completer<void>();
      final written = Completer<void>();
      final dataSub = store.dataChanges.listen((_) {
        if (!written.isCompleted) {
          written.complete();
        }
      });
      try {
        final pending = runtime.execute(
          'panel',
          'start',
          {},
          invocation: button,
        );
        await written.future;
        await device.snapshotEntered.future;
        await runtime.permissions.setGranted(
          'panel',
          'device.battery.read',
          false,
        );
        device.pendingSnapshot!.complete();
        final result = await pending;
        expect(await store.storageGet('panel', 'saved'), 1);
        expect(result['status'], 'permission_required');
        expect(result['partial'], true);
        expect(result['completedSteps'], hasLength(1));
        expect(result['completedSteps'][0]['result']['status'], 'applied');
        expect(
          result['completedSteps'][0]['result'].containsKey('state'),
          false,
        );
      } finally {
        await dataSub.cancel();
      }
    },
  );

  test(
    'sequences run ordered native and nested state actions without a mutation lane deadlock',
    () async {
      final increment = stateAction();
      increment['name'] = 'increment';
      increment['inputSchema'] = {'type': 'object'};
      increment['executor'] = {
        'kind': 'state',
        'expressions': true,
        'patch': {
          'count': {r'$inc': 1},
        },
      };
      await install(
        actions: [
          sequenceAction(
            [
              {
                'action': 'save',
                'arguments': {
                  'value': {r'$arg': 'value'},
                },
              },
              {
                'action': 'bright',
                'arguments': {
                  'value': {r'$arg': 'value'},
                },
              },
              {'action': 'bump'},
            ],
            permissions: ['device.screen.write'],
          ),
          sequenceAction([
            {'action': 'increment'},
          ], name: 'bump'),
          stateAction(),
          increment,
          nativeAction('device.screen.brightness.set', name: 'bright'),
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      device.afterMutation = () async {
        expect(await store.storageGet('panel', 'saved'), 80);
      };
      final result = await runtime.execute('panel', 'start', {
        'value': 80,
      }, invocation: button);
      expect(result['status'], 'applied');
      expect((result['completedSteps'] as List).map((s) => s['action']), [
        'save',
        'bright',
        'bump',
      ]);
      expect(result['partial'], false);
      expect(await store.storageAll('panel'), {'saved': 80, 'count': 1});
      expect(device.calls, ['device.screen.brightness.set']);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test('sequence failure stops after honest completed effects', () async {
    await install(
      actions: [
        sequenceAction(
          [
            {
              'action': 'save',
              'arguments': {'value': 1},
            },
            {
              'action': 'bright',
              'arguments': {'value': 80},
            },
            {
              'action': 'save',
              'arguments': {'value': 3},
            },
          ],
          permissions: ['device.screen.write'],
        ),
        stateAction(),
        nativeAction('device.screen.brightness.set', name: 'bright'),
      ],
    );
    await runtime.permissions.setGranted('panel', 'device.screen.write', true);
    device.fail = 'device.screen.brightness.set';
    final result = await runtime.execute(
      'panel',
      'start',
      {},
      invocation: button,
    );
    expect(result['status'], 'permission_required');
    expect(result['partial'], true);
    expect(result['completedSteps'], hasLength(1));
    expect(result['failedStep']['index'], 1);
    expect(result['failedStep']['action'], 'bright');
    expect(await store.storageGet('panel', 'saved'), 1);
    expect(device.calls, ['device.screen.brightness.set']);
  });

  test(
    'sequence continue stops an ambiguous timeout inside an aggregated preset failure',
    () async {
      await install(
        actions: [
          sequenceAction(
            [
              {'action': 'preset', 'arguments': {}, 'onFailure': 'continue'},
              {
                'action': 'save',
                'arguments': {'value': 1},
              },
            ],
            permissions: ['device.screen.write'],
          ),
          {
            'name': 'preset',
            'description': 'Focus settings',
            'permissions': ['device.screen.write'],
            'danger': 'write',
            'inputSchema': {'type': 'object'},
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': 'device.screen.brightness.set',
                  'args': {'value': 77},
                },
              ],
            },
          },
          stateAction(),
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      device.unsupported = 'device.screen.brightness.set';
      device.unsupportedStatus = 'unknown_after_timeout';
      final result = await runtime.execute(
        'panel',
        'start',
        {},
        invocation: button,
      );
      expect(result['status'], 'failed');
      expect(await store.storageAll('panel'), isEmpty);
      expect(result['completedSteps'], isEmpty);
      expect(
        result['failedStep']['result']['steps'][0]['status'],
        'unknown_after_timeout',
      );
    },
  );

  test(
    'sequence continue keeps ordinary partial failure visible while recording Focus state',
    () async {
      await install(
        actions: [
          sequenceAction(
            [
              {'action': 'preset', 'arguments': {}, 'onFailure': 'continue'},
              {
                'action': 'save',
                'arguments': {'value': 1},
              },
            ],
            permissions: ['device.screen.write'],
          ),
          {
            'name': 'preset',
            'description': 'Focus settings',
            'permissions': ['device.screen.write'],
            'danger': 'write',
            'inputSchema': {'type': 'object'},
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': 'device.screen.brightness.set',
                  'args': {'value': 77},
                },
                {
                  'handler': 'device.screen.timeout.set',
                  'args': {'milliseconds': 15000},
                },
              ],
            },
          },
          stateAction(),
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      // Ordinary unsupported outcome, unlike a missing required grant.
      device.unsupported = 'device.screen.timeout.set';
      final result = await runtime.execute(
        'panel',
        'start',
        {},
        invocation: button,
      );
      expect(result['status'], 'failed');
      expect(result['partial'], true);
      expect(result['failedStep']['action'], 'preset');
      expect(result['failedSteps'], hasLength(1));
      expect((result['completedSteps'] as List).single['action'], 'save');
      expect(await store.storageGet('panel', 'saved'), 1);
      expect(result['steps'], hasLength(2));
      expect(
        (await store.readHostData('panel', 'undo.json'))['steps'],
        hasLength(1),
      );
    },
  );

  test(
    'sequence continue never bypasses revoked grants approval refusal or background ownership',
    () async {
      await install(
        actions: [
          sequenceAction(
            [
              {
                'action': 'bright',
                'arguments': {'value': 80},
                'onFailure': 'continue',
              },
              {
                'action': 'save',
                'arguments': {'value': 3},
              },
            ],
            permissions: ['device.screen.write'],
          ),
          stateAction(),
          nativeAction('device.screen.brightness.set', name: 'bright'),
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      await runtime.permissions.setGranted('panel', 'actions.ai', true);
      final denied = await runtime.execute(
        'panel',
        'start',
        {},
        invocation: ai(approve: (_, _, _) async => false),
      );
      expect(denied['status'], 'denied');
      expect(await store.storageAll('panel'), isEmpty);
      expect(device.calls, isEmpty);
      device.afterMutation = () =>
          runtime.permissions.setGranted('panel', 'device.screen.write', false);
      final revoked = await runtime.execute(
        'panel',
        'start',
        {},
        invocation: button,
      );
      expect(revoked['status'], 'permission_required');
      expect(await store.storageAll('panel'), isEmpty);
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      for (final source in [
        MiniAppInvocationSource.background,
        MiniAppInvocationSource.wifi,
      ]) {
        expect(
          (await runtime.execute(
            'panel',
            'start',
            {},
            invocation: MiniAppInvocation(
              source: source,
              fullTrust: () => true,
            ),
          ))['status'],
          'denied',
        );
      }
      expect(await store.storageAll('panel'), isEmpty);
      expect(device.calls, hasLength(1));
    },
  );

  test(
    'ACP sequence asks normal per-step consent including root and shares cancellation',
    () async {
      await install(
        actions: [
          sequenceAction(
            [
              {
                'action': 'save',
                'arguments': {'value': 1},
              },
              {
                'action': 'wifi',
                'arguments': {'enabled': false},
              },
            ],
            permissions: ['device.root.wifi'],
            danger: 'root',
          ),
          stateAction(),
          nativeAction('device.root.wifi.set', name: 'wifi', danger: 'root'),
        ],
      );
      await runtime.permissions.setGranted('panel', 'device.root.wifi', true);
      await runtime.permissions.setGranted('panel', 'actions.ai', true);
      final approved = <String>[];
      final result = await runtime.execute(
        'panel',
        'start',
        {},
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.acp,
          approve: (_, action, _) async {
            approved.add(action.name);
            return true;
          },
        ),
      );
      expect(result['status'], 'applied');
      expect(approved, ['save', 'wifi']);
      expect((device.current['connectivity'] as Map)['wifiEnabled'], false);
    },
  );

  test(
    'state executors without expression opt in preserve recognized dollar objects as literal JSON',
    () async {
      for (final enabled in [null, false]) {
        for (final patch in <Map<String, dynamic>>[
          {
            'value': {r'$inc': 1},
          },
          {
            'value': {r'$now': false},
          },
          {r'$now': true},
        ]) {
          final action = stateAction();
          action['executor'] = {
            'kind': 'state',
            if (enabled != null) 'expressions': enabled,
            'patch': patch,
          };
          await install(actions: [action]);
          for (final key in await store.storageKeys('panel')) {
            await store.storageRemove('panel', key);
          }
          final result = await runtime.execute('panel', 'save', {
            'value': 1,
          }, invocation: button);
          expect(result['status'], 'applied');
          expect(await store.storageAll('panel'), patch);
        }
      }
    },
  );

  test(
    'state expressions use one prepatch snapshot in the atomic write',
    () async {
      final action = stateAction();
      action['executor'] = {
        'kind': 'state',
        'expressions': true,
        'patch': {
          'counter': {
            r'$inc': {r'$arg': 'value'},
          },
          'previous': {r'$data': 'counter'},
          'nested': {
            'total': {
              r'$add': [
                1,
                {r'$data': 'counter'},
              ],
            },
          },
        },
      };
      await install(actions: [action]);
      await store.storageSet('panel', 'counter', 2);
      final result = await runtime.execute('panel', 'save', {
        'value': 3,
      }, invocation: button);
      expect(result['status'], 'applied');
      expect(await store.storageAll('panel'), {
        'counter': 5,
        'previous': 2,
        'nested': {'total': 3},
      });
    },
  );

  test(
    'foreground web mutations require consent while native buttons use the same action directly',
    () async {
      await install();
      expect(
        (await runtime.execute(
          'panel',
          'save',
          {'value': 2},
          invocation: const MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            forceConfirmation: true,
          ),
        ))['status'],
        'permission_required',
      );
      var prompts = 0;
      expect(
        (await runtime.execute(
          'panel',
          'save',
          {'value': 2},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            forceConfirmation: true,
            approve: (_, _, _) async {
              prompts++;
              return true;
            },
          ),
        ))['status'],
        'applied',
      );
      expect(prompts, 1);
      expect(
        (await runtime.execute('panel', 'save', {
          'value': 3,
        }, invocation: button))['status'],
        'applied',
      );
      expect(prompts, 1);
    },
  );

  test(
    'uniqueItems compares objects without key-order and numerically equal number differences',
    () async {
      await install(
        actions: [
          stateAction(
            schema: {
              'type': 'object',
              'properties': {
                'value': {'type': 'array', 'uniqueItems': true},
              },
              'required': ['value'],
              'additionalProperties': false,
            },
          ),
        ],
      );
      for (final values in [
        [
          {
            'a': 1,
            'b': [2],
          },
          {
            'b': [2.0],
            'a': 1.0,
          },
        ],
        [1, 1.0],
      ]) {
        expect(
          (await runtime.execute('panel', 'save', {
            'value': values,
          }, invocation: button))['status'],
          'failed',
        );
      }
      expect(
        (await runtime.execute('panel', 'save', {
          'value': [
            {'a': 1},
            {'a': 2},
          ],
        }, invocation: button))['status'],
        'applied',
      );
    },
  );

  test(
    'source schema reference expansion stops at a bounded evaluation budget',
    () async {
      final defs = <String, dynamic>{
        'leaf': {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer', 'maximum': 0},
          },
          'required': ['value'],
        },
      };
      var previous = 'leaf';
      for (var i = 0; i < 14; i++) {
        final name = 'node$i';
        defs[name] = {
          'anyOf': [
            {r'$ref': '#/\$defs/$previous'},
            {r'$ref': '#/\$defs/$previous'},
          ],
        };
        previous = name;
      }
      await install(
        actions: [
          stateAction(schema: {r'$defs': defs, r'$ref': '#/\$defs/$previous'}),
        ],
      );
      final result = await runtime.execute('panel', 'save', {
        'value': 1,
      }, invocation: button);
      expect(result['status'], 'failed');
      expect(result['message'], contains('evaluation limit'));
      expect(await store.storageAll('panel'), isEmpty);
    },
  );

  test(
    'expected app is checked after loading before the replacement schema',
    () async {
      await runtime.dispose();
      final controlled = ControlledStore(
        root: () async => Directory(p.join(temp.path, 'controlled-apps')),
      );
      store = controlled;
      runtime = MiniAppRuntime(store: store, device: device);
      final offered = await install();
      controlled.trigger = controlled.loads + 1;
      controlled.beforeLoad = () => install(
        actions: [
          stateAction(
            schema: {
              'type': 'object',
              'properties': {
                'renamed': {'type': 'string'},
              },
              'required': ['renamed'],
              'additionalProperties': false,
            },
          ),
        ],
      );
      final result = await runtime.execute(
        'panel',
        'save',
        {'value': 1},
        invocation: button,
        expectedApp: offered,
      );
      expect(result['code'], 'app_changed');
      expect(await store.storageAll('panel'), isEmpty);
    },
  );

  test(
    'state checks identity after its final asynchronous grant read',
    () async {
      await runtime.dispose();
      final controlled = ControlledStore(
        root: () async => Directory(p.join(temp.path, 'controlled-apps')),
      );
      store = controlled;
      runtime = MiniAppRuntime(store: store, device: device);
      await install();
      await runtime.permissions.granted('panel');
      controlled.loads = 0;
      controlled.trigger = 3;
      controlled.beforeLoad = () async {
        await install();
      };
      expect((await runtime.state('panel'))['status'], 'denied');
    },
  );

  test(
    'tool schemas stay original and sanitized colliding names stay distinct',
    () async {
      final action = stateAction();
      await install(id: 'a-b', actions: [action]);
      await install(id: 'a--b', actions: [action]);
      final tools = runtime.toolDefinitions();
      expect(tools, hasLength(2));
      final names = tools
          .map((t) => (t['function'] as Map)['name'] as String)
          .toList();
      expect(names.toSet(), hasLength(2));
      for (final name in names) {
        expect(name.length, lessThanOrEqualTo(64));
        expect(runtime.resolveTool(name)!.actionName, 'save');
      }
      expect(
        (tools.first['function'] as Map)['parameters'],
        action['inputSchema'],
      );
    },
  );

  test(
    'button and approved AI use identical atomic state with strict optional null omitted',
    () async {
      await install();
      expect(
        (await runtime.execute('panel', 'save', {
          'value': 3,
          'note': null,
        }, invocation: button))['status'],
        'applied',
      );
      final before = await runtime.state('panel');
      expect(before['data'], {'saved': 3});
      expect(before['device'], isEmpty);
      expect(
        (await runtime.execute('panel', 'save', {
          'value': 3,
        }, invocation: ai(approve: (_, _, _) async => true)))['status'],
        'permission_required',
      );
      await runtime.permissions.setGranted('panel', 'actions.ai', true);
      expect(
        (await runtime.execute('panel', 'save', {
          'value': 3,
        }, invocation: ai(approve: (_, _, _) async => true)))['status'],
        'applied',
      );
      expect((await runtime.state('panel'))['data'], before['data']);
      expect(
        (await runtime.execute('panel', 'save', {
          'value': null,
        }, invocation: button))['status'],
        'failed',
      );
    },
  );

  test(
    'original nullable unions and local refs are enforced without removing allowed null',
    () async {
      await install(
        actions: [
          stateAction(
            schema: {
              'type': 'object',
              r'$defs': {
                'v': {
                  'anyOf': [
                    {'type': 'integer', 'minimum': 2},
                    {'type': 'null'},
                  ],
                },
              },
              'properties': {
                'value': {r'$ref': '#/\$defs/v'},
              },
              'required': ['value'],
              'additionalProperties': false,
            },
          ),
        ],
      );
      expect(
        (await runtime.execute('panel', 'save', {
          'value': null,
        }, invocation: button))['status'],
        'applied',
      );
      expect((await runtime.state('panel'))['data'], {'saved': null});
      expect(
        (await runtime.execute('panel', 'save', {
          'value': 1,
        }, invocation: button))['status'],
        'failed',
      );
    },
  );

  test(
    'background state actions cannot mutate data or notify foreground viewers even in full trust',
    () async {
      await install(
        actions: [
          stateAction(),
          nativeAction('device.battery.get', name: 'battery', danger: 'read'),
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.battery.read',
        true,
      );
      var prompts = 0;
      final background = MiniAppInvocation(
        source: MiniAppInvocationSource.background,
        fullTrust: () => true,
        approve: (_, _, _) async {
          prompts++;
          return true;
        },
      );
      final events = <Map<String, dynamic>>[];
      final ready = Completer<void>();
      final subscription = runtime.watch('panel', (state) {
        events.add(state);
        if (!ready.isCompleted) {
          ready.complete();
        }
      });
      try {
        await ready.future;
        await device.attached.future;
        events.clear();
        final revision = store.dataRevisionFor('panel');
        final result = await runtime.execute('panel', 'save', {
          'value': 80,
        }, invocation: background);
        expect(await store.storageAll('panel'), isEmpty);
        expect(store.dataRevisionFor('panel'), revision);
        expect(events, isEmpty);
        expect(result['status'], 'denied');
        expect(result['code'], 'background_denied');
        expect(prompts, 0);
        expect(device.calls, isEmpty);
        final read = await runtime.execute(
          'panel',
          'battery',
          {},
          invocation: background,
        );
        expect(read['status'], 'applied');
        expect((read['state'] as Map)['device'], {
          'battery': {'level': 45, 'powerSave': false},
        });
        expect(
          (await runtime.state('panel', invocation: background))['data'],
          isEmpty,
        );
        expect(device.calls, ['device.battery.get']);
        expect(prompts, 0);
        expect(events, isEmpty);
      } finally {
        await subscription.cancel();
      }
    },
  );

  test(
    'wifi gets no new state or actions and background cannot prompt for device mutation',
    () async {
      await install(actions: [nativeAction('device.screen.brightness.set')]);
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      expect(
        (await runtime.execute(
          'panel',
          'set',
          {'value': 80},
          invocation: const MiniAppInvocation(
            source: MiniAppInvocationSource.wifi,
          ),
        ))['status'],
        'denied',
      );
      expect(
        (await runtime.state(
          'panel',
          invocation: const MiniAppInvocation(
            source: MiniAppInvocationSource.wifi,
          ),
        ))['status'],
        'denied',
      );
      var prompts = 0;
      expect(
        (await runtime.execute(
          'panel',
          'set',
          {'value': 80},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.background,
            approve: (_, _, _) async {
              prompts++;
              return true;
            },
          ),
        ))['status'],
        'denied',
      );
      expect(prompts, 0);
      expect(device.calls, isEmpty);
    },
  );

  test(
    'native read state is filtered by explicit grants and revocation while snapshot waits',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'panel',
        'device.battery.read',
        true,
      );
      expect((await runtime.state('panel'))['device'], {
        'battery': {'level': 45, 'powerSave': false},
      });
      device.pendingSnapshot = Completer<void>();
      final reading = runtime.state('panel');
      await Future<void>.delayed(Duration.zero);
      await runtime.permissions.setGranted(
        'panel',
        'device.battery.read',
        false,
      );
      device.pendingSnapshot!.complete();
      expect((await reading)['device'], isEmpty);
    },
  );

  test(
    'grant revoke, deletion, replacement and ownership cancel stale pending approvals',
    () async {
      for (final change in ['grant', 'delete', 'update', 'owner']) {
        await install(actions: [nativeAction('device.screen.brightness.set')]);
        await runtime.permissions.setGranted('panel', 'actions.ai', true);
        await runtime.permissions.setGranted(
          'panel',
          'device.screen.write',
          true,
        );
        final entered = Completer<void>();
        final approval = Completer<bool>();
        var allowed = true;
        final executing = runtime.execute(
          'panel',
          'set',
          {'value': 80},
          invocation: ai(
            isAllowed: () => allowed,
            approve: (_, _, _) {
              entered.complete();
              return approval.future;
            },
          ),
        );
        await entered.future;
        switch (change) {
          case 'grant':
            await runtime.permissions.setGranted(
              'panel',
              'device.screen.write',
              false,
            );
          case 'delete':
            await store.delete('panel');
          case 'update':
            await install(
              actions: [nativeAction('device.screen.brightness.set')],
            );
          case 'owner':
            allowed = false;
        }
        approval.complete(true);
        expect((await executing)['status'], isNot('applied'), reason: change);
      }
      expect(device.calls, isEmpty);
    },
  );

  test(
    'root requires confirmation on buttons and full trust only bypasses approval',
    () async {
      await install(
        actions: [nativeAction('device.root.wifi.set', danger: 'root')],
      );
      expect(
        (await runtime.execute(
          'panel',
          'set',
          {'enabled': false},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            fullTrust: () => true,
          ),
        ))['status'],
        'permission_required',
      );
      await runtime.permissions.setGranted('panel', 'device.root.wifi', true);
      expect(
        (await runtime.execute('panel', 'set', {
          'enabled': false,
        }, invocation: button))['status'],
        'permission_required',
      );
      expect(
        (await runtime.execute(
          'panel',
          'set',
          {'enabled': false},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            approve: (_, _, _) async => false,
          ),
        ))['status'],
        'denied',
      );
      expect(
        (await runtime.execute(
          'panel',
          'set',
          {'enabled': false},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            fullTrust: () => true,
          ),
        ))['status'],
        'applied',
      );
    },
  );

  test(
    'revocation then regrant does not resurrect a pending approval',
    () async {
      await install(actions: [nativeAction('device.screen.brightness.set')]);
      await runtime.permissions.setGranted('panel', 'actions.ai', true);
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      final entered = Completer<void>();
      final approval = Completer<bool>();
      final pending = runtime.execute(
        'panel',
        'set',
        {'value': 80},
        invocation: ai(
          approve: (_, _, _) {
            entered.complete();
            return approval.future;
          },
        ),
      );
      await entered.future;
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        false,
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      approval.complete(true);
      expect((await pending)['status'], 'permission_required');
      expect(device.calls, isEmpty);
    },
  );

  test(
    'button native requests cancel on grant revoke, replacement and viewer disposal',
    () async {
      for (final reason in ['grant', 'update', 'lifetime']) {
        final localDevice = FakeDevice();
        final localRuntime = MiniAppRuntime(store: store, device: localDevice);
        await install(actions: [nativeAction('device.screen.brightness.set')]);
        await localRuntime.permissions.setGranted(
          'panel',
          'device.screen.write',
          true,
        );
        localDevice.pendingNative = Completer<void>();
        final lifetime = Completer<void>();
        final execution = localRuntime.execute(
          'panel',
          'set',
          {'value': 80},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            cancelled: lifetime.future,
          ),
        );
        await localDevice.nativeEntered.future;
        if (reason == 'grant') {
          await localRuntime.permissions.setGranted(
            'panel',
            'device.screen.write',
            false,
          );
        }
        if (reason == 'update') {
          await install(
            actions: [nativeAction('device.screen.brightness.set')],
          );
        }
        if (reason == 'lifetime') {
          lifetime.complete();
        }
        expect((await execution)['status'], isNot('applied'), reason: reason);
        expect((localDevice.current['screen'] as Map)['brightness'], 120);
        await localRuntime.dispose();
        await localDevice.events.close();
      }
    },
  );

  test(
    'preset skips a prior setting outside the fixed restore argument limits',
    () async {
      await install(
        actions: [
          {
            'name': 'night',
            'description': 'Night preset',
            'permissions': ['device.screen.write'],
            'danger': 'write',
            'inputSchema': {'type': 'object'},
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': 'device.screen.timeout.set',
                  'args': {'milliseconds': 15000},
                },
              ],
            },
          },
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      (device.current['screen'] as Map)['timeoutMs'] = 10000;
      final result = await runtime.execute(
        'panel',
        'night',
        {},
        invocation: button,
      );
      expect(result['partial'], isTrue);
      expect((result['steps'] as List).single['status'], 'unsupported');
      expect((device.current['screen'] as Map)['timeoutMs'], 10000);
      expect(device.calls, isEmpty);
    },
  );

  test(
    'an approval callback cannot change the validated execution arguments',
    () async {
      await install();
      await runtime.permissions.setGranted('panel', 'actions.ai', true);
      final result = await runtime.execute(
        'panel',
        'save',
        {'value': 2},
        invocation: ai(
          approve: (_, _, args) async {
            args['value'] = 1000;
            return true;
          },
        ),
      );
      expect(result['status'], 'applied');
      expect(await store.storageGet('panel', 'saved'), 2);
    },
  );

  test(
    'root restore approval presents the effective danger and concrete operation',
    () async {
      await install(
        actions: [
          {
            'name': 'offline',
            'description': 'Disconnect Wi-Fi',
            'permissions': ['device.root.wifi'],
            'danger': 'root',
            'inputSchema': {'type': 'object'},
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': 'device.root.wifi.set',
                  'args': {'enabled': false},
                },
              ],
            },
          },
          {
            'name': 'restore',
            'description': 'Restore',
            'permissions': [],
            'danger': 'write',
            'inputSchema': {'type': 'object'},
            'executor': {'kind': 'restore'},
          },
        ],
      );
      await runtime.permissions.setGranted('panel', 'device.root.wifi', true);
      await runtime.execute(
        'panel',
        'offline',
        {},
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          fullTrust: () => true,
        ),
      );
      MiniAppAction? presented;
      Map<String, dynamic>? presentedArgs;
      final result = await runtime.execute(
        'panel',
        'restore',
        {},
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          approve: (_, action, args) async {
            presented = action;
            presentedArgs = args;
            return true;
          },
        ),
      );
      expect(result['status'], 'applied');
      expect(presented!.danger, MiniAppDanger.root);
      expect(presented!.permissions, contains('device.root.wifi'));
      expect(presentedArgs!['operations'], [
        {
          'handler': 'device.root.wifi.set',
          'args': {'enabled': true},
        },
      ]);
    },
  );

  test(
    'watches share one native subscription and cancel it after the last viewer',
    () async {
      await install();
      await runtime.permissions.setGranted('panel', 'device.screen.read', true);
      final first = <Map<String, dynamic>>[];
      final second = <Map<String, dynamic>>[];
      final watch1 = runtime.watch('panel', first.add);
      final watch2 = runtime.watch('panel', second.add);
      await device.attached.future;
      expect(device.listeners, 1);
      device.events.add(await device.snapshot());
      await runtime.execute('panel', 'save', {'value': 9}, invocation: button);
      await Future<void>.delayed(Duration.zero);
      expect(first.last['data'], {'saved': 9});
      expect(second.last['data'], {'saved': 9});
      await watch1.cancel();
      expect(device.listeners, 1);
      await watch2.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(device.listeners, 0);
    },
  );

  for (final restoring in [false, true]) {
    test(
      '${restoring ? 'restore' : 'preset'} retains completed step evidence after grant cancellation',
      () async {
        await install(
          actions: [
            {
              'name': 'night',
              'description': 'Night preset',
              'permissions': ['device.screen.write'],
              'danger': 'write',
              'inputSchema': {'type': 'object'},
              'executor': {
                'kind': 'preset',
                'steps': [
                  {
                    'handler': 'device.screen.brightness.set',
                    'args': {'value': 60},
                  },
                  {
                    'handler': 'device.screen.timeout.set',
                    'args': {'milliseconds': 15000},
                  },
                ],
              },
            },
            {
              'name': 'restore',
              'description': 'Restore',
              'permissions': [],
              'danger': 'write',
              'inputSchema': {'type': 'object'},
              'executor': {'kind': 'restore'},
            },
          ],
        );
        await runtime.permissions.setGranted(
          'panel',
          'device.screen.write',
          true,
        );
        if (restoring) {
          await runtime.execute('panel', 'night', {}, invocation: button);
          device.calls.clear();
        }
        device.afterMutation = () => runtime.permissions.setGranted(
          'panel',
          'device.screen.write',
          false,
        );
        final result = await runtime.execute(
          'panel',
          restoring ? 'restore' : 'night',
          {},
          invocation: button,
        );
        expect(device.calls, hasLength(1));
        expect(result['status'], 'permission_required');
        expect(result['partial'], isTrue);
        expect(result['steps'], [
          {
            'handler': restoring
                ? 'device.screen.timeout.set'
                : 'device.screen.brightness.set',
            'status': 'applied',
          },
        ]);
        expect(result.containsKey('state'), isFalse);
        final undo = await store.readHostData('panel', 'undo.json');
        expect(undo['steps'], hasLength(1));
      },
    );
  }

  test(
    'preset partial failure only restores recorded applied steps and preserves manual changes',
    () async {
      await install(
        actions: [
          {
            'name': 'night',
            'description': 'Night preset',
            'permissions': ['device.screen.write'],
            'danger': 'write',
            'inputSchema': {
              'type': 'object',
              'properties': {},
              'additionalProperties': false,
            },
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': 'device.screen.brightness.set',
                  'args': {'value': 60},
                },
                {
                  'handler': 'device.screen.timeout.set',
                  'args': {'milliseconds': 15000},
                },
              ],
            },
          },
          {
            'name': 'restore',
            'description': 'Restore preset',
            'permissions': [],
            'danger': 'write',
            'inputSchema': {
              'type': 'object',
              'properties': {},
              'additionalProperties': false,
            },
            'executor': {'kind': 'restore'},
          },
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      device.fail = 'device.screen.timeout.set';
      final result = await runtime.execute(
        'panel',
        'night',
        {},
        invocation: button,
      );
      expect(result['partial'], isTrue);
      expect(result['status'], 'failed');
      expect((device.current['screen'] as Map)['brightness'], 60);
      (device.current['screen'] as Map)['brightness'] = 200;
      final restored = await runtime.execute(
        'panel',
        'restore',
        {},
        invocation: button,
      );
      expect(restored['conflicts'], contains('screen.brightness'));
      expect((device.current['screen'] as Map)['brightness'], 200);
      expect(device.calls, [
        'device.screen.brightness.set',
        'device.screen.timeout.set',
      ]);
    },
  );

  test(
    'restore checks live stored operation permissions and restores actual before values',
    () async {
      await install(
        actions: [
          {
            'name': 'night',
            'description': 'Night preset',
            'permissions': ['device.screen.write'],
            'danger': 'write',
            'inputSchema': {'type': 'object'},
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': 'device.screen.brightness.set',
                  'args': {'value': 60, 'mode': 'manual'},
                },
              ],
            },
          },
          {
            'name': 'restore',
            'description': 'Restore',
            'permissions': [],
            'danger': 'write',
            'inputSchema': {'type': 'object'},
            'executor': {'kind': 'restore'},
          },
        ],
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      await runtime.execute('panel', 'night', {}, invocation: button);
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        false,
      );
      expect(
        (await runtime.execute(
          'panel',
          'restore',
          {},
          invocation: button,
        ))['status'],
        'permission_required',
      );
      await runtime.permissions.setGranted(
        'panel',
        'device.screen.write',
        true,
      );
      expect(
        (await runtime.execute(
          'panel',
          'restore',
          {},
          invocation: button,
        ))['status'],
        'applied',
      );
      expect((device.current['screen'] as Map)['brightness'], 120);
      expect((device.current['screen'] as Map)['brightnessMode'], 'automatic');
    },
  );
}
