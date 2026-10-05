import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_permissions.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/focus_mini_app.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// The device boundary reports actual mutable settings and native readback.
/// The built-in manifest, installation, grants, expressions, undo and sequences
/// are exercised through production code rather than reproduced in the fake.
class _FocusDevice extends MiniAppDeviceService {
  _FocusDevice() {
    events = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        listeners++;
        listenStarts++;
        if (!attached.isCompleted) attached.complete();
      },
      onCancel: () => listeners--,
    );
  }

  late final StreamController<Map<String, dynamic>> events;
  final attached = Completer<void>();
  final calls = <Map<String, dynamic>>[];
  final outcomes = <String, String>{};
  int listeners = 0;
  int listenStarts = 0;
  bool android15 = false;
  Future<void> Function(String handler)? afterMutation;
  final current = <String, dynamic>{
    'screen': {
      'brightness': 151,
      'brightnessMode': 'automatic',
      'timeoutMs': 60000,
      'canWrite': true,
      'reasons': <String, dynamic>{},
    },
    'audio': {
      'dnd': 'priority',
      'canChangeDnd': true,
      'canAccessDnd': true,
      'volumes': {
        'music': {'value': 6, 'min': 0, 'max': 15},
      },
      'reasons': <String, dynamic>{},
    },
  };

  Map<String, dynamic> get screen => current['screen'] as Map<String, dynamic>;
  Map<String, dynamic> get audio => current['audio'] as Map<String, dynamic>;
  Map<String, dynamic> get music =>
      (audio['volumes'] as Map)['music'] as Map<String, dynamic>;

  @override
  Stream<Map<String, dynamic>> get changes => events.stream;

  @override
  Future<Map<String, dynamic>> snapshot() async {
    final state = _copy(current);
    state['system'] = {'sdkInt': android15 ? 35 : 34};
    if (android15) {
      (state['audio'] as Map)['canChangeDnd'] = false;
      (state['audio'] as Map)['reasons'] = {
        'canChangeDnd': 'unsupported_android_version',
      };
    }
    return state;
  }

  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    calls.add({'handler': handler, 'args': _copy(args)});
    final status = android15 && handler == 'device.audio.dnd.set'
        ? 'unsupported'
        : outcomes[handler] ?? 'applied';
    if (status == 'applied') {
      switch (handler) {
        case 'device.screen.brightness.set':
          screen['brightness'] = (args['value'] as num).toInt();
          if (args.containsKey('mode')) screen['brightnessMode'] = args['mode'];
        case 'device.audio.volume.set':
          final stream = (audio['volumes'] as Map)[args['stream']] as Map;
          stream['value'] = (args['value'] as num).toInt();
        case 'device.audio.dnd.set':
          audio['dnd'] = args['mode'];
        default:
          throw StateError('Unexpected Focus device mutation: $handler');
      }
      await afterMutation?.call(handler);
    }
    return {
      'status': status,
      'message': status == 'unsupported'
          ? 'Use Android DND settings on Android 15.'
          : status == 'permission_required'
          ? 'Android special access is missing.'
          : status == 'denied'
          ? 'Android denied this change.'
          : 'Android confirmed the actual settings.',
      'state': await snapshot(),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late _FocusDevice device;
  late DateTime now;

  const button = MiniAppInvocation(source: MiniAppInvocationSource.button);
  const presetCalls = [
    {
      'handler': 'device.screen.brightness.set',
      'args': {'value': 77, 'mode': 'manual'},
    },
    {
      'handler': 'device.audio.volume.set',
      'args': {'stream': 'music', 'value': 0},
    },
    {
      'handler': 'device.audio.dnd.set',
      'args': {'mode': 'none'},
    },
  ];
  const restoreCalls = [
    {
      'handler': 'device.audio.dnd.set',
      'args': {'mode': 'priority'},
    },
    {
      'handler': 'device.audio.volume.set',
      'args': {'stream': 'music', 'value': 6},
    },
    {
      'handler': 'device.screen.brightness.set',
      'args': {'value': 151, 'mode': 'automatic'},
    },
  ];

  Future<void> grantAll(bool enabled) async {
    final app = store.byId(FocusMiniApp.id)!;
    for (final capability in MiniAppPermissions.declared(app)) {
      await runtime.permissions.setGranted(app.id, capability, enabled);
    }
  }

  Future<Map<String, dynamic>> run(
    String action, {
    MiniAppInvocation invocation = button,
    Map<String, dynamic> args = const {},
  }) => runtime.execute(FocusMiniApp.id, action, args, invocation: invocation);

  Future<Map<String, dynamic>> data() => store.storageAll(FocusMiniApp.id);

  void expectOriginalDevice() {
    expect(device.screen['brightness'], 151);
    expect(device.screen['brightnessMode'], 'automatic');
    expect(device.music['value'], 6);
    expect(device.audio['dnd'], 'priority');
  }

  setUp(() async {
    now = DateTime(2026, 10, 5, 9, 15);
    temp = await Directory.systemTemp.createTemp('focus-runtime-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
      now: () => now,
    );
    device = _FocusDevice();
    runtime = MiniAppRuntime(store: store, device: device, now: () => now);
    await FocusMiniApp.ensureInstalled(store);
    await grantAll(true);
  });

  tearDown(() async {
    await runtime.dispose();
    store.dispose();
    await device.events.close();
    await temp.delete(recursive: true);
  });

  for (final minutes in [15, 25, 50]) {
    test(
      'actual Focus start_$minutes applies the preset and records its deadline',
      () async {
        final result = await run('start_$minutes');
        expect(result['status'], 'applied');
        expect(result['partial'], false);
        expect((result['completedSteps'] as List).map((s) => s['action']), [
          'focus_preset',
          'record_start',
        ]);
        expect(device.calls, presetCalls);
        expect(await data(), {
          'startedAt': now.millisecondsSinceEpoch,
          'endsAt': now.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          'running': true,
          'sessionsToday': 0,
          'sessionDay': '2026-10-05',
        });
        final state = await runtime.state(FocusMiniApp.id);
        expect(state['data'], await data());
        expect((state['device'] as Map)['screen']['brightness'], 77);
        expect(
          (state['device'] as Map)['audio']['volumes']['music']['value'],
          0,
        );
        final undo = await store.readHostData(FocusMiniApp.id, 'undo.json');
        expect((undo['steps'] as List).map((s) => s['handler']), [
          for (final call in presetCalls) call['handler'],
        ]);
        expect(device.listeners, 0);
        expect(device.listenStarts, 0);
      },
    );
  }

  test(
    'stop counts once and restores original brightness mode media and DND',
    () async {
      await run('start_25');
      now = now.add(const Duration(minutes: 25));
      device.calls.clear();
      final stopped = await run('stop');
      expect(stopped['status'], 'applied');
      expect((stopped['completedSteps'] as List).map((s) => s['action']), [
        'record_stop',
        'restore',
      ]);
      expect(device.calls, restoreCalls);
      expectOriginalDevice();
      final stoppedData = await data();
      expect(stoppedData['running'], false);
      expect(stoppedData['endsAt'], isNull);
      expect(stoppedData['sessionsToday'], 1);
      expect(stoppedData['sessionDay'], '2026-10-05');
      expect(
        (await store.readHostData(FocusMiniApp.id, 'undo.json'))['steps'],
        isEmpty,
      );

      device.calls.clear();
      final repeated = await run('stop');
      expect(repeated['status'], 'applied');
      expect(await data(), stoppedData);
      expect(device.calls, isEmpty);
      expectOriginalDevice();
    },
  );

  test(
    'Android 15 DND unsupported keeps a partial failure while starting and restoring the timer session',
    () async {
      device.android15 = true;
      final result = await run('start_25');
      expect(result['status'], 'failed');
      expect(result['partial'], true);
      expect(result['failedStep']['action'], 'focus_preset');
      expect(result['failedSteps'], hasLength(1));
      expect(
        (result['completedSteps'] as List).single['action'],
        'record_start',
      );
      expect(
        (result['steps'] as List).last,
        containsPair('status', 'unsupported'),
      );
      expect((await data())['running'], true);
      expect(
        (await data())['endsAt'],
        now.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
      );
      expect(device.screen['brightness'], 77);
      expect(device.music['value'], 0);
      expect(device.audio['dnd'], 'priority');
      final undo = await store.readHostData(FocusMiniApp.id, 'undo.json');
      expect((undo['steps'] as List).map((s) => s['handler']), [
        'device.screen.brightness.set',
        'device.audio.volume.set',
      ]);

      device.calls.clear();
      final stopped = await run('stop');
      expect(stopped['status'], 'applied');
      expect(device.calls, restoreCalls.skip(1).toList());
      expectOriginalDevice();
      expect((await data())['sessionsToday'], 1);
    },
  );

  for (final status in ['permission_required', 'denied']) {
    test('Android $status cannot be continued into a timer start', () async {
      device.outcomes['device.screen.brightness.set'] = status;
      device.screen['canWrite'] = false;
      final result = await run('start_15');
      expect(result['status'], 'failed');
      expect(result['partial'], true);
      expect(result['failedStep']['action'], 'focus_preset');
      expect(result['completedSteps'], isEmpty);
      expect((result['steps'] as List).first['status'], status);
      expect(await data(), isEmpty);
      expect(device.screen['brightness'], 151);
      expect(device.screen['brightnessMode'], 'automatic');
      // Later preset effects remain accurately visible and restorable.
      expect(device.music['value'], 0);
      expect(device.audio['dnd'], 'none');
      final undo = await store.readHostData(FocusMiniApp.id, 'undo.json');
      expect((undo['steps'] as List).map((s) => s['handler']), [
        'device.audio.volume.set',
        'device.audio.dnd.set',
      ]);
    });
  }

  test(
    'missing Android Settings access reports its outcome without changing Focus state or grants',
    () async {
      device.outcomes['device.settings.open'] = 'permission_required';
      final beforeGrants = await runtime.permissions.granted(FocusMiniApp.id);
      final result = await run('settings', args: {'page': 'write_settings'});
      expect(result['status'], 'permission_required');
      expect(device.calls, [
        {
          'handler': 'device.settings.open',
          'args': {'page': 'write_settings'},
        },
      ]);
      expect(await data(), isEmpty);
      expect(await runtime.permissions.granted(FocusMiniApp.id), beforeGrants);
      expectOriginalDevice();
    },
  );

  test(
    'full grant revocation after a completed native step stops both later settings and timer data',
    () async {
      device.afterMutation = (_) async {
        device.afterMutation = null;
        await grantAll(false);
      };
      final result = await run('start_50');
      expect(result['status'], 'permission_required');
      expect(result['partial'], true);
      expect(result['failedStep']['action'], 'focus_preset');
      expect(result['completedSteps'], isEmpty);
      expect(device.calls, [presetCalls.first]);
      expect(await data(), isEmpty);
      expect(await runtime.permissions.granted(FocusMiniApp.id), isEmpty);
      expect((await runtime.state(FocusMiniApp.id))['device'], isEmpty);
      expect(device.screen['brightness'], 77);
      expect(device.music['value'], 6);
      final undo = await store.readHostData(FocusMiniApp.id, 'undo.json');
      expect(
        (undo['steps'] as List).single['handler'],
        'device.screen.brightness.set',
      );
      expect(device.listeners, 0);
    },
  );

  test(
    'manual brightness change after Focus is preserved as a restore conflict',
    () async {
      await run('start_15');
      device.screen['brightness'] = 203;
      device.calls.clear();
      final stopped = await run('stop');
      expect(stopped['status'], 'failed');
      expect(stopped['partial'], true);
      expect(
        (stopped['completedSteps'] as List).single['action'],
        'record_stop',
      );
      expect(stopped['failedStep']['action'], 'restore');
      expect(stopped['failedStep']['result']['conflicts'], [
        'screen.brightness',
      ]);
      expect((stopped['steps'] as List).last['status'], 'conflict');
      expect(device.calls, restoreCalls.take(2).toList());
      expect(device.screen['brightness'], 203);
      expect(device.screen['brightnessMode'], 'manual');
      expect(device.music['value'], 6);
      expect(device.audio['dnd'], 'priority');
      expect((await data())['sessionsToday'], 1);
      expect((await data())['running'], false);
      expect(
        (await store.readHostData(FocusMiniApp.id, 'undo.json'))['steps'],
        isEmpty,
      );
      device.calls.clear();
      await run('stop');
      expect((await data())['sessionsToday'], 1);
      expect(device.calls, isEmpty);
      expect(device.screen['brightness'], 203);
    },
  );

  for (final source in [
    MiniAppInvocationSource.button,
    MiniAppInvocationSource.chat,
    MiniAppInvocationSource.acp,
  ]) {
    test(
      '${source.name} runs the same Focus settings state and per-step consent workflow while closed',
      () async {
        final approvals = <Map<String, dynamic>>[];
        final invocation = MiniAppInvocation(
          source: source,
          isAllowed: () => true,
          fullTrust: () => false,
          approve: (_, action, arguments) async {
            approvals.add({'action': action.name, 'args': _copy(arguments)});
            return true;
          },
        );
        final started = await run('start_50', invocation: invocation);
        expect(started['status'], 'applied');
        expect(device.calls, presetCalls);
        expect(
          (await data())['endsAt'],
          now.add(const Duration(minutes: 50)).millisecondsSinceEpoch,
        );
        final stopped = await run('stop', invocation: invocation);
        expect(stopped['status'], 'applied');
        expect((await data())['sessionsToday'], 1);
        expectOriginalDevice();
        if (source == MiniAppInvocationSource.button) {
          expect(approvals, isEmpty);
        } else {
          expect(approvals.map((approval) => approval['action']), [
            'focus_preset',
            'record_start',
            'record_stop',
            'restore',
          ]);
          expect(
            approvals.first['args']['operations'],
            presetCalls
                .map(
                  (call) => {'handler': call['handler'], 'args': call['args']},
                )
                .toList(),
          );
          expect(approvals[1]['args'], {'durationMs': 3000000});
          expect(
            approvals.last['args']['operations'],
            restoreCalls
                .map(
                  (call) => {'handler': call['handler'], 'args': call['args']},
                )
                .toList(),
          );
        }
        expect(device.listeners, 0);
        expect(device.listenStarts, 0);
      },
    );
  }

  for (final declined in ['focus_preset', 'record_start']) {
    test(
      'chat refusal of $declined never records a timer despite explicit continuation',
      () async {
        final approvals = <String>[];
        final result = await run(
          'start_25',
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.chat,
            approve: (_, action, _) async {
              approvals.add(action.name);
              return action.name != declined;
            },
          ),
        );
        expect(result['status'], 'denied');
        expect(result['code'], 'approval_denied');
        expect(result['failedStep']['action'], declined);
        expect(await data(), isEmpty);
        if (declined == 'focus_preset') {
          expect(approvals, ['focus_preset']);
          expect(device.calls, isEmpty);
          expectOriginalDevice();
        } else {
          expect(approvals, ['focus_preset', 'record_start']);
          expect(device.calls, presetCalls);
          expect(result['partial'], true);
          expect(
            (await store.readHostData(FocusMiniApp.id, 'undo.json'))['steps'],
            hasLength(3),
          );
        }
      },
    );
  }

  test(
    'deadline expiry and day rollover require explicit stop and never run background device watchers',
    () async {
      await store.storageSet(FocusMiniApp.id, 'sessionDay', '2026-10-04');
      await store.storageSet(FocusMiniApp.id, 'sessionsToday', 7);
      now = DateTime(2026, 10, 5, 23, 50);
      await run('start_15');
      expect((await data())['sessionsToday'], 0);
      now = DateTime(2026, 10, 6, 0, 10);
      final expired = await runtime.state(FocusMiniApp.id);
      expect((expired['data'] as Map)['running'], true);
      expect((expired['data'] as Map)['sessionsToday'], 0);
      expect(
        (expired['data'] as Map)['endsAt'],
        lessThan(now.millisecondsSinceEpoch),
      );
      expect(device.calls, presetCalls);
      expect(device.listenStarts, 0);
      await run('stop');
      expect((await data())['sessionsToday'], 1);
      expect((await data())['sessionDay'], '2026-10-06');
      await run('stop');
      expect((await data())['sessionsToday'], 1);
      expectOriginalDevice();
    },
  );
}
