import 'dart:convert';

import 'chat_api_helpers.dart';
import 'generation/spend_round_control.dart';
import 'stream/stream_chunk.dart';
import 'stream/stream_chunk_emit.dart';

typedef ToolArgumentSanitizer =
    Map<String, dynamic> Function(String name, Map<String, dynamic> arguments);

/// Keeps the runtime handler's raw arguments separate from copies published to
/// the model, stream consumers, and persisted provider continuation state.
abstract final class ToolCallArgumentPrivacy {
  static final _sanitizers = Expando<ToolArgumentSanitizer>();

  static bool hasPolicy(ToolCallHandler? handler) =>
      handler != null && _sanitizers[handler] != null;

  static ToolCallHandler register(
    ToolCallHandler handler,
    ToolArgumentSanitizer sanitizer,
  ) {
    _sanitizers[handler] = sanitizer;
    return handler;
  }

  static ToolCallHandler propagate(
    ToolCallHandler source,
    ToolCallHandler target,
  ) {
    final sanitizer = _sanitizers[source];
    if (sanitizer != null) _sanitizers[target] = sanitizer;
    return target;
  }

  static Map<String, dynamic> argumentsForModel(
    ToolCallHandler? handler,
    String name,
    Map<String, dynamic> arguments,
  ) => handler == null
      ? arguments
      : _sanitizers[handler]?.call(name, arguments) ?? arguments;

  static String _textForModel(ToolCallHandler? handler, String text) =>
      argumentsForModel(handler, '__mcp_private_name__', {
            'value': text,
          }).values.single
          as String;

  static String nameForModel(ToolCallHandler? handler, String name) {
    final safeName = _textForModel(handler, name);
    // Bracketed redaction markers are invalid provider function names. The
    // call id still pairs this rejected attempted call with its safe error.
    return safeName == name ? name : 'mcp_private_tool';
  }

  static EmitToolCall callForModel(
    ToolCallHandler handler,
    EmitToolCall call,
  ) => emitToolCall(
    id: call.id,
    name: nameForModel(handler, call.name),
    arguments: argumentsForModel(handler, call.name, call.arguments),
    metadata: protocolValue(handler, call.metadata) as Map<String, dynamic>?,
    providerCallId: call.providerCallId,
  );

  /// Copies protocol tool blocks too: Claude stores `tool_use.input`, Google
  /// echoes `functionCall.args`, and OpenAI echoes JSON `function.arguments`.
  static Object? protocolValue(ToolCallHandler? handler, Object? value) {
    if (handler == null || _sanitizers[handler] == null) return value;
    if (value is List) {
      return [for (final item in value) protocolValue(handler, item)];
    }
    if (value is! Map) return value;
    final copy = <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): protocolValue(handler, entry.value),
    };
    final name = copy['name'];
    if (copy['_kelivo_claude_turn'] case final String payload) {
      try {
        copy['_kelivo_claude_turn'] = jsonEncode(
          protocolValue(handler, jsonDecode(payload)),
        );
      } catch (_) {}
    }
    if (name is String) {
      copy['name'] = nameForModel(handler, name);
      for (final key in ['input', 'args', 'arguments']) {
        final raw = copy[key];
        if (raw is Map) {
          copy[key] = argumentsForModel(
            handler,
            name,
            raw.cast<String, dynamic>(),
          );
        } else if (key == 'arguments' && raw is String) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              copy[key] = jsonEncode(
                argumentsForModel(
                  handler,
                  name,
                  decoded.cast<String, dynamic>(),
                ),
              );
            }
          } catch (_) {
            // A malformed tool argument string cannot safely be published.
            copy[key] = '{}';
          }
        }
      }
    }
    return copy;
  }

  /// Input fragments must remain private until the complete JSON is known:
  /// redacting each fragment independently can expose split keys or values.
  static Stream<StreamChunk> publishStream(
    Stream<StreamChunk> source,
    ToolCallHandler? handler,
  ) async* {
    if (handler == null || _sanitizers[handler] == null) {
      yield* source;
      return;
    }
    final names = <String, String>{};
    final inputs = <String, StringBuffer>{};
    Map<String, dynamic>? metadata(Map<String, dynamic>? value) =>
        protocolValue(handler, value) as Map<String, dynamic>?;
    try {
      await for (final chunk in source) {
        switch (chunk) {
          case ToolCallStart():
            names[chunk.id] = chunk.toolName;
            yield ToolCallStart(
              id: chunk.id,
              toolName: '',
              metadata: metadata(chunk.metadata),
            );
          case ToolCallDelta():
            names[chunk.id] = (names[chunk.id] ?? '') + chunk.toolNameDelta;
            if (chunk.inputDelta.isNotEmpty) {
              (inputs[chunk.id] ??= StringBuffer()).write(chunk.inputDelta);
            }
            if (chunk.metadata != null) {
              yield ToolCallDelta(
                id: chunk.id,
                metadata: metadata(chunk.metadata),
              );
            }
          case ToolCallEnd():
            final name = names[chunk.id] ?? '';
            if (name.isNotEmpty) {
              yield ToolCallDelta(
                id: chunk.id,
                toolNameDelta: nameForModel(handler, name),
              );
            }
            final input = inputs.remove(chunk.id);
            if (input != null) {
              Map<String, dynamic> arguments = {};
              try {
                arguments = (jsonDecode(input.toString()) as Map)
                    .cast<String, dynamic>();
              } catch (_) {}
              yield ToolCallDelta(
                id: chunk.id,
                inputDelta: jsonEncode(
                  argumentsForModel(handler, names[chunk.id] ?? '', arguments),
                ),
              );
            }
            names.remove(chunk.id);
            yield chunk;
          case ToolCallResult():
            yield ToolCallResult(
              id: chunk.id,
              output: chunk.output,
              metadata: metadata(chunk.metadata),
            );
          case RetryPending():
            yield RetryPending(
              attempt: chunk.attempt,
              maxRetries: chunk.maxRetries,
              delay: chunk.delay,
              errorText: _textForModel(handler, chunk.errorText),
              retryAt: chunk.retryAt,
            );
          case ProviderArtifact():
            Object? payload;
            try {
              payload = jsonDecode(chunk.payload);
            } catch (_) {
              yield chunk;
              continue;
            }
            yield ProviderArtifact(
              kind: chunk.kind,
              payload: jsonEncode(protocolValue(handler, payload)),
            );
          default:
            yield chunk;
        }
      }
    } catch (error, stack) {
      final rawText = error.toString();
      final safeText = _textForModel(handler, rawText);
      if (safeText == rawText) rethrow;
      if (error is SpendLimitExceeded) {
        Error.throwWithStackTrace(SpendLimitExceeded(safeText), stack);
      }
      Error.throwWithStackTrace(_PrivateProviderError(safeText), stack);
    }
    // Incomplete arguments on cancellation/error are intentionally discarded.
  }
}

final class _PrivateProviderError implements Exception {
  const _PrivateProviderError(this.message);
  final String message;
  @override
  String toString() => message;
}
