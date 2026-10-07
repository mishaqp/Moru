import 'dart:async';
import 'dart:convert';

import 'acp_secret_redactor.dart';
import 'acp_tool_correlation.dart';

/// The line-delimited JSON pipe to an agent process. The workspace STDIO
/// transport is one; tests use an in-memory pair.
abstract class AcpChannel {
  /// Decoded JSON messages from the agent's stdout.
  Stream<dynamic> get messages;

  /// Completes when the pipe is gone (process exit, close, error).
  Future<void> get closed;

  Future<void> send(Map<String, Object?> message);

  void close();

  /// Why the pipe broke, with the agent's stderr when there is some.
  String describeError(Object error) => error.toString();

  /// Raw bounded diagnostics, consumed and redacted inside the ACP boundary.
  String? get stderrTail => null;

  /// A diagnostic category observed before the launch's stderr was masked.
  AcpFailureKind? get stderrFailureKind => null;
}

/// A safe category retained when redaction removes a recognized phrase.
enum AcpFailureKind {
  apiKey,
  model,
  network,
  headers,
  temporaryDirectory,
  authRequired,
  accountBusy,
}

/// A JSON-RPC error from the agent, or the pipe breaking under a request.
class AcpError implements Exception {
  const AcpError(
    this.code,
    this.message, [
    this.data,
    this.failureKind,
    this.details,
  ]);

  final int code;
  final String message;
  final Object? data;
  final AcpFailureKind? failureKind;

  /// Safe original reason, diagnostic data and stderr for optional display.
  /// The connection assembles this before redaction or localization.
  final String? details;

  /// ACP's "authentication required": the agent needs a login or a key.
  static const int authRequired = -32000;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  /// Not a JSON-RPC code: the process died or the pipe closed.
  static const int disconnected = -1;

  /// Shown in the chat as it is, so only the agent's own words.
  @override
  String toString() => message;
}

const acpErrorMessageLimit = 4 * 1024;
const acpErrorDataLimit = 16 * 1024;
const acpErrorDetailsLimit = 32 * 1024;

/// Cap an already-redacted diagnostic at a UTF-8 boundary.
String boundAcpDiagnostic(
  String safe, {
  int limit = acpErrorDetailsLimit,
  String marker = '\n[truncated]',
}) {
  final bytes = utf8.encode(safe);
  if (bytes.length <= limit) return safe;
  var end = limit - utf8.encode(marker).length;
  while (end > 0 && bytes[end] & 0xc0 == 0x80) {
    end--;
  }
  return '${utf8.decode(bytes.sublist(0, end))}$marker';
}

/// Render diagnostics from an error that has already crossed the secret
/// boundary. Callers keep the short [AcpError.message] for notifications.
String? acpErrorDetails(Object error) {
  if (error is! AcpError) return boundAcpDiagnostic(error.toString());
  if (error.details?.trim().isNotEmpty == true) {
    return boundAcpDiagnostic(error.details!);
  }
  final data = error.data;
  return boundAcpDiagnostic(
    [
      error.message,
      if (data != null)
        data is String
            ? data
            : const JsonEncoder.withIndent('  ').convert(data),
    ].where((part) => part.trim().isNotEmpty).join('\n\n'),
  );
}

/// Answers a request the agent sends to Moru (permission, file access).
/// Return the JSON result; throw [AcpError] to answer with an error.
typedef AcpRequestHandler =
    Future<Object?> Function(String method, Map<String, Object?> params);

typedef AcpNotificationHandler =
    void Function(String method, Map<String, Object?> params);

/// JSON-RPC 2.0 in both directions over an [AcpChannel]: Moru calls the
/// agent, and the agent calls back while a prompt runs.
class AcpConnection {
  AcpConnection(
    this._channel, {
    required this.onRequest,
    required this.onNotification,
    this.redactor,
    this.onToolCorrelation,
  }) {
    _subscription = _channel.messages.listen(
      _receive,
      onError: (Object error) => _fail(error),
      onDone: () => _fail(StateError('agent pipe closed')),
    );
    unawaited(_channel.closed.then((_) => _fail(StateError('agent exited'))));
  }

