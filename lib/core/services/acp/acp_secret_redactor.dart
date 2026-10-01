import 'dart:convert';

import 'acp_connection.dart';
import 'acp_error_messages.dart';

/// Secrets known to one launch, removed before agent data leaves ACP.
/// Empty values are ignored; even short nonempty header values are secrets.
class AcpSecretRedactor {
  AcpSecretRedactor(Iterable<String> secrets) {
    final values = <String>{};
    for (final secret in secrets) {
      if (secret.isEmpty) continue;
      values.add(secret);
      // OpenCode expands environment variables before parsing config JSON.
      final encoded = jsonEncode(secret);
      final jsonValue = encoded.substring(1, encoded.length - 1);
      values.add(jsonValue);
      values.add(
        jsonValue.replaceAll('{', r'\u007b').replaceAll('}', r'\u007d'),
      );
    }
    final ordered = values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    _secrets = ordered;
    _pattern = ordered.isEmpty
        ? null
        : RegExp(ordered.map(RegExp.escape).join('|'));
    const marker = '[REDACTED]';
    final runes = values.expand((value) => value.runes).toSet();
    // Separators at diagnostic cuts cannot join either side into a known
    // secret. Include escaped representations when choosing this rune.
    var scalar = 0x25a0;
    while (runes.contains(scalar)) {
      scalar++;
      if (scalar == 0xd800) scalar = 0xe000;
    }
    _separator = String.fromCharCode(scalar);
    final markerContainsSecret = _pattern?.hasMatch(marker) == true;
    if (!markerContainsSecret &&
        !runes.contains(0x5b) &&
        !runes.contains(0x5d)) {
      _replacement = marker;
    } else {
      // A visible separator absent from every secret prevents replacement
      // from joining ordinary fragments into another secret, even in streams.
      _replacement = markerContainsSecret
          ? _separator
          : '$_separator$marker$_separator';
    }
  }

  late final List<String> _secrets;
  late final RegExp? _pattern;
  late final String _replacement;
  late final String _separator;

  String get _truncationMarker =>
      '$_separator${text('\n[truncated]')}$_separator';

  String text(String value) =>
      _pattern == null ? value : value.replaceAll(_pattern, _replacement);

  AcpSecretTextBuffer textBuffer() => AcpSecretTextBuffer._(this);

  AcpStderrBuffer stderrBuffer() => AcpStderrBuffer._(this);

  /// Arbitrary diagnostics and tool payloads have no protocol controls.
  Object? value(Object? input) => switch (input) {
    String() => text(input),
    Map() => {
      for (final entry in input.entries)
        entry.key is String ? text(entry.key as String) : entry.key: value(
          entry.value,
        ),
    },
    List() => input.map(value).toList(),
    _ => input,
  };

  AcpError error(
    Object input, {
    int code = AcpError.internalError,
    String? stderr,
    AcpFailureKind? failureKind,
  }) {
    // Decide from the complete current RPC payload before masking or size
    // limits remove its only evidence. Process diagnostics are a fallback.
    final kind =
        classifyAcpFailure(input) ??
        (input is! AcpError ||
                input.code == AcpError.internalError ||
                input.code == AcpError.disconnected
            ? failureKind ??
                  (stderr == null ? null : classifyAcpFailure(stderr))
            : null);
    final rawMessage = input is AcpError ? input.message : input.toString();
    final safeReason = text(rawMessage);
    final safeData = _boundedErrorData(
      input is AcpError ? value(input.data) : null,
    );
    final safeDetails = text(
      input is AcpError && input.details != null
          ? input.details!
          : [
              safeReason,
              if (safeData != null)
                safeData is String
                    ? safeData
                    : const JsonEncoder.withIndent('  ').convert(safeData),
            ].where((part) => part.trim().isNotEmpty).join('\n\n'),
    );
    final safeMarker = _truncationMarker;
    // Reserve half the diagnostic budget for recent stderr, so large data
    // cannot displace the process's explanation of an Internal error.
    final details = stderr?.isNotEmpty == true
        ? [
            boundAcpDiagnostic(
              safeDetails,
              limit: acpErrorDetailsLimit ~/ 2 - 2,
              marker: safeMarker,
            ),
            text(stderr!),
          ].join('\n\n')
        : safeDetails;
    return AcpError(
      input is AcpError ? input.code : code,
      boundAcpDiagnostic(
        safeReason,
        limit: acpErrorMessageLimit,
        marker: safeMarker,
      ),
      safeData,
      kind,
      boundAcpDiagnostic(text(details), marker: safeMarker),
    );
  }

  Object? _boundedErrorData(Object? safeData) {
    if (safeData == null) return null;
    final encoded = jsonEncode(safeData);
    if (utf8.encode(encoded).length <= acpErrorDataLimit) return safeData;
    // JSON text has no unescaped control characters. Encoding this excerpt
    // again can at most double its bytes, keeping the data payload bounded.
    return boundAcpDiagnostic(
      text(encoded),
      limit: acpErrorDataLimit ~/ 2 - 2,
      marker: _truncationMarker,
    );
  }

