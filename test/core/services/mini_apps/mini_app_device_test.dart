import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.mini_app_device');
  const events = EventChannel('test.mini_app_device/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });

  test(
    'catalog gives each root operation its own permission and confirmation',
    () {
      for (final operation in [
        'power_save',
        'wifi',
        'bluetooth',
        'data',
        'airplane',
      ]) {
        final handler = 'device.root.$operation.set';
        expect(MiniAppDeviceService.permissionsFor(handler), {
          'device.root.$operation',
        });
        expect(MiniAppDeviceService.isMutation(handler), isTrue);
        expect(MiniAppDeviceService.requiresConfirmation(handler), isTrue);
      }
      expect(MiniAppDeviceService.permissionsFor('device.root.stop_app'), {
        'device.root.stop_app',
      });
      expect(
        MiniAppDeviceService.requiresConfirmation('device.root.stop_app'),
        isTrue,
      );
      expect(MiniAppDeviceService.permissionsFor('device.battery.get'), {
        'device.battery.read',
      });
      expect(MiniAppDeviceService.isMutation('device.battery.get'), isFalse);
      expect(
        MiniAppDeviceService.requiresConfirmation(
          'device.screen.brightness.set',
        ),
        isFalse,
      );
    },
  );

  test(
    'catalog schemas bound native setters and preserve optional brightness mode',
    () {
      final brightness = MiniAppDeviceService.inputSchemaFor(
        'device.screen.brightness.set',
      );
      expect(brightness?['required'], ['value']);
      expect(brightness?['additionalProperties'], isFalse);
      expect((brightness?['properties'] as Map)['value'], {
        'type': 'integer',
        'minimum': 0,
        'maximum': 255,
      });
      expect(
        MiniAppDeviceService.inputSchemaFor(
          'device.root.stop_app',
        )?['properties'],
        {
          'packageName': {
            'type': 'string',
            'minLength': 3,
            'maxLength': 200,
            'pattern': r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
          },
        },
      );
      expect(MiniAppDeviceService.handlers, hasLength(18));
      expect(MiniAppDeviceService.knownCapabilities, hasLength(16));
      expect(MiniAppDeviceService.inputSchemaFor('device.shell'), isNull);
      // Callers cannot weaken the authoritative catalog by editing a schema copy.
      (brightness!['properties'] as Map)['value'] = {'type': 'string'};
      expect(
        (MiniAppDeviceService.inputSchemaFor(
              'device.screen.brightness.set',
            )!['properties']
            as Map)['value']['type'],
        'integer',
      );
    },
  );

  test(
    'snapshot decodes nested native maps without inventing absent readings',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'snapshot');
        return {
          'battery': {
            'levelPercent': 42,
            'currentMicroamps': null,
            'reasons': {'currentMicroamps': 'sensor_unavailable'},
          },
        };
      });
      final service = MiniAppDeviceService(channel: channel, events: events);
      final state = await service.snapshot();
      expect(state['battery']['levelPercent'], 42);
      expect(state['battery']['currentMicroamps'], isNull);
      expect(
        state['battery']['reasons']['currentMicroamps'],
        'sensor_unavailable',
      );
    },
  );

  test(
    'execution sends fixed handler and arguments and returns actual native status',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'execute');
        expect(call.arguments['handler'], 'device.screen.brightness.set');
        expect(call.arguments['args'], {'value': 80});
        expect(call.arguments['requestId'], isA<String>());
        return {
          'status': 'permission_required',
          'message': 'Allow Android system settings access.',
          'state': {
            'screen': {'canWrite': false},
          },
        };
      });
      final result = await MiniAppDeviceService(
        channel: channel,
        events: events,
      ).execute('device.screen.brightness.set', {'value': 80});
      expect(result['status'], 'permission_required');
      expect(result['state']['screen']['canWrite'], isFalse);
    },
  );

  test('unknown handlers never enter the method channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return {};
    });
    final result = await MiniAppDeviceService(
      channel: channel,
      events: events,
    ).execute('device.root.exec', {'command': 'id'});
    expect(result['status'], 'unsupported');
    expect(calls, 0);
  });

  test(
    'timeout cancels the same native request and reports an unknown outcome',
    () async {
      final stalled = Completer<Object?>();
      String? requestId;
      String? cancelledId;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'execute') {
          requestId = call.arguments['requestId'] as String;
          return stalled.future;
        }
        if (call.method == 'cancel') {
          cancelledId = call.arguments['requestId'] as String;
        }
        return null;
      });
      final result = await MiniAppDeviceService(
        channel: channel,
        events: events,
        operationTimeout: const Duration(milliseconds: 20),
      ).execute('device.root.wifi.set', {'enabled': true});
      expect(result['status'], 'unknown_after_timeout');
      expect(cancelledId, requestId);
      stalled.complete({'status': 'applied'});
    },
  );

  test(
    'native subscriptions exist only while changes are watched and restart',
    () async {
      final nativeCalls = <String>[];
      messenger.setMockMethodCallHandler(MethodChannel(events.name), (
        call,
      ) async {
        nativeCalls.add(call.method);
        return null;
      });
      final service = MiniAppDeviceService(channel: channel, events: events);
      expect(nativeCalls, isEmpty);
      final first = service.changes.listen((_) {});
      final second = service.changes.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(nativeCalls, ['listen']);
      await first.cancel();
      expect(nativeCalls, ['listen']);
      await second.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(nativeCalls, ['listen', 'cancel']);
      final again = service.changes.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(nativeCalls, ['listen', 'cancel', 'listen']);
      await again.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(nativeCalls.last, 'cancel');
    },
  );

  test(
    'Stop promptly cancels native root work and never returns a late applied outcome',
    () async {
      final stopped = Completer<void>();
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final acknowledge = Completer<void>();
      final native = Completer<Object?>();
      var isStopped = false;
      String? executionId;
      String? cancellationId;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'execute') {
          executionId = call.arguments['requestId'] as String;
          started.complete();
          return native.future;
        }
        if (call.method == 'cancel') {
          cancellationId = call.arguments['requestId'] as String;
          cancelled.complete();
          await acknowledge.future;
        }
        return null;
      });
      final token = ToolCallCancellation(
        isCancelled: () => isStopped,
        cancelled: stopped.future,
      );
      var finished = false;
      final result = token.run(
        () => MiniAppDeviceService(
          channel: channel,
          events: events,
        ).execute('device.root.wifi.set', {'enabled': false}),
      );
      unawaited(
        result.then((_) {
          finished = true;
        }),
      );
      await started.future;
      isStopped = true;
      stopped.complete();
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(cancellationId, executionId);
      expect(finished, isFalse);
      acknowledge.complete();
      native.complete({
        'status': 'applied',
        'message': 'Late response',
        'state': {
          'connectivity': {'wifiEnabled': false},
        },
      });
      expect((await result)['status'], 'unknown_after_timeout');
    },
  );

  test(
    'already cancelled tool ownership cannot start a native operation',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        return {};
      });
      final stopped = Completer<void>();
      var isStopped = false;
      final token = ToolCallCancellation(
        isCancelled: () => isStopped,
        cancelled: stopped.future,
      );
      final result = await token.run(() async {
        // Ownership can be lost after entering the tool zone, before the device
        // request starts. This exercises the device precheck itself.
        isStopped = true;
        stopped.complete();
        return MiniAppDeviceService(
          channel: channel,
          events: events,
        ).execute('device.root.wifi.set', {'enabled': true});
      });
      expect(result['status'], 'denied');
      expect(calls, 0);
    },
  );
}