  final AcpChannel _channel;
  final AcpSecretRedactor? redactor;
  final void Function(String sessionId, AcpToolCorrelation correlation)?
  onToolCorrelation;
  final AcpRequestHandler onRequest;
  final AcpNotificationHandler onNotification;
  late final StreamSubscription<dynamic> _subscription;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final Completer<void> _done = Completer<void>();
  int _nextId = 1;
  AcpError? _failure;

  /// Completes once the agent is gone; [failure] then says why.
  Future<void> get done => _done.future;
  AcpError? get failure => _failure;
  bool get isOpen => _failure == null;

  /// Calls [method] and waits for its result object (`{}` for a null one).
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final failure = _failure;
    if (failure != null) return Future.error(failure);
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    unawaited(
      _channel
          .send({
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
            'params': params,
          })
          .catchError((Object error) => _fail(error)),
    );
    return completer.future;
  }

  Future<void> notify(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_failure != null) return;
    try {
      await _channel.send({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      });
    } catch (error) {
      _fail(error);
      throw _failure!;
    }
  }

  void close() {
    _fail(StateError('closed by Moru'));
    _channel.close();
  }

  void _receive(dynamic message) {
    if (message is! Map) return;
    final map = Map<String, Object?>.from(message);
    final method = map['method'];
    final id = map['id'];
    if (method is String) {
      _correlate(method, map['params']);
      final params = map['params'] is Map
          ? Map<String, Object?>.from(
              redactor?.protocol(map['params']) as Map? ?? map['params'] as Map,
            )
          : <String, Object?>{};
      if (id == null) {
        onNotification(method, params);
      } else {
        unawaited(_answer(id, method, params));
      }
      return;
    }
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = map['error'];
    if (error is Map) {
      final message = error['message'];
      final rawFailure = AcpError(
        (error['code'] as num?)?.toInt() ?? AcpError.internalError,
        message is String && message.trim().isNotEmpty
            ? message
            : 'agent error',
        error['data'],
      );
      // Current protocol evidence takes precedence over this process's older
      // stderr. Stderr supplies a category for generic Internal errors only.
      final failure = (redactor ?? AcpSecretRedactor(const [])).error(
        rawFailure,
        stderr: _channel.stderrTail,
        failureKind: _channel.stderrFailureKind,
      );
      completer.completeError(failure);
      return;
    }
    final result = map['result'];
    completer.complete(
      result is Map
          ? Map<String, Object?>.from(
              redactor?.protocol(result) as Map? ?? result,
            )
          : <String, Object?>{},
    );
  }

  void _correlate(String method, Object? params) {
    if (onToolCorrelation == null || params is! Map) return;
    final sessionId = params['sessionId'];
    if (sessionId is! String) return;
    final update = switch (method) {
      'session/update' => params['update'],
      'session/request_permission' => params['toolCall'],
      _ => null,
    };
    if (update is! Map) return;
    if (method == 'session/update' &&
        update['sessionUpdate'] != 'tool_call' &&
        update['sessionUpdate'] != 'tool_call_update') {
      return;
    }
    final correlation = AcpToolCorrelation.fromUpdate(update);
    if (correlation != null) onToolCorrelation!(sessionId, correlation);
  }

  Future<void> _answer(
    Object id,
    String method,
    Map<String, Object?> params,
  ) async {
    Map<String, Object?> reply;
    try {
      final result = await onRequest(method, params);
      reply = {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on AcpError catch (error) {
      reply = {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': error.code, 'message': error.message},
      };
    } catch (error) {
      reply = {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': AcpError.internalError, 'message': '$error'},
      };
    }
    if (_failure != null) return;
    try {
      await _channel.send(reply);
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (_failure != null) return;
    _failure = error is AcpError
        ? error
        : AcpError(AcpError.disconnected, _channel.describeError(error));
    _failure = (redactor ?? AcpSecretRedactor(const [])).error(
      _failure!,
      failureKind: _channel.stderrFailureKind,
    );
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(_failure!);
    }
    unawaited(_subscription.cancel());
    if (!_done.isCompleted) _done.complete();
  }
}
