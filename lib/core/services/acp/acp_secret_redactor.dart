import 'dart:convert';

import '../../../utils/authentication_uri.dart';

import 'acp_connection.dart';
import 'acp_error_messages.dart';

/// Secrets known to one launch, removed before agent data leaves ACP.
/// Empty values are ignored; even short nonempty header values are secrets.
class AcpSecretRedactor {
  AcpSecretRedactor(
    Iterable<String> secrets, {
    this.protectAuthentication = false,
  }) {
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

  /// Subscription processes own their credentials. Recognize their output
  /// without reading a token store or adding those credentials to launch env.
  final bool protectAuthentication;

  static bool _credentialField(Object? key) =>
      key is String &&
      const {
        'accesstoken',
        'refreshtoken',
        'idtoken',
        'devicetoken',
        'devicecode',
        'usercode',
        'authorizationcode',
        'verificationcode',
        'onetimecode',
        'logincode',
        'oauthtoken',
        'bearertoken',
        'claudecodeoauthtoken',
        'authorization',
      }.contains(key.toLowerCase().replaceAll(RegExp(r'[_\s-]'), ''));

  String get _truncationMarker =>
      '$_separator${text('\n[truncated]')}$_separator';

  String text(String value) {
    if (!protectAuthentication) {
      return _pattern == null
          ? value
          : value.replaceAll(_pattern, _replacement);
    }
    final buffer = textBuffer();
    return [
      ...buffer.add(value, id: 'text'),
      ...buffer.finish(),
    ].map((part) => part.text).join();
  }

  AcpSecretTextBuffer textBuffer() => AcpSecretTextBuffer._(this);

  AcpStderrBuffer stderrBuffer() => AcpStderrBuffer._(this);

  /// Arbitrary diagnostics and tool payloads have no protocol controls.
  Object? value(Object? input) => switch (input) {
    String() => text(input),
    Map() => {
      for (final entry in input.entries)
        entry.key is String ? text(entry.key as String) : entry.key: value(
          protectAuthentication &&
                  _credentialField(entry.key) &&
                  entry.value != null
              ? _replacement
              : entry.value,
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
  /// Subscription message/thought content stays private until the translator's
  /// streaming filter: masking a prefix here would expose the following chunk.
  Object? protocol(Object? input) => _protocol(input, 'root');

  Object? _protocol(Object? input, String context) {
    if (input is List) {
      return input.map((item) => _protocol(item, context)).toList();
    }
    if (input is! Map) return value(input);
    if (protectAuthentication &&
        context == 'update' &&
        const {
          'agent_message_chunk',
          'agent_thought_chunk',
        }.contains(input['sessionUpdate'])) {
      context = 'stream-update';
    }
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
    'update' || 'stream-update' => const {
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
    'content' || 'stream-content' => const {
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
      'update' || 'stream-update' => const {
        'sessionUpdate',
        'toolCallId',
        'kind',
        'status',
        'currentModeId',
      },
      'content' || 'stream-content' => const {'type', 'mimeType'},
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
    if (context == 'stream-content' &&
        input is String &&
        const {'text', 'uri', 'title', 'name'}.contains(key)) {
      return input;
    }
    if (protectAuthentication && _credentialField(key) && input != null) {
      return _replacement;
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
      ('stream-update', 'content') => 'stream-content',
      ('update', 'entries') => 'entry',
      ('content', 'content' || 'resource') => 'content',
      ('stream-content', 'content' || 'resource') => 'stream-content',
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

/// Incremental filtering preserves text owners while withholding ambiguous
/// prefixes. Ordinary tails are emitted when the turn ends; confirmed
/// authentication bodies are discarded without retaining their contents.
class AcpSecretTextBuffer {
  AcpSecretTextBuffer._(this._redactor)
    : _authentication = _redactor.protectAuthentication
          ? _AcpAuthenticationTextBuffer(_redactor._replacement)
          : null;
  final AcpSecretRedactor _redactor;
  final _AcpAuthenticationTextBuffer? _authentication;
  String _tail = '';
  List<({String id, int length})> _spans = [];

  Set<String> get pendingIds => {
    ..._spans.map((span) => span.id),
    ...?_authentication?.pendingIds,
  };

  List<({String id, String text})> add(String chunk, {required String id}) {
    final authentication = _authentication;
    if (authentication == null) return _add(chunk, id: id);
    return [
      for (final part in authentication.add(chunk, id: id))
        ..._add(part.text, id: part.id),
    ];
  }

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

  List<({String id, String text})> finish() => [
    if (_authentication case final authentication?)
      for (final part in authentication.finish())
        ..._add(part.text, id: part.id),
    ..._add('', id: '', finishing: true),
  ];
}

enum _AcpAuthDiscard { token, jwt, url, bare, quoted, separator, value, expiry }

typedef _AcpAuthCredential = ({
  int start,
  int quote,
  int escapes,
  _AcpAuthDiscard? waiting,
});

/// Authentication evidence is recognized before known-key filtering can
/// alter it. A confirmed secret's body is discarded as it arrives; ambiguous
/// URLs/JWTs and label prefixes retain at most 2 KiB and their original owners.
class _AcpAuthenticationTextBuffer {
  _AcpAuthenticationTextBuffer(this._replacement);

  final String _replacement;
  static const _candidateLimit = 2048;
  static const _tokenPrefixes = ['sk-ant-oat', 'sk-ant-ort'];
  static const _urlPrefixes = [
    'https://',
    'http://',
    r'https:\/\/',
    r'http:\/\/',
  ];
  static const _bearerPrefixes = ['authorization: bearer', 'bearer'];
  static const _promptPrefixes = [
    'enter this one-time code',
    'enter the one-time code',
    'enter this device code',
    'enter the device code',
    'enter this user code',
    'enter the user code',
  ];
  static final _credentialPrefixes = <String>{
    for (final field in const [
      'access_token',
      'refresh_token',
      'id_token',
      'device_token',
      'device_code',
      'user_code',
      'authorization_code',
      'verification_code',
      'one_time_code',
      'login_code',
      'oauth_token',
      'bearer_token',
      'claude_code_oauth_token',
    ]) ...[
      field,
      field.replaceAll('_', ''),
      field.replaceAll('_', ' '),
      field.replaceAll('_', '-'),
    ],
    'one-time code',
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  static final _prefixes = [
    ..._tokenPrefixes,
    ..._urlPrefixes,
    ..._bearerPrefixes,
    ..._promptPrefixes,
    ..._credentialPrefixes,
    'eyj',
  ]..sort((a, b) => b.length.compareTo(a.length));

  String _tail = '';
  List<({String id, int length})> _spans = [];
  _AcpAuthDiscard? _discard;
  int _quote = 0;
  int _quoteEscapes = 0;
  int _backslashes = 0;

  Set<String> get pendingIds => _spans.map((span) => span.id).toSet();

  List<({String id, String text})> add(String chunk, {required String id}) =>
      _add(chunk, id: id);

  List<({String id, String text})> finish() =>
      _add('', id: '', finishing: true);

  static bool _space(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

  static bool _tokenUnit(int unit) =>
      unit >= 0x41 && unit <= 0x5a ||
      unit >= 0x61 && unit <= 0x7a ||
      unit >= 0x30 && unit <= 0x39 ||
      unit == 0x5f ||
      unit == 0x2d;

  static bool _urlUnit(int unit) =>
      !_space(unit) &&
      !const {
        0x22,
        0x27,
        0x28,
        0x29,
        0x3c,
        0x3e,
        0x5b,
        0x5d,
        0x60,
      }.contains(unit);

  static bool _bareUnit(int unit) =>
      _urlUnit(unit) && !const {0x2c, 0x7b, 0x7d}.contains(unit);

  static bool _possibleJwtHeader(String input, int offset) {
    // JSON permits whitespace before its opening brace, so a JWT need not
    // begin with the usual eyJ. Reject ordinary words from their first bytes.
    if (!const {0x65, 0x49, 0x43, 0x44}.contains(input.codeUnitAt(offset))) {
      return false;
    }
    var end = offset;
    while (end < input.length &&
        end - offset < 64 &&
        _tokenUnit(input.codeUnitAt(end))) {
      end++;
    }
    final complete = (end - offset) ~/ 4 * 4;
    if (complete == 0) return true;
    try {
      for (final byte in base64Url.decode(
        input.substring(offset, offset + complete),
      )) {
        if (!_space(byte)) return byte == 0x7b;
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool _jwtArtifact(String value) {
    if (value.toLowerCase().startsWith('eyj') && value.length >= 16) {
      return true;
    }
    final dot = value.indexOf('.');
    if (dot < 0) return false;
    try {
      final header = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(value.substring(0, dot))),
        ),
      );
      return header is Map &&
          (header.containsKey('alg') || header['typ'] == 'JWT');
    } on FormatException {
      return false;
    }
  }

  static bool _authenticationUrl(String value) {
    value = value.replaceAll(r'\/', '/');
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (const {
      'auth.openai.com',
      'auth0.openai.com',
      'auth.anthropic.com',
    }.contains(host)) {
      return true;
    }
    if (const {
          'claude.ai',
          'claude.com',
          'platform.claude.com',
          'console.anthropic.com',
          'platform.openai.com',
          'chat.openai.com',
          'chatgpt.com',
        }.contains(host) &&
        RegExp(r'/(?:login|oauth|auth|deviceauth)(?:/|$)').hasMatch(path)) {
      return true;
    }
    return isAuthenticationUri(uri);
  }

  /// Finds the start of a value after a recognized label. `null` is an
  /// ordinary word; an incomplete prefix is retained until the next chunk.
  static _AcpAuthCredential? _credential(
    String input,
    int position, {
    required bool bearer,
    required bool prompt,
  }) {
    var at = position;
    _AcpAuthCredential waiting(_AcpAuthDiscard state) =>
        (start: at, quote: 0, escapes: 0, waiting: state);

    if (prompt) {
      if (at < input.length &&
          !_space(input.codeUnitAt(at)) &&
          !const {0x28, 0x3a, 0x3d}.contains(input.codeUnitAt(at))) {
        return null;
      }
      while (at < input.length && _space(input.codeUnitAt(at))) {
        at++;
      }
      if (at == input.length) return waiting(_AcpAuthDiscard.value);
      // Native Codex prints an optional expiry annotation before a blank
      // line and the device code. Its prompt does not require a colon.
      if (input.codeUnitAt(at) == 0x28) {
        final close = input.indexOf(')', at + 1);
        if (close < 0) return waiting(_AcpAuthDiscard.expiry);
        at = close + 1;
        while (at < input.length && _space(input.codeUnitAt(at))) {
          at++;
        }
      }
      if (at < input.length &&
          const {0x3a, 0x3d}.contains(input.codeUnitAt(at))) {
        at++;
      }
    } else if (bearer) {
      if (at < input.length && !_space(input.codeUnitAt(at))) return null;
    } else {
      var quotedAt = at;
      while (quotedAt < input.length && input.codeUnitAt(quotedAt) == 0x5c) {
        quotedAt++;
      }
      if (quotedAt > at && quotedAt == input.length) {
        return waiting(_AcpAuthDiscard.separator);
      }
      if (at < input.length &&
          quotedAt < input.length &&
          const {0x22, 0x27}.contains(input.codeUnitAt(quotedAt))) {
        at = quotedAt + 1;
      }
      while (at < input.length && _space(input.codeUnitAt(at))) {
        at++;
      }
      if (at == input.length) {
        return waiting(_AcpAuthDiscard.separator);
      }
      if (!const {0x3a, 0x3d}.contains(input.codeUnitAt(at))) return null;
      at++;
    }
    while (at < input.length && _space(input.codeUnitAt(at))) {
      at++;
    }
    if (at == input.length) {
      return waiting(_AcpAuthDiscard.value);
    }
    var quotedAt = at;
    while (quotedAt < input.length && input.codeUnitAt(quotedAt) == 0x5c) {
      quotedAt++;
    }
    if (quotedAt > at && quotedAt == input.length) {
      return waiting(_AcpAuthDiscard.value);
    }
    final unit = input.codeUnitAt(at);
    if (quotedAt < input.length &&
        const {0x22, 0x27}.contains(input.codeUnitAt(quotedAt))) {
      return (
        start: quotedAt + 1,
        quote: input.codeUnitAt(quotedAt),
        escapes: quotedAt - at,
        waiting: null,
      );
    }
    if (!_bareUnit(unit)) return null;
    return (start: at, quote: 0, escapes: 0, waiting: null);
  }

  List<({String id, String text})> _add(
    String chunk, {
    required String id,
    bool finishing = false,
  }) {
    final input = _tail + chunk;
    final lower = input.toLowerCase();
    final spans = [
      ..._spans,
      if (chunk.isNotEmpty) (id: id, length: chunk.length),
    ];
    _tail = '';
    _spans = [];
    final output = <String, StringBuffer>{};
    var spanIndex = 0;
    var spanBegin = 0;

    String owner(int position) {
      while (position >= spanBegin + spans[spanIndex].length) {
        spanBegin += spans[spanIndex++].length;
      }
      return spans[spanIndex].id;
    }

    void emit(int begin, int end) {
      while (begin < end) {
        final partId = owner(begin);
        final partEnd = spanBegin + spans[spanIndex].length;
        final stop = end < partEnd ? end : partEnd;
        output
            .putIfAbsent(partId, StringBuffer.new)
            .write(input.substring(begin, stop));
        begin = stop;
      }
    }

    void mask(int position) {
      output.putIfAbsent(owner(position), StringBuffer.new).write(_replacement);
    }

    void retain(int position) {
      _tail = input.substring(position);
      var begin = 0;
      for (final span in spans) {
        final end = begin + span.length;
        if (end > position) {
          _spans.add((
            id: span.id,
            length: end - (begin < position ? position : begin),
          ));
        }
        begin = end;
      }
    }

    var offset = 0;
    while (offset < input.length) {
      final unit = input.codeUnitAt(offset);
      if (_discard case final discard?) {
        switch (discard) {
          case _AcpAuthDiscard.expiry:
            offset++;
            if (unit == 0x29) _discard = _AcpAuthDiscard.value;
          case _AcpAuthDiscard.separator:
            if (_space(unit)) {
              offset++;
            } else if (unit == 0x3a || unit == 0x3d) {
              offset++;
              _discard = _AcpAuthDiscard.value;
            } else {
              _discard = null;
            }
          case _AcpAuthDiscard.value:
            if (_space(unit)) {
              offset++;
            } else if (unit == 0x5c) {
              offset++;
              // Encoded JSON can escape the opening quote of a value.
              // Beyond this cap, discard conservatively as a bare value.
              if (++_backslashes > 32) _discard = _AcpAuthDiscard.bare;
            } else if (unit == 0x22 || unit == 0x27) {
              offset++;
              _quote = unit;
              _quoteEscapes = _backslashes;
              _backslashes = 0;
              _discard = _AcpAuthDiscard.quoted;
            } else {
              _discard = _AcpAuthDiscard.bare;
            }
          case _AcpAuthDiscard.quoted:
            if (unit == _quote && _backslashes == _quoteEscapes) {
              if (_quoteEscapes > 0) {
                output
                    .putIfAbsent(owner(offset), StringBuffer.new)
                    .write(r'\' * _quoteEscapes);
              }
              _discard = null;
            } else {
              _backslashes = unit == 0x5c
                  ? (_backslashes + 1) % (2 * (_quoteEscapes + 1))
                  : 0;
              offset++;
            }
          case _AcpAuthDiscard.token ||
              _AcpAuthDiscard.jwt ||
              _AcpAuthDiscard.url ||
              _AcpAuthDiscard.bare:
            final secretUnit = switch (discard) {
              _AcpAuthDiscard.token => _tokenUnit(unit),
              _AcpAuthDiscard.jwt => _tokenUnit(unit) || unit == 0x2e,
              _AcpAuthDiscard.url => _urlUnit(unit),
              _ => _bareUnit(unit),
            };
            if (secretUnit) {
              offset++;
            } else {
              _discard = null;
            }
        }
        continue;
      }

      String? prefix;
      var partial = false;
      for (final candidate in _prefixes) {
        if (lower.startsWith(candidate, offset)) {
          prefix = candidate;
          break;
        }
        if (input.length - offset < candidate.length &&
            candidate.startsWith(lower.substring(offset))) {
          partial = true;
        }
      }
      if (prefix == null && _possibleJwtHeader(input, offset)) prefix = 'jwt';
      if (prefix == null) {
        if (partial && !finishing) {
          retain(offset);
          break;
        }
        if (finishing && lower.startsWith('sk-ant-', offset)) {
          mask(offset);
          break;
        }
        emit(offset, offset + 1);
        offset++;
        continue;
      }
      if (_tokenPrefixes.contains(prefix)) {
        mask(offset);
        offset += prefix.length;
        _discard = _AcpAuthDiscard.token;
        continue;
      }
      if (_urlPrefixes.contains(prefix) || prefix == 'eyj' || prefix == 'jwt') {
        final url = _urlPrefixes.contains(prefix);
        var end = offset + (prefix == 'jwt' ? 1 : prefix.length);
        while (end < input.length &&
            (url
                ? _urlUnit(input.codeUnitAt(end))
                : _tokenUnit(input.codeUnitAt(end)) ||
                      input.codeUnitAt(end) == 0x2e)) {
          end++;
        }
        if (end == input.length && !finishing) {
          if (end - offset < _candidateLimit) {
            retain(offset);
            break;
          }
          mask(offset);
          offset = end;
          _discard = url ? _AcpAuthDiscard.url : _AcpAuthDiscard.jwt;
          continue;
        }
        final candidate = input.substring(offset, end);
        final sensitive = url
            ? _authenticationUrl(candidate)
            : _jwtArtifact(candidate);
        if (sensitive || candidate.length >= _candidateLimit) {
          mask(offset);
        } else {
          emit(offset, end);
        }
        offset = end;
        continue;
      }

      final credential = _credential(
        input,
        offset + prefix.length,
        bearer: _bearerPrefixes.contains(prefix),
        prompt: _promptPrefixes.contains(prefix),
      );
      if (credential == null || credential.waiting != null && finishing) {
        emit(offset, offset + 1);
        offset++;
        continue;
      }
      if (credential.waiting != null) {
        if (input.length - offset < _candidateLimit) {
          retain(offset);
          break;
        }
        mask(offset);
        _discard = credential.waiting;
        _backslashes = 0;
        break;
      }
      emit(offset, credential.start);
      if (credential.start == input.length) {
        // A quoted value is confirmed even when its opening quote ends the
        // chunk. Emit its marker now and discard subsequent body fragments.
        mask(credential.start - 1);
        _quote = credential.quote;
        _quoteEscapes = credential.escapes;
        _backslashes = 0;
        _discard = _AcpAuthDiscard.quoted;
        break;
      }
      mask(credential.start);
      offset = credential.start;
      _quote = credential.quote;
      _quoteEscapes = credential.escapes;
      _backslashes = 0;
      _discard = _quote == 0 ? _AcpAuthDiscard.bare : _AcpAuthDiscard.quoted;
    }
    if (finishing) {
      _discard = null;
      _backslashes = 0;
    }
    return [
      for (final entry in output.entries)
        (id: entry.key, text: entry.value.toString()),
    ];
  }
}