  /// Preserve wire identifiers and discriminators used to route replies,
  /// updates and permission choices. Only display/payload strings are redacted.
  /// Applying replacement to serialized JSON would break ACP for headers such
  /// as "text", "s1" or "completed".
  Object? protocol(Object? input) => _protocol(input, 'root');

  Object? _protocol(Object? input, String context) {
    if (input is List) {
      return input.map((item) => _protocol(item, context)).toList();
    }
    if (input is! Map) return value(input);
    final result = <String, Object?>{
      for (final entry in input.entries)
        _schemaFields(context).contains(entry.key)
            ? entry.key as String
            : text(entry.key as String): _field(
          entry.key as String,
          entry.value,
          context,
        ),
    };
    // Routing IDs remain private controls; labels synthesized from them do not.
    final labelId = switch (context) {
      'mode' || 'auth' => input['id'],
      'option' => input['optionId'],
      _ => null,
    };
    if (result['name'] == null && labelId is String) {
      result['name'] = text(labelId);
    }
    return result;
  }

  static Set<String> _schemaFields(String context) => switch (context) {
    'root' => const {
      'protocolVersion',
      'agentCapabilities',
      'agentInfo',
      'authMethods',
      'sessionId',
      'modes',
      'stopReason',
      'usage',
      'update',
      'toolCall',
      'options',
    },
    'update' => const {
      'sessionUpdate',
      'toolCallId',
      'title',
      'kind',
      'status',
      'currentModeId',
      'rawInput',
      'rawOutput',
      'content',
      'locations',
      'entries',
    },
    'content' => const {
      'type',
      'mimeType',
      'text',
      'data',
      'uri',
      'name',
      'title',
      'description',
      'resource',
      'content',
      'path',
      'oldText',
      'newText',
    },
    'modes' => const {'currentModeId', 'availableModes'},
    'mode' || 'auth' => const {'id', 'name', 'description'},
    'option' => const {'optionId', 'name', 'kind'},
    'entry' => const {'content', 'status', 'priority'},
    'info' => const {'name', 'title', 'version'},
    'caps' => const {
      'promptCapabilities',
      'sessionCapabilities',
      'mcpCapabilities',
      'loadSession',
      'resume',
      'image',
      'audio',
      'embeddedContext',
      'http',
    },
    'usage' => const {
      'inputTokens',
      'outputTokens',
      'cachedReadTokens',
      'cachedWriteTokens',
      'totalTokens',
    },
    _ => const <String>{},
  };

  static Set<String>? _enumValues(String key, String context) => switch (key) {
    'type' => const {
      'text',
      'image',
      'audio',
      'resource',
      'resource_link',
      'content',
      'diff',
    },
    'kind' =>
      context == 'option'
          ? const {'allow_once', 'allow_always', 'reject_once', 'reject_always'}
          : const {
              'read',
              'edit',
              'delete',
              'move',
              'search',
              'execute',
              'think',
              'fetch',
              'other',
            },
    'status' => const {
      'pending',
      'in_progress',
      'completed',
      'failed',
      'cancelled',
    },
    'stopReason' => const {
      'end_turn',
      'max_tokens',
      'max_turn_requests',
      'refusal',
      'cancelled',
    },
    'sessionUpdate' => const {
      'agent_message_chunk',
      'agent_thought_chunk',
      'user_message_chunk',
      'tool_call',
      'tool_call_update',
      'plan',
      'current_mode_update',
      'available_commands_update',
      'session_info_update',
      'config_option_update',
      'usage_update',
    },
    'mimeType' => const {
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
      'image/svg+xml',
      'audio/wav',
      'audio/mpeg',
      'application/pdf',
      'text/plain',
    },
    _ => null,
  };

  Object? _field(String key, Object? input, String context) {
    // Only ACP schema fields at their actual locations are controls. An
    // arbitrary diagnostic containing a "status" or "id" is still redacted.
    final controls = switch (context) {
      'root' => const {'sessionId', 'stopReason'},
      'update' => const {
        'sessionUpdate',
        'toolCallId',
        'kind',
        'status',
        'currentModeId',
      },
      'content' => const {'type', 'mimeType'},
      'modes' => const {'currentModeId'},
      'mode' || 'auth' => const {'id'},
      'option' => const {'optionId', 'kind'},
      'entry' => const {'status'},
      _ => const <String>{},
    };
    if (controls.contains(key)) {
      final allowed = _enumValues(key, context);
      return allowed == null || allowed.contains(input) ? input : value(input);
    }
    final child = switch ((context, key)) {
      ('root', 'update' || 'toolCall') => 'update',
      ('root', 'options') => 'option',
      ('root', 'modes') => 'modes',
      ('root', 'authMethods') => 'auth',
      ('root', 'agentInfo') => 'info',
      ('root', 'agentCapabilities') => 'caps',
      ('root', 'usage') => 'usage',
      (
        'caps',
        'promptCapabilities' || 'sessionCapabilities' || 'mcpCapabilities',
      ) =>
        'caps',
      ('modes', 'availableModes') => 'mode',
      ('update', 'content') => 'content',
      ('update', 'entries') => 'entry',
      ('content', 'content' || 'resource') => 'content',
      _ => null,
    };
    return child == null ? value(input) : _protocol(input, child);
  }
}

