import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../api/tool_call_cancellation.dart';

/// The Android device boundary. Per-app grants and invocation consent belong to
/// MiniAppRuntime; Android validates these fixed handlers again before writing.
class MiniAppDeviceService {
  MiniAppDeviceService({
    MethodChannel? channel,
    EventChannel? events,
    this.operationTimeout = const Duration(seconds: 12),
  }) : _channel = channel ?? const MethodChannel('app.mini_app_device'),
       _events = events ?? const EventChannel('app.mini_app_device/events');

  final MethodChannel _channel;
  final EventChannel _events;
  final Duration operationTimeout;
  static int _requestSequence = 0;

  // EventChannel's broadcast controller attaches on its first listener and
  // detaches on its last. map preserves that behavior, including later watches.
  late final Stream<Map<String, dynamic>> _changes = _events
      .receiveBroadcastStream()
      .map(_map);
  Stream<Map<String, dynamic>> get changes => _changes;

  static const _readGroups = [
    'battery',
    'screen',
    'audio',
    'connectivity',
    'flashlight',
    'system',
  ];
  static const _rootOperations = [
    'power_save',
    'wifi',
    'bluetooth',
    'data',
    'airplane',
  ];
  static const audioStreams = [
    'music',
    'ring',
    'notification',
    'alarm',
    'system',
    'voice_call',
  ];
  static const settingsPages = [
    'battery',
    'power_save',
    'display',
    'sound',
    'wifi',
    'bluetooth',
    'mobile_data',
    'airplane',
    'write_settings',
    'dnd',
    'dnd_access',
    'app_details',
    'permissions',
  ];

  static final Map<String, String> _permissions = Map.unmodifiable({
    for (final group in _readGroups) 'device.$group.get': 'device.$group.read',
    'device.screen.brightness.set': 'device.screen.write',
    'device.screen.timeout.set': 'device.screen.write',
    'device.audio.volume.set': 'device.audio.write',
    'device.audio.dnd.set': 'device.audio.write',
    'device.flashlight.set': 'device.flashlight.write',
    'device.settings.open': 'device.settings.open',
    for (final operation in _rootOperations)
      'device.root.$operation.set': 'device.root.$operation',
    'device.root.stop_app': 'device.root.stop_app',
  });

  static Set<String> get handlers => Set.unmodifiable(_permissions.keys);
  static Set<String> get knownCapabilities =>
      Set.unmodifiable(_permissions.values);

  static Set<String> permissionsFor(String handler) {
    final permission = _permissions[handler];
    return permission == null ? const {} : {permission};
  }

  static bool isMutation(String handler) =>
      _permissions.containsKey(handler) && !handler.endsWith('.get');

  static bool requiresConfirmation(String handler) =>
      _permissions.containsKey(handler) && handler.startsWith('device.root.');

