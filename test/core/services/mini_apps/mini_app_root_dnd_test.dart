import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/focus_mini_app.dart';
import 'package:Kelivo/features/mini_apps/phone_control_mini_app.dart';

class _DndDevice extends MiniAppDeviceService {
  final calls = <Map<String, dynamic>>[];
  final current = <String, dynamic>{
    'screen': {
      'brightness': 120,
      'brightnessMode': 'automatic',
      'timeoutMs': 60000,
    },
    'audio': {
      'dnd': 'all',
      'canChangeDnd': false,
      'volumes': {
        'music': {'value': 6},
      },
    },
  };
  String rootStatus = 'applied';
  String? manuallyChangedMode;

  String get mode => (current['audio'] as Map)['dnd'] as String;
  set mode(String value) => (current['audio'] as Map)['dnd'] = value;

  @override
  Future<Map<String, dynamic>> snapshot() async =>
      jsonDecode(jsonEncode(current)) as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    calls.add({'handler': handler, 'args': Map<String, dynamic>.of(args)});
    if (handler == 'device.audio.dnd.set') return {'status': 'unsupported'};
    if (handler == 'device.root.dnd.set' && rootStatus != 'applied') {
      if (manuallyChangedMode != null) mode = manuallyChangedMode!;
      return {'status': rootStatus};
    }
    switch (handler) {
      case 'device.root.dnd.set':
        mode = args['mode'] as String;
      case 'device.screen.brightness.set':
        (current['screen'] as Map)['brightness'] = args['value'];
        (current['screen'] as Map)['brightnessMode'] = args['mode'];
      case 'device.screen.timeout.set':
        (current['screen'] as Map)['timeoutMs'] = args['milliseconds'];
      case 'device.audio.volume.set':
        (current['audio'] as Map)['volumes']['music']['value'] = args['value'];
      default:
        throw StateError('Unexpected device handler: $handler');
    }
    return {'status': 'applied'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late _DndDevice device;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-root-dnd-');
    store = MiniAppStore(root: () async => Directory('${temp.path}/apps'));
    device = _DndDevice();
    runtime = MiniAppRuntime(store: store, device: device);
  });
  tearDown(() async {
    await runtime.dispose();
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> install({bool directRoot = false}) async {
    final handler = directRoot ? 'device.root.dnd.set' : 'device.audio.dnd.set';
    final source = Directory('${temp.path}/source')..createSync();
    File('${source.path}/moru-app.json').writeAsStringSync(
      jsonEncode({
        'id': 'dnd',
        'name': 'DND',
        'formatVersion': 2,
        'permissions': ['actions.ai', 'device.root.dnd'],
        'actions': [
          {
            'name': 'set',
            'description': 'Set DND',
            'inputSchema': MiniAppDeviceService.inputSchemaFor(handler),
            'permissions': MiniAppDeviceService.permissionsFor(
              handler,
            ).toList(),
            'danger': directRoot ? 'root' : 'write',
            'executor': {'kind': 'native', 'handler': handler},
          },
          {
            'name': 'preset',
            'description': 'Quiet preset',
            'inputSchema': {'type': 'object', 'additionalProperties': false},
            'permissions': MiniAppDeviceService.permissionsFor(
              handler,
            ).toList(),
            'danger': directRoot ? 'root' : 'write',
            'executor': {
              'kind': 'preset',
              'steps': [
                {
                  'handler': handler,
                  'args': {'mode': 'priority'},
                },
              ],
            },
          },
          {
            'name': 'restore',
            'description': 'Restore DND',
            'inputSchema': {'type': 'object', 'additionalProperties': false},
            'permissions': [],
            'danger': 'write',
            'executor': {'kind': 'restore'},
          },
        ],
      }),
    );
    File('${source.path}/index.html').writeAsStringSync('DND');
    await store.install(source);
    if (!directRoot) {
      await runtime.permissions.setGranted('dnd', 'device.audio.write', true);
    }
  }

  const button = MiniAppInvocation(source: MiniAppInvocationSource.button);
  MiniAppInvocation trusted(MiniAppInvocationSource source) =>
      MiniAppInvocation(source: source, fullTrust: () => true);

  for (final mode in ['all', 'priority', 'alarms', 'none']) {
    test(
      'explicit root DND $mode requires its own grant and confirmation',
      () async {
        await install(directRoot: true);
        final missing = await runtime.execute('dnd', 'set', {
          'mode': mode,
        }, invocation: trusted(MiniAppInvocationSource.button));
        expect(missing['status'], 'permission_required');
        expect(device.calls, isEmpty);
        await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
        final unconfirmed = await runtime.execute('dnd', 'set', {
          'mode': mode,
        }, invocation: button);
        expect(unconfirmed['status'], 'permission_required');
        expect(device.calls, isEmpty);
        final applied = await runtime.execute(
          'dnd',
          'set',
          {'mode': mode},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            approve: (_, action, _) async {
              expect(action.danger, MiniAppDanger.root);
              return true;
            },
          ),
        );
        expect(applied['status'], 'applied');
        expect(device.mode, mode);
        expect(device.calls.single, {
          'handler': 'device.root.dnd.set',
          'args': {'mode': mode},
        });
      },
    );
  }

  for (final source in [
    MiniAppInvocationSource.button,
    MiniAppInvocationSource.chat,
    MiniAppInvocationSource.acp,
  ]) {
    test(
      '${source.name} DND chooses granted root and presents the actual operation',
      () async {
        await install();
        await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
        await runtime.permissions.setGranted('dnd', 'actions.ai', true);
        var approved = false;
        final result = await runtime.execute(
          'dnd',
          'set',
          {'mode': 'none'},
          invocation: MiniAppInvocation(
            source: source,
            approve: (_, action, args) async {
              approved = true;
              expect(action.danger, MiniAppDanger.root);
              expect(action.permissions, contains('device.root.dnd'));
              expect(args['operations'], [
                {
                  'handler': 'device.root.dnd.set',
                  'args': {'mode': 'none'},
                },
              ]);
              return true;
            },
          ),
        );
        expect(result['status'], 'applied');
        expect(approved, true);
        expect(device.calls.single['handler'], 'device.root.dnd.set');
        expect(device.mode, 'none');
      },
    );
  }

  test(
    'without a root grant ordinary modern DND remains unsupported',
    () async {
      await install();
      final result = await runtime.execute('dnd', 'set', {
        'mode': 'none',
      }, invocation: button);
      expect(result['status'], 'unsupported');
      expect(device.calls.single['handler'], 'device.audio.dnd.set');
      expect(device.mode, 'all');
    },
  );

  test(
    'revoking root while consent is pending does not fall back or write',
    () async {
      await install();
      await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
      final offered = Completer<void>();
      final consent = Completer<bool>();
      final result = runtime.execute(
        'dnd',
        'set',
        {'mode': 'none'},
        invocation: MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          approve: (_, _, _) {
            offered.complete();
            return consent.future;
          },
        ),
      );
      await offered.future;
      await runtime.permissions.setGranted('dnd', 'device.root.dnd', false);
      consent.complete(true);
      expect((await result)['status'], isNot('applied'));
      expect(device.calls, isEmpty);
      expect(device.mode, 'all');
    },
  );

  for (final directRoot in [false, true]) {
    test(
      'root DND preset/restore records exact handler and refuses revoked rights ($directRoot)',
      () async {
        await install(directRoot: directRoot);
        await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
        final invocation = trusted(MiniAppInvocationSource.button);
        final preset = await runtime.execute(
          'dnd',
          'preset',
          {},
          invocation: invocation,
        );
        expect(preset['status'], 'applied');
        expect(device.mode, 'priority');
        final undo = await store.readHostData('dnd', 'undo.json');
        expect(
          (undo['steps'] as List).single['handler'],
          'device.root.dnd.set',
        );
        device.calls.clear();
        await runtime.permissions.setGranted('dnd', 'device.root.dnd', false);
        expect(
          (await runtime.execute(
            'dnd',
            'restore',
            {},
            invocation: invocation,
          ))['status'],
          'permission_required',
        );
        expect(device.calls, isEmpty);
        expect(device.mode, 'priority');
        expect(await store.readHostData('dnd', 'undo.json'), undo);
        await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
        final restored = await runtime.execute(
          'dnd',
          'restore',
          {},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            approve: (_, action, args) async {
              expect(action.danger, MiniAppDanger.root);
              expect(args['operations'], [
                {
                  'handler': 'device.root.dnd.set',
                  'args': {'mode': 'all'},
                },
              ]);
              return true;
            },
          ),
        );
        expect(restored['status'], 'applied');
        expect(device.mode, 'all');
        expect(
          (await store.readHostData('dnd', 'undo.json'))['steps'],
          isEmpty,
        );
      },
    );
  }

  for (final status in ['denied', 'unsupported', 'permission_required']) {
    for (final manualMode in ['none', 'priority']) {
      test(
        'DND $status cannot own manual $manualMode while root is pending',
        () async {
          await install();
          await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
          device.rootStatus = status;
          device.manuallyChangedMode = manualMode;
          final invocation = trusted(MiniAppInvocationSource.button);
          final preset = await runtime.execute(
            'dnd',
            'preset',
            {},
            invocation: invocation,
          );
          expect(preset['status'], 'failed');
          expect(device.mode, manualMode);
          expect(
            (await store.readHostData('dnd', 'undo.json'))['steps'] ?? [],
            isEmpty,
          );
          device.calls.clear();
          final restored = await runtime.execute(
            'dnd',
            'restore',
            {},
            invocation: invocation,
          );
          expect(restored['status'], 'applied');
          expect(device.calls, isEmpty);
          expect(device.mode, manualMode);
        },
      );
    }
  }

  for (final matchesRequest in [false, true]) {
    test(
      'DND timeout owns only verified requested readback ($matchesRequest)',
      () async {
        await install();
        await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
        device.rootStatus = 'unknown_after_timeout';
        device.manuallyChangedMode = matchesRequest ? 'priority' : 'none';
        final invocation = trusted(MiniAppInvocationSource.button);
        final preset = await runtime.execute(
          'dnd',
          'preset',
          {},
          invocation: invocation,
        );
        expect(preset['status'], 'failed');
        final steps =
            (await store.readHostData('dnd', 'undo.json'))['steps'] as List? ??
            [];
        expect(steps, hasLength(matchesRequest ? 1 : 0));
        device.rootStatus = 'applied';
        device.calls.clear();
        await runtime.execute('dnd', 'restore', {}, invocation: invocation);
        expect(device.calls, hasLength(matchesRequest ? 1 : 0));
        expect(device.mode, matchesRequest ? 'all' : 'none');
      },
    );
  }

  test('root DND restore preserves a user change as a conflict', () async {
    await install();
    await runtime.permissions.setGranted('dnd', 'device.root.dnd', true);
    final invocation = trusted(MiniAppInvocationSource.button);
    await runtime.execute('dnd', 'preset', {}, invocation: invocation);
    device.mode = 'alarms';
    device.calls.clear();
    final result = await runtime.execute(
      'dnd',
      'restore',
      {},
      invocation: invocation,
    );
    expect(result['status'], 'failed');
    expect(result['conflicts'], ['audio.dnd']);
    expect(device.calls, isEmpty);
    expect(device.mode, 'alarms');
  });

  for (final builtin in [PhoneControlMiniApp.id, FocusMiniApp.id]) {
    test(
      '$builtin uses granted root for its actual preset and restores DND',
      () async {
        if (builtin == PhoneControlMiniApp.id) {
          await PhoneControlMiniApp.ensureInstalled(store);
        } else {
          await FocusMiniApp.ensureInstalled(store);
        }
        expect(store.byId(builtin)!.permissions, contains('device.root.dnd'));
        for (final capability in [
          'device.screen.write',
          'device.audio.write',
          'device.root.dnd',
        ]) {
          await runtime.permissions.setGranted(builtin, capability, true);
        }
        final invocation = trusted(MiniAppInvocationSource.button);
        final result = await runtime.execute(
          builtin,
          builtin == PhoneControlMiniApp.id ? 'night' : 'start_25',
          {},
          invocation: invocation,
        );
        expect(result['status'], 'applied');
        expect(device.calls.last['handler'], 'device.root.dnd.set');
        expect(
          device.mode,
          builtin == PhoneControlMiniApp.id ? 'priority' : 'none',
        );
        device.calls.clear();
        final restored = await runtime.execute(
          builtin,
          builtin == PhoneControlMiniApp.id ? 'restore' : 'stop',
          {},
          invocation: invocation,
        );
        expect(restored['status'], 'applied');
        expect(device.calls.first['handler'], 'device.root.dnd.set');
        expect(device.mode, 'all');
      },
    );
  }
}