/// Launch stderr is decoded and filtered before the transport retains its
/// bounded tail. No suffix of a secret can survive an earlier byte cut.
class AcpStderrBuffer {
  AcpStderrBuffer._(AcpSecretRedactor redactor)
    : _text = redactor.textBuffer() {
    _decoder = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      StringConversionSink.from(_StderrTextSink(_decoded)),
    );
  }

  final AcpSecretTextBuffer _text;
  late final ByteConversionSink _decoder;
  static const _rawTailLimit = 16 * 1024;
  List<int> _rawTail = [];
  StringBuffer _output = StringBuffer();
  AcpFailureKind? failureKind;

  String addBytes(List<int> bytes) {
    if (bytes.length >= _rawTailLimit) {
      _rawTail = bytes.sublist(bytes.length - _rawTailLimit);
    } else {
      _rawTail = [..._rawTail, ...bytes];
      if (_rawTail.length > _rawTailLimit) {
        _rawTail.removeRange(0, _rawTail.length - _rawTailLimit);
      }
    }
    // Classification uses the same bounded raw evidence window as stderr,
    // before masking removes its phrases. Old evidence expires with the tail.
    failureKind = classifyAcpFailure(
      utf8.decode(_rawTail, allowMalformed: true),
    );
    _output = StringBuffer();
    _decoder.add(bytes);
    return _output.toString();
  }

  void _decoded(String chunk) {
    for (final part in _text.add(chunk, id: 'stderr')) {
      _output.write(part.text);
    }
    // A possible unfinished secret prefix stays private even after exit.
    // Flushing it to diagnostics would disclose a nearly complete key.
  }
}

class _StderrTextSink implements Sink<String> {
  _StderrTextSink(this.onText);
  final void Function(String) onText;
  @override
  void add(String data) => onText(data);
  @override
  void close() {}
}

/// Incremental text replacement retains only a possible secret prefix. A tail
/// that did not complete a secret is emitted when its turn ends.
class AcpSecretTextBuffer {
  AcpSecretTextBuffer._(this._redactor);
  final AcpSecretRedactor _redactor;
  String _tail = '';
  List<({String id, int length})> _spans = [];

  Set<String> get pendingIds => _spans.map((span) => span.id).toSet();

  List<({String id, String text})> add(String chunk, {required String id}) =>
      _add(chunk, id: id);

  List<({String id, String text})> _add(
    String chunk, {
    required String id,
    bool finishing = false,
  }) {
    if (_redactor._secrets.isEmpty) {
      return chunk.isEmpty ? [] : [(id: id, text: chunk)];
    }
    final input = _tail + chunk;
    final spans = [
      ..._spans,
      if (chunk.isNotEmpty) (id: id, length: chunk.length),
    ];
    _tail = '';
    _spans = [];
    final output = <String, StringBuffer>{};
    var spanIndex = 0;
    var spanEnd = spans.isEmpty ? 0 : spans.first.length;
    var offset = 0;
    while (offset < input.length) {
      while (offset >= spanEnd) {
        spanEnd += spans[++spanIndex].length;
      }
      final owner = spans[spanIndex].id;
      // Only the final max-secret-length characters can be an unfinished
      // prefix. Avoid allocating every suffix of a large ordinary chunk.
      // A shorter complete secret may also begin a longer one: wait before
      // masking it so the longer secret's suffix cannot escape next chunk.
      if (!finishing &&
          input.length - offset < _redactor._secrets.first.length) {
        final rest = input.substring(offset);
        if (_redactor._secrets.any(
          (secret) => secret.length > rest.length && secret.startsWith(rest),
        )) {
          _tail = rest;
          var begin = 0;
          for (final span in spans) {
            final end = begin + span.length;
            if (end > offset) {
              _spans.add((
                id: span.id,
                length: end - (begin < offset ? offset : begin),
              ));
            }
            begin = end;
          }
          break;
        }
      }
      String? matched;
      for (final secret in _redactor._secrets) {
        if (input.startsWith(secret, offset)) {
          matched = secret;
          break;
        }
      }
      if (matched != null) {
        output
            .putIfAbsent(owner, StringBuffer.new)
            .write(_redactor._replacement);
        offset += matched.length;
        continue;
      }
      output.putIfAbsent(owner, StringBuffer.new).write(input[offset++]);
    }
    return [
      for (final entry in output.entries)
        (id: entry.key, text: entry.value.toString()),
    ];
  }

  List<({String id, String text})> finish() =>
      _add('', id: '', finishing: true);
}
