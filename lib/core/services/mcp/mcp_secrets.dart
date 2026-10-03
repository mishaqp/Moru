import '../../providers/mcp_provider.dart';
import '../acp/acp_secret_redactor.dart';
import '../logging/log_redactor.dart';

/// MCP credentials never belong in a model result or an approval description.
/// Reuses the launch redactor, including escaped and URL-encoded values.
class McpSecrets {
  McpSecrets(McpServerConfig server, {Iterable<String> extra = const []}) {
    final values = <String>{...privateFields(server).values, ...extra};
    var privateNext = false;
    for (final arg in [server.command ?? '', ...server.args]) {
      if (privateNext && !arg.startsWith('-')) values.add(arg);
      final split = arg.indexOf('=');
      final key = split < 0 ? arg : arg.substring(0, split);
      privateNext = key.startsWith('-') && sensitiveName(key);
      if (privateNext && split >= 0) values.add(arg.substring(split + 1));
      for (final match in RegExp(r'https?://[^\s]+').allMatches(arg)) {
        values.addAll(_urlSecrets(match[0]!));
      }
    }
    values.addAll(_urlSecrets(server.url));
    for (final value in values.toList()) {
      if (value.startsWith('Bearer ') || value.startsWith('Basic ')) {
        values.add(value.substring(value.indexOf(' ') + 1));
      }
    }
    redactor = AcpSecretRedactor([
      for (final value in values.where((v) => v.isNotEmpty)) ...[
        value,
        Uri.encodeComponent(value),
        Uri.encodeQueryComponent(value),
      ],
    ]);
  }

  late final AcpSecretRedactor redactor;
  static final placeholder = RegExp(r'\{\{([A-Za-z_][A-Za-z0-9_]{0,63})\}\}');
  static bool sensitiveName(String value) => RegExp(
    r'key|token|secret|password|passwd|auth|cookie|credential|signature|session|(?:^|[-_])(sig|pass|pwd|code)(?:$|[-_])',
    caseSensitive: false,
  ).hasMatch(value);

  static bool isSecret(String name, String value) =>
      sensitiveName(name) || LogRedactor.looksLikeSecret(value);

  static bool _privateProvenance(String name, String value) {
    if (name.startsWith('env:') || name.startsWith('header:')) {
      return isSecret(name.substring(name.indexOf(':') + 1), value);
    }
    return true;
  }

  static final _assignment = RegExp(
    r'''(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\+?=((?:"(?:\\.|[^"\\])*"|'[^']*'|\\.|[^\s;|&<>'"\\])*)''',
  );

  static String _assignmentValue(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Retain private provenance when a field changes: cached tool descriptions
  /// and delayed connection errors can still contain the previous credential.
  static Map<String, String> privateFields(
    McpServerConfig server, {
    Map<String, String> retained = const {},
  }) {
    final fields = <String, String>{
      for (final entry in retained.entries)
        if (_privateProvenance(entry.key, entry.value)) entry.key: entry.value,
      for (final entry in server.managedSecrets.entries)
        if (_privateProvenance(entry.key, entry.value)) entry.key: entry.value,
      for (final entry in server.env.entries)
        if (isSecret(entry.key, entry.value)) 'env:${entry.key}': entry.value,
      for (final entry in server.headers.entries)
        if (isSecret(entry.key, entry.value))
          'header:${entry.key}': entry.value,
      for (final entry in _urlSecrets(server.url).indexed)
        'url:${entry.$1}': entry.$2,
      for (var i = 0; i < server.args.length; i++)
        if (i > 0 &&
            server.args[i - 1].startsWith('-') &&
            sensitiveName(server.args[i - 1]))
          'arg:$i': server.args[i]
        else if (server.args[i].startsWith('-') &&
            server.args[i].contains('=') &&
            sensitiveName(server.args[i].split('=').first))
          'arg:$i': server.args[i].substring(server.args[i].indexOf('=') + 1),
      for (final arg in server.args.indexed)
        for (final match in _assignment.allMatches(arg.$2))
          if (sensitiveName(match[1]!))
            'arg:${arg.$1}:${match.start}': _assignmentValue(match[2]!),
      if (server.oauth case final oauth?) ...{
        'oauth:accessToken': oauth.accessToken,
        'oauth:authorization': oauth.authorizationHeader,
        if (oauth.refreshToken != null)
          'oauth:refreshToken': oauth.refreshToken!,
        if (oauth.clientSecret != null)
          'oauth:clientSecret': oauth.clientSecret!,
      },
      if (server.oauthClient?.clientSecret case final secret?)
        'oauthClient:clientSecret': secret,
    };
    var index = 0;
    for (final entry in [
      ...server.managedSecrets.entries,
      ...retained.entries,
    ]) {
      if (!_privateProvenance(entry.key, entry.value)) continue;
      final value = entry.value;
      if (value.isEmpty || fields.containsValue(value)) continue;
      while (fields.containsKey('retained:$index')) {
        index++;
      }
      fields['retained:${index++}'] = value;
    }
    return fields;
  }

  static Iterable<String> _urlSecrets(
    String value, {
    bool redactPath = true,
  }) sync* {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return;
    }
    if (uri.userInfo.isNotEmpty) {
      yield uri.userInfo;
      for (final part in uri.userInfo.split(':')) {
        yield Uri.decodeComponent(part);
      }
    }
    for (final entry in uri.queryParametersAll.entries) {
      if (sensitiveName(entry.key)) yield* entry.value;
    }
    // Imported endpoints may carry an opaque credential in a path (for
    // example Zapier). Only conventional public route segments are disclosed.
    for (final segment in redactPath ? uri.pathSegments : <String>[]) {
      if (segment.isNotEmpty &&
          !const {
            'mcp',
            'sse',
            'api',
            'rpc',
            'http',
            'v1',
            'v2',
            'v3',
          }.contains(segment)) {
        yield segment;
      }
    }
  }