  static Map<String, dynamic>? inputSchemaFor(String handler) {
    if (!_permissions.containsKey(handler)) return null;
    final Map<String, dynamic> properties;
    final List<String> required;
    switch (handler) {
      case 'device.screen.brightness.set':
        properties = {
          'value': {'type': 'integer', 'minimum': 0, 'maximum': 255},
          'mode': {
            'type': 'string',
            'enum': ['manual', 'automatic'],
          },
        };
        required = ['value'];
      case 'device.screen.timeout.set':
        properties = {
          'milliseconds': {
            'type': 'integer',
            'minimum': 15000,
            'maximum': 1800000,
          },
        };
        required = ['milliseconds'];
      case 'device.audio.volume.set':
        properties = {
          'stream': {'type': 'string', 'enum': audioStreams},
          'value': {'type': 'integer', 'minimum': 0, 'maximum': 100},
        };
        required = ['stream', 'value'];
      case 'device.audio.dnd.set':
        properties = {
          'mode': {
            'type': 'string',
            'enum': ['all', 'priority', 'none', 'alarms'],
          },
        };
        required = ['mode'];
      case 'device.settings.open':
        properties = {
          'page': {'type': 'string', 'enum': settingsPages},
          'packageName': {
            'type': 'string',
            'minLength': 3,
            'maxLength': 200,
            'pattern': r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
          },
        };
        required = ['page'];
      case 'device.root.stop_app':
        properties = {
          'packageName': {
            'type': 'string',
            'minLength': 3,
            'maxLength': 200,
            'pattern': r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
          },
        };
        required = ['packageName'];
      default:
        if (handler.endsWith('.get')) {
          properties = {};
          required = [];
        } else {
          properties = {
            'enabled': {'type': 'boolean'},
          };
          required = ['enabled'];
        }
    }
    // Return an independent tree. Manifests and provider normalizers may edit
    // their schemas without changing the host's fixed native argument catalog.
    return jsonDecode(
          jsonEncode({
            'type': 'object',
            'properties': properties,
            'required': required,
            'additionalProperties': false,
          }),
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> snapshot() async {
    try {
      return _map(
        await _channel
            .invokeMethod<Object?>('snapshot')
            .timeout(operationTimeout),
      );
    } on MissingPluginException {
      return _unavailableSnapshot('unsupported');
    } on PlatformException {
      return _unavailableSnapshot('read_failed');
    } on TimeoutException {
      return _unavailableSnapshot('read_timeout');
    }
  }

  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> args,
  ) async {
    if (!_permissions.containsKey(handler)) {
      return _result('unsupported', 'Unknown device handler.');
    }
    final owner = ToolCallCancellation.current;
    if (owner?.isCancelled() == true) {
      return _result(
        'denied',
        'The device request was cancelled before execution.',
      );
    }
    final requestId = 'device-${++_requestSequence}';
    var finished = false;
    Future<Object?>? operation;
    Future<void>? cancelRequest;
    Future<void> cancelNative() => cancelRequest ??= () async {
      try {
        await _channel
            .invokeMethod<void>('cancel', {'requestId': requestId})
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        // Cancellation during native detach still has an unknown outcome.
      }
    }();
    Future<Map<String, dynamic>> cancelledResult(String message) async {
      await cancelNative();
      final result = _result('unknown_after_timeout', message);
      // Keep the device mutation lane until Android answers the stopped
      // operation, with a bound for a detached/stalled channel. Native also
      // serializes operations and checks queued cancellation before changing.
      try {
        final reply = _map(
          await operation!.timeout(const Duration(seconds: 2)),
        );
        if (reply['state'] is Map) result['state'] = reply['state'];
        if (reply['status'] == 'denied') result['status'] = 'denied';
      } catch (_) {
        // Neither a late success nor an absent reply can establish ownership.
      }
      return result;
    }

    try {
      operation = _channel.invokeMethod<Object?>('execute', {
        'handler': handler,
        'args': args,
        'requestId': requestId,
      });
      final stopped = owner?.cancelled.then<Object?>((_) async {
        if (finished) return null;
        return cancelledResult(
          'The device request was stopped before its outcome was confirmed.',
        );
      });
      final result = _map(
        await (stopped == null
                ? operation
                : Future.any<Object?>([operation, stopped]))
            .timeout(operationTimeout),
      );
      if (owner?.isCancelled() == true) {
        return await cancelledResult(
          'The device request was stopped before its outcome was confirmed.',
        );
      }
      if (!const {
        'applied',
        'opened_settings',
        'permission_required',
        'unsupported',
        'denied',
        'failed',
        'unknown_after_timeout',
      }.contains(result['status'])) {
        return _result('failed', 'Android returned an invalid device result.');
      }
      return result;
    } on MissingPluginException {
      return _result('unsupported', 'Android device controls are unavailable.');
    } on PlatformException catch (error) {
      return _result(
        error.code == 'permission_required' ? 'permission_required' : 'failed',
        'Android could not complete the device request.',
      );
    } on TimeoutException {
      // Native cancellation stops a still-running bounded command. A timeout
      // does not prove that Android did not already accept the setting change.
      return await cancelledResult(
        'Android did not confirm the outcome before the deadline.',
      );
    } finally {
      finished = true;
    }
  }

  static Map<String, dynamic> _result(String status, String message) => {
    'status': status,
    'message': message,
    'state': _unavailableSnapshot(status),
  };

  static Map<String, dynamic> _unavailableSnapshot(String reason) => {
    for (final group in _readGroups)
      group: {
        'reasons': {'group': reason},
      },
  };

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) return {};
    Object? decode(Object? item) {
      if (item is Map) {
        return {
          for (final entry in item.entries)
            if (entry.key is String) entry.key as String: decode(entry.value),
        };
      }
      if (item is List) return item.map(decode).toList();
      return item;
    }

    return decode(value) as Map<String, dynamic>;
  }
}
