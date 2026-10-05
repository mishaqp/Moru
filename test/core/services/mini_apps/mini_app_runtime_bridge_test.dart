import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_web_server.dart';

class _Device extends MiniAppDeviceService {
  final calls = <String>[];
  Future<void> Function()? duringExecute;
  @override
  Future<Map<String, dynamic>> snapshot() async => {
    'battery': {'level': 73},
    'screen': {'brightness': 40},
  };
  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    calls.add(handler);
    await duringExecute?.call();
    return {'status': 'applied', 'state': await snapshot()};
  }

  @override
  Stream<Map<String, dynamic>> get changes => const Stream.empty();
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late _Device device;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-runtime-bridge-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    device = _Device();
    runtime = MiniAppRuntime(store: store, device: device);
  });
  tearDown(() async {
    await runtime.dispose();
    await temp.delete(recursive: true);
  });

  Future<MiniApp> install({int formatVersion = 2}) async {
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'control',
        'name': 'Control',
        'formatVersion': formatVersion,
        if (formatVersion == 2)
          'permissions': [
            'actions.ai',
            'device.battery.read',
            'device.screen.write',
            'device.root.power_save',
          ],
        if (formatVersion == 2)
          'actions': [
            {
              'name': 'set_count',
              'description': 'Set count',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'count': {'type': 'integer'},
                },
                'required': ['count'],
                'additionalProperties': false,
              },
              'permissions': [],
              'danger': 'write',
              'executor': {
                'kind': 'state',
                'patch': {
                  'count': {r'$arg': 'count'},
                },
              },
            },
            {
              'name': 'battery',
              'description': 'Read battery',
              'inputSchema': {
                'type': 'object',
                'properties': {},
                'additionalProperties': false,
              },
              'permissions': ['device.battery.read'],
              'danger': 'read',
              'executor': {'kind': 'native', 'handler': 'device.battery.get'},
            },
            {
              'name': 'brightness',
              'description': 'Set brightness',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'value': {'type': 'integer', 'minimum': 1, 'maximum': 255},
                },
                'required': ['value'],
                'additionalProperties': false,
              },
              'permissions': ['device.screen.write'],
              'danger': 'write',
              'executor': {
                'kind': 'native',
                'handler': 'device.screen.brightness.set',
              },
            },
            {
              'name': 'power',
              'description': 'Set power save',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'enabled': {'type': 'boolean'},
                },
                'required': ['enabled'],
                'additionalProperties': false,
              },
              'permissions': ['device.root.power_save'],
              'danger': 'root',
              'executor': {
                'kind': 'native',
                'handler': 'device.root.power_save.set',
              },
            },
          ],
      }),
    );
    File(p.join(source.path, 'index.html')).writeAsStringSync('<p>Control</p>');
    return (await store.install(source)).app;
  }

  MiniAppBridge bridge(MiniAppInvocation invocation) => MiniAppBridge(
    store: store,
    appId: 'control',
    host: MiniAppHost(runtime: runtime, invocation: invocation),
  );
  Future<Map<String, dynamic>> call(
    MiniAppBridge bridge,
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final script = await bridge.handle(
      jsonEncode({'id': 1, 'method': method, 'args': args}),
    );
    final match = RegExp(
      r'^window\.__moruReply\(1, (true|false), (.*)\);$',
    ).firstMatch(script!)!;
    expect(match[1], 'true');
    return Map<String, dynamic>.from(jsonDecode(match[2]!) as Map);
  }

  test('web action and chat action write the same runtime state', () async {
    await install();
    await runtime.permissions.setGranted('control', 'actions.ai', true);
    final web = bridge(
      MiniAppInvocation(
        source: MiniAppInvocationSource.button,
        approve: (_, __, ___) async => true,
      ),
    );
    expect(
      (await call(web, 'actions.invoke', {
        'name': 'set_count',
        'arguments': {'count': 4},
      }))['status'],
      'applied',
    );
    expect((await call(web, 'state.get'))['data'], {'count': 4});
    await runtime.execute(
      'control',
      'set_count',
      {'count': 7},
      invocation: MiniAppInvocation(
        source: MiniAppInvocationSource.chat,
        approve: (_, __, ___) async => true,
      ),
    );
    expect((await call(web, 'state.get'))['data'], {'count': 7});
  });

  test(
    'Wi-Fi rejects every new action, state and device entry despite grants and trust',
    () async {
      await install();
      for (final capability in [
        'actions.ai',
        'device.battery.read',
        'device.root.power_save',
      ]) {
        await runtime.permissions.setGranted('control', capability, true);
      }
      final wifi = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.wifi,
          fullTrust: () => true,
        ),
      );
      for (final invocation in [
        (
          'actions.invoke',
          {
            'name': 'set_count',
            'arguments': {'count': 8},
          },
        ),
        ('state.get', <String, dynamic>{}),
        ('device.snapshot', <String, dynamic>{}),
        (
          'device.invoke',
          {'handler': 'device.battery.get', 'arguments': <String, dynamic>{}},
        ),
      ]) {
        expect(
          (await call(wifi, invocation.$1, invocation.$2))['status'],
          'denied',
        );
      }
      expect(device.calls, isEmpty);
      expect((await runtime.state('control'))['data'], isEmpty);
      // Existing data stays readable over Wi-Fi.
      await store.storageSet('control', 'old', 1);
      expect(
        await wifi.handle(
          jsonEncode({
            'id': 2,
            'method': 'storage.get',
            'args': {'key': 'old'},
          }),
        ),
        'window.__moruReply(2, true, 1);',
      );
    },
  );

  test(
    'Wi-Fi raw storage cannot relay a granted device write through a trusted local page',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.screen.write',
        true,
      );
      final local = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          fullTrust: () => true,
        ),
      );
      final wifi = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.wifi,
          fullTrust: () => true,
        ),
      );
      final relayed = Completer<Map<String, dynamic>>();
      var reacting = false;
      // MiniAppPage forwards runtime.watch to moru.state.subscribe even
      // when a raw bridge write suppresses the legacy moru:storage event.
      final listener = runtime.watch('control', (state) async {
        if (reacting || (state['data'] as Map)['desired'] != 80) return;
        reacting = true;
        relayed.complete(
          await call(local, 'device.invoke', {
            'handler': 'device.screen.brightness.set',
            'arguments': {'value': 80},
          }),
        );
      });
      try {
        final reply = await wifi.handle(
          jsonEncode({
            'id': 51,
            'method': 'storage.set',
            'args': {'key': 'desired', 'value': 80},
          }),
        );
        if (reply!.startsWith('window.__moruReply(51, true,')) {
          final result = await relayed.future.timeout(
            const Duration(seconds: 1),
          );
          expect(result['status'], 'applied');
        }
        expect(
          device.calls,
          isEmpty,
          reason:
              'Wi-Fi must not inherit a local page device grant via storage events.',
        );
        expect(await store.storageGet('control', 'desired'), isNull);
        expect(reply, startsWith('window.__moruReply(51, false,'));
      } finally {
        await listener.cancel();
        local.dispose();
        wifi.dispose();
      }
    },
  );

  test(
    'background raw storage cannot relay a device mutation through a trusted local page',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.screen.write',
        true,
      );
      final local = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          fullTrust: () => true,
        ),
      );
      final background = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.background,
          fullTrust: () => true,
        ),
      );
      final relayed = Completer<Map<String, dynamic>>();
      var reacting = false;
      final listener = runtime.watch('control', (state) async {
        if (reacting || (state['data'] as Map)['desired'] != 80) return;
        reacting = true;
        relayed.complete(
          await call(local, 'device.invoke', {
            'handler': 'device.screen.brightness.set',
            'arguments': {'value': 80},
          }),
        );
      });
      try {
        final reply = await background.handle(
          jsonEncode({
            'id': 52,
            'method': 'storage.set',
            'args': {'key': 'desired', 'value': 80},
          }),
        );
        if (reply!.startsWith('window.__moruReply(52, true,')) {
          final result = await relayed.future.timeout(
            const Duration(seconds: 1),
          );
          expect(result['status'], 'applied');
        }
        expect(
          device.calls,
          isEmpty,
          reason:
              'A background write must not turn into a foreground device mutation.',
        );
        expect(await store.storageGet('control', 'desired'), isNull);
        expect(reply, startsWith('window.__moruReply(52, false,'));
      } finally {
        await listener.cancel();
        local.dispose();
        background.dispose();
      }
    },
  );

  test(
    'background state actions cannot relay a device mutation through a trusted local page',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.screen.write',
        true,
      );
      final local = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          fullTrust: () => true,
        ),
      );
      final relayed = Completer<Map<String, dynamic>>();
      var reacting = false;
      final listener = runtime.watch('control', (state) async {
        if (reacting || (state['data'] as Map)['count'] != 80) return;
        reacting = true;
        relayed.complete(
          await call(local, 'device.invoke', {
            'handler': 'device.screen.brightness.set',
            'arguments': {'value': 80},
          }),
        );
      });
      try {
        final result = await runtime.execute(
          'control',
          'set_count',
          {'count': 80},
          invocation: MiniAppInvocation(
            source: MiniAppInvocationSource.background,
            fullTrust: () => true,
          ),
        );
        if (result['status'] == 'applied') {
          expect(
            (await relayed.future.timeout(
              const Duration(seconds: 1),
            ))['status'],
            'applied',
          );
        }
        expect(
          device.calls,
          isEmpty,
          reason:
              'A background state action must not become a foreground device mutation.',
        );
        expect(result['status'], 'denied');
        expect(await store.storageGet('control', 'count'), isNull);
      } finally {
        await listener.cancel();
        local.dispose();
      }
    },
  );

  test(
    'Wi-Fi HTTP v2 storage is read-only despite local full trust and device grants',
    () async {
      await install();
      await store.storageSet('control', 'desired', 12);
      await runtime.permissions.setGranted(
        'control',
        'device.screen.write',
        true,
      );
      final local = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          fullTrust: () => true,
        ),
      );
      final wifi = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.wifi,
          fullTrust: () => true,
        ),
      );
      final listener = runtime.watch('control', (state) {
        if ((state['data'] as Map)['desired'] != 12) {
          unawaited(
            call(local, 'device.invoke', {
              'handler': 'device.screen.brightness.set',
              'arguments': {'value': 80},
            }),
          );
        }
      });
      final server = MiniAppWebServer(store: store, bridgeFor: (_) => wifi);
      final client = HttpClient();
      try {
        await server.start(port: 0, localhostOnly: true);
        Future<String> post(
          String method,
          Map<String, dynamic> arguments,
        ) async {
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/app/control/__moru'),
          );
          request.write(
            jsonEncode({'id': 53, 'method': method, 'args': arguments}),
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          return utf8.decodeStream(response);
        }

        for (final operation in ['storage.set', 'storage.remove']) {
          final reply = await post(operation, {'key': 'desired', 'value': 80});
          expect(reply, startsWith('window.__moruReply(53, false,'));
          expect(reply, contains('read-only'));
          expect(await store.storageGet('control', 'desired'), 12);
        }
        expect(
          await post('storage.get', {'key': 'desired'}),
          'window.__moruReply(53, true, 12);',
        );
        expect(
          await post('storage.keys', {}),
          'window.__moruReply(53, true, ["desired"]);',
        );
        expect(device.calls, isEmpty);
      } finally {
        await listener.cancel();
        local.dispose();
        await server.stop();
        client.close(force: true);
      }
    },
  );

  for (final source in [
    MiniAppInvocationSource.wifi,
    MiniAppInvocationSource.background,
  ]) {
    test(
      '$source cannot remove v2 data and emit a reactive device mutation',
      () async {
        await install();
        await store.storageSet('control', 'desired', 12);
        await runtime.permissions.setGranted(
          'control',
          'device.screen.write',
          true,
        );
        final local = bridge(
          MiniAppInvocation(
            source: MiniAppInvocationSource.button,
            fullTrust: () => true,
          ),
        );
        final remote = bridge(
          MiniAppInvocation(source: source, fullTrust: () => true),
        );
        final relayed = Completer<Map<String, dynamic>>();
        var reacting = false;
        final listener = runtime.watch('control', (state) async {
          if (reacting || (state['data'] as Map).containsKey('desired')) return;
          reacting = true;
          relayed.complete(
            await call(local, 'device.invoke', {
              'handler': 'device.screen.brightness.set',
              'arguments': {'value': 80},
            }),
          );
        });
        try {
          final reply = await remote.handle(
            jsonEncode({
              'id': 54,
              'method': 'storage.remove',
              'args': {'key': 'desired'},
            }),
          );
          if (reply!.startsWith('window.__moruReply(54, true,')) {
            expect(
              (await relayed.future.timeout(
                const Duration(seconds: 1),
              ))['status'],
              'applied',
            );
          }
          expect(device.calls, isEmpty);
          expect(reply, startsWith('window.__moruReply(54, false,'));
          expect(reply, contains('read-only'));
          expect(await store.storageGet('control', 'desired'), 12);
        } finally {
          await listener.cancel();
          local.dispose();
          remote.dispose();
        }
      },
    );

    test('$source retains legacy v1 storage writes and removes', () async {
      await install(formatVersion: 1);
      final legacy = bridge(MiniAppInvocation(source: source));
      expect(
        await legacy.handle(
          jsonEncode({
            'id': 55,
            'method': 'storage.set',
            'args': {'key': 'legacy', 'value': 7},
          }),
        ),
        'window.__moruReply(55, true, null);',
      );
      expect(await store.storageGet('control', 'legacy'), 7);
      expect(
        await legacy.handle(
          jsonEncode({
            'id': 56,
            'method': 'storage.remove',
            'args': {'key': 'legacy'},
          }),
        ),
        'window.__moruReply(56, true, null);',
      );
      expect(await store.storageGet('control', 'legacy'), isNull);
      legacy.dispose();
    });
  }

  test(
    'a pending v2 raw write cannot publish after its web page closes',
    () async {
      final app = await install();
      final web = bridge(
        const MiniAppInvocation(source: MiniAppInvocationSource.button),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocker = store.updateState<void>(app.id, (_) async {
        entered.complete();
        await release.future;
      }, expected: app);
      await entered.future.timeout(const Duration(seconds: 1));
      final pending = web.handle(
        jsonEncode({
          'id': 57,
          'method': 'storage.set',
          'args': {'key': 'late', 'value': 80},
        }),
      );
      web.dispose();
      release.complete();
      await blocker;
      expect(await pending, startsWith('window.__moruReply(57, false,'));
      expect(await store.storageGet(app.id, 'late'), isNull);
    },
  );

  test(
    'a pending legacy Wi-Fi write cannot attach to a v2 replacement',
    () async {
      final app = await install(formatVersion: 1);
      final wifi = bridge(
        const MiniAppInvocation(source: MiniAppInvocationSource.wifi),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocker = store.updateState<void>(app.id, (_) async {
        entered.complete();
        await release.future;
      }, expected: app);
      final stoppedBlocker = blocker.then<void>((_) {}, onError: (Object _) {});
      await entered.future.timeout(const Duration(seconds: 1));
      final pending = wifi.handle(
        jsonEncode({
          'id': 58,
          'method': 'storage.set',
          'args': {'key': 'late', 'value': 80},
        }),
      );
      await install();
      release.complete();
      await stoppedBlocker;
      expect(await pending, startsWith('window.__moruReply(58, false,'));
      expect(await store.storageGet(app.id, 'late'), isNull);
      wifi.dispose();
    },
  );

  test('an old v1 channel cannot write the data of a current v2 app', () async {
    await install(formatVersion: 1);
    final old = bridge(
      const MiniAppInvocation(source: MiniAppInvocationSource.button),
    );
    await install();
    final reply = await old.handle(
      jsonEncode({
        'id': 59,
        'method': 'storage.set',
        'args': {'key': 'late', 'value': 80},
      }),
    );
    expect(reply, startsWith('window.__moruReply(59, false,'));
    expect(await store.storageGet('control', 'late'), isNull);
    old.dispose();
  });

  test(
    'an AI storage event cannot launder a web device mutation into button consent',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.screen.write',
        true,
      );
      var approvals = 0;
      final web = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          approve: (_, action, arguments) async {
            approvals++;
            expect(action.name, 'brightness');
            expect(arguments, {'value': 80});
            return false;
          },
        ),
      );
      final outcome = Completer<Map<String, dynamic>>();
      // A page's moru:storage listener is arbitrary JavaScript. It receives
      // the same event when an AI writes app data, without a user gesture.
      final listener = store.changes
          .where((event) => event.appId == 'control' && event.key == 'desired')
          .listen((_) async {
            outcome.complete(
              await call(web, 'device.invoke', {
                'handler': 'device.screen.brightness.set',
                'arguments': {'value': 80},
              }),
            );
          });
      try {
        await store.storageSet('control', 'desired', 80);
        expect(
          (await outcome.future.timeout(const Duration(seconds: 1)))['status'],
          'denied',
        );
        expect(approvals, 1);
        expect(device.calls, isEmpty);
        expect(await runtime.permissions.granted('control'), {
          'device.screen.write',
        });
      } finally {
        await listener.cancel();
        web.dispose();
      }
    },
  );

  test(
    'device shortcuts require declared actions and live per-app grants',
    () async {
      await install();
      final web = bridge(
        const MiniAppInvocation(source: MiniAppInvocationSource.button),
      );
      expect(
        (await call(web, 'device.invoke', {
          'handler': 'device.battery.get',
        }))['status'],
        'permission_required',
      );
      await runtime.permissions.setGranted(
        'control',
        'device.battery.read',
        true,
      );
      expect(
        (await call(web, 'device.invoke', {
          'handler': 'device.battery.get',
        }))['status'],
        'applied',
      );
      expect(device.calls, ['device.battery.get']);
      expect(
        (await call(web, 'device.invoke', {
          'handler': 'device.audio.volume.set',
          'arguments': {'percent': 80},
        }))['status'],
        'denied',
      );
      await runtime.permissions.setGranted(
        'control',
        'device.battery.read',
        false,
      );
      expect((await call(web, 'device.snapshot'))['device'], isEmpty);
    },
  );

  test(
    'the legacy unproven file channel cannot acquire a device context',
    () async {
      await install();
      final unbound = MiniAppBridge(store: store, appId: 'control');
      expect(
        (await call(unbound, 'actions.invoke', {
          'name': 'set_count',
          'arguments': {'count': 2},
        }))['status'],
        'denied',
      );
      expect((await call(unbound, 'state.get'))['status'], 'denied');
    },
  );

  test(
    'a background bridge never asks for dangerous approval or grants',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.root.power_save',
        true,
      );
      var approvals = 0;
      final background = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.background,
          approve: (_, __, ___) async {
            approvals++;
            return true;
          },
        ),
      );
      expect(
        (await call(background, 'device.invoke', {
          'handler': 'device.root.power_save.set',
          'arguments': {'enabled': true},
        }))['status'],
        'denied',
      );
      expect(approvals, 0);
      expect(device.calls, isEmpty);
    },
  );

  test(
    'a web page bound to an older version cannot dispatch its replacement',
    () async {
      await install();
      final old = bridge(
        const MiniAppInvocation(source: MiniAppInvocationSource.button),
      );
      await install();
      expect(
        (await call(old, 'actions.invoke', {
          'name': 'set_count',
          'arguments': {'count': 9},
        }))['status'],
        'denied',
      );
      expect((await runtime.state('control'))['data'], isEmpty);
    },
  );

  test(
    'closing a web bridge while root approval waits denies the pending operation',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.root.power_save',
        true,
      );
      final requested = Completer<void>();
      final consent = Completer<bool>();
      final web = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          approve: (_, __, ___) {
            requested.complete();
            return consent.future;
          },
        ),
      );
      final pending = call(web, 'actions.invoke', {
        'name': 'power',
        'arguments': {'enabled': true},
      });
      await requested.future;
      web.dispose();
      consent.complete(true);
      expect((await pending)['status'], 'denied');
      expect(device.calls, isEmpty);
    },
  );

  test('closing a web bridge cancels an in-flight native operation', () async {
    await install();
    await runtime.permissions.setGranted(
      'control',
      'device.root.power_save',
      true,
    );
    final entered = Completer<void>();
    final cancelled = Completer<void>();
    device.duringExecute = () async {
      final cancellation = ToolCallCancellation.current;
      expect(cancellation, isNotNull);
      entered.complete();
      await cancellation!.cancelled;
      cancelled.complete();
    };
    final web = bridge(
      MiniAppInvocation(
        source: MiniAppInvocationSource.button,
        fullTrust: () => true,
      ),
    );
    final pending = call(web, 'actions.invoke', {
      'name': 'power',
      'arguments': {'enabled': true},
    });
    await entered.future;
    web.dispose();
    await cancelled.future.timeout(const Duration(seconds: 1));
    expect((await pending)['status'], 'denied');
    expect(device.calls, ['device.root.power_save.set']);
  });

  test(
    'revoking a grant while web approval waits denies the pending operation',
    () async {
      await install();
      await runtime.permissions.setGranted(
        'control',
        'device.root.power_save',
        true,
      );
      final requested = Completer<void>();
      final consent = Completer<bool>();
      final web = bridge(
        MiniAppInvocation(
          source: MiniAppInvocationSource.button,
          approve: (_, __, ___) {
            requested.complete();
            return consent.future;
          },
        ),
      );
      final pending = call(web, 'device.invoke', {
        'handler': 'device.root.power_save.set',
        'arguments': {'enabled': true},
      });
      await requested.future;
      await runtime.permissions.setGranted(
        'control',
        'device.root.power_save',
        false,
      );
      consent.complete(true);
      expect((await pending)['status'], 'permission_required');
      expect(device.calls, isEmpty);
    },
  );
}