  String text(String value) =>
      LogRedactor.redactDiagnosticText(redactor.text(value));
  Object? value(Object? input) => switch (input) {
    String() => text(input),
    Map() => {
      for (final entry in input.entries)
        text(entry.key.toString()): value(entry.value),
    },
    List() => input.map(value).toList(),
    _ => input,
  };

  /// Accept ordinary values; credentials request private user input instead.
  /// {{NAME}} is the only credential accepted in args or URLs.
  static bool containsLiteralSecret(Map<String, dynamic> config) {
    for (final field in ['env', 'headers']) {
      final map = config[field];
      if (map is Map &&
          map.entries.any(
            (e) =>
                e.value is String &&
                (e.value as String).isNotEmpty &&
                isSecret(e.key.toString(), e.value as String),
          )) {
        return true;
      }
    }
    String withoutPlaceholders(String input) =>
        input.replaceAll(placeholder, '');
    bool privateLiteral(String input) => withoutPlaceholders(input).isNotEmpty;
    var privateNext = false;
    for (final arg in [
      config['command'],
      ...?((config['args'] is List) ? config['args'] as List : null),
    ].whereType<String>()) {
      for (final match in _assignment.allMatches(arg)) {
        if (sensitiveName(match[1]!) &&
            privateLiteral(_assignmentValue(match[2]!))) {
          return true;
        }
      }
      if (privateNext && privateLiteral(arg)) return true;
      final split = arg.indexOf('=');
      final key = split < 0 ? arg : arg.substring(0, split);
      privateNext = key.startsWith('-') && sensitiveName(key);
      if (privateNext && split >= 0) {
        if (privateLiteral(arg.substring(split + 1))) return true;
        privateNext = false;
        continue;
      }
      if (_urlSecrets(arg, redactPath: false).any(privateLiteral)) return true;
      final plain = withoutPlaceholders(arg);
      final diagnostics = withoutPlaceholders(
        arg.replaceAllMapped(
          _assignment,
          (match) => sensitiveName(match[1]!) ? '' : match[0]!,
        ),
      ).replaceAll(RegExp(r'https?://[^\s]+'), '');
      if (LogRedactor.redactBody(plain) != plain ||
          LogRedactor.redactDiagnosticText(diagnostics) != diagnostics) {
        return true;
      }
    }
    for (final field in ['url', 'baseUrl']) {
      final input = config[field];
      if (input is! String) continue;
      final uri = Uri.tryParse(input);
      if (uri == null) continue;
      if (uri.userInfo.isNotEmpty &&
          uri.userInfo
              .split(':')
              .any((part) => privateLiteral(Uri.decodeComponent(part)))) {
        return true;
      }
      for (final entry in uri.queryParametersAll.entries) {
        if (sensitiveName(entry.key) && entry.value.any(privateLiteral)) {
          return true;
        }
      }
    }
    return false;
  }
}
