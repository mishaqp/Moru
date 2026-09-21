import 'dart:async';

import 'package:flutter/services.dart';

const String kLiteRtMethodChannel = 'app.litert';
const String kLiteRtEventChannel = 'app.litert/events';

/// One event from the native LiteRT-LM engine, decoded from the raw
/// `app.litert/events` payload. [requestId] is only set on the events that
/// belong to a specific generation (`textDelta`/`done`/`error`); an
/// `engineState` change has none.
sealed class LiteRtEvent {
  const LiteRtEvent();

  factory LiteRtEvent.fromMap(Map<Object?, Object?> map) {
    switch (map['type']) {
      case 'textDelta':
        return LiteRtTextDelta(
          requestId: (map['requestId'] ?? '').toString(),
          text: (map['text'] ?? '').toString(),
        );
      case 'done':
        return LiteRtDone(requestId: (map['requestId'] ?? '').toString());
      case 'error':
        return LiteRtError(
          requestId: (map['requestId'] ?? '').toString(),
          message: (map['message'] ?? '').toString(),
          cancelled: map['cancelled'] == true,
        );
      case 'engineState':
        return LiteRtEngineStateChanged((map['state'] ?? '').toString());
      default:
        return LiteRtUnknownEvent(Map<String, Object?>.from(map));
    }
  }
}

final class LiteRtTextDelta extends LiteRtEvent {
  const LiteRtTextDelta({required this.requestId, required this.text});
  final String requestId;
  final String text;
}

final class LiteRtDone extends LiteRtEvent {
  const LiteRtDone({required this.requestId});
  final String requestId;
}

final class LiteRtError extends LiteRtEvent {
  const LiteRtError({
    required this.requestId,
    required this.message,
    required this.cancelled,
  });
  final String requestId;
  final String message;
  final bool cancelled;
}

final class LiteRtEngineStateChanged extends LiteRtEvent {
  const LiteRtEngineStateChanged(this.state);
  final String state;
}

final class LiteRtUnknownEvent extends LiteRtEvent {
  const LiteRtUnknownEvent(this.raw);
  final Map<String, Object?> raw;
}

/// Thrown for native-side failures reported through a `MethodChannel`
/// error (`PlatformException`), normalized to the small set of error codes
/// [LiteRtEngineManager] on the Kotlin side actually returns.
class LiteRtException implements Exception {
  const LiteRtException(this.code, this.message);
  final String code;
  final String? message;

  @override
  String toString() => 'LiteRtException($code${message == null ? '' : ': $message'})';
}

/// Thin typed client over the `app.litert` / `app.litert/events` channels.
/// Mirrors `WorkspaceChannel`'s shape. Never carries model weight bytes --
/// only file paths, ids, small config values, and generated text.
class LiteRtChannel {
  LiteRtChannel({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods = methodChannel ?? const MethodChannel(kLiteRtMethodChannel),
      _events = eventChannel ?? const EventChannel(kLiteRtEventChannel);

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<LiteRtEvent>? _eventStream;

  Stream<LiteRtEvent> get events {
    return _eventStream ??= _events.receiveBroadcastStream().map(
      (raw) => LiteRtEvent.fromMap(raw as Map<Object?, Object?>),
    );
  }

  Future<T> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args) as T;
    } on PlatformException catch (e) {
      throw LiteRtException(e.code, e.message);
    }
  }

  Future<Map<Object?, Object?>> status() =>
      _invoke<Map<Object?, Object?>>('status');

  /// Returns the backend actually used ("cpu" or "gpu" -- may differ from
  /// [backend] if GPU initialization failed and the engine fell back).
  Future<String> loadModel({
    required String modelPath,
    required String backend,
    String? cacheDir,
    int? maxNumTokens,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>('loadModel', {
      'modelPath': modelPath,
      'backend': backend,
      if (cacheDir != null) 'cacheDir': cacheDir,
      if (maxNumTokens != null) 'maxNumTokens': maxNumTokens,
    });
    return (result['backend'] ?? backend).toString();
  }

  Future<void> unloadModel() => _invoke<void>('unloadModel');

  Future<void> startConversation({
    required String conversationToken,
    String? systemInstruction,
    required List<(String role, String text)> initialMessages,
    double? temperature,
    int? topK,
    double? topP,
  }) => _invoke<void>('startConversation', {
    'conversationToken': conversationToken,
    if (systemInstruction != null) 'systemInstruction': systemInstruction,
    'initialMessages': [
      for (final (role, text) in initialMessages) {'role': role, 'text': text},
    ],
    if (temperature != null) 'temperature': temperature,
    if (topK != null) 'topK': topK,
    if (topP != null) 'topP': topP,
  });

  Future<void> sendMessage({
    required String requestId,
    required String conversationToken,
    required String text,
  }) => _invoke<void>('sendMessage', {
    'requestId': requestId,
    'conversationToken': conversationToken,
    'text': text,
  });

  /// Returns whether [requestId] was actually the active generation.
  Future<bool> cancel(String requestId) =>
      _invoke<bool>('cancel', {'requestId': requestId});
}
