import 'dart:convert';

import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:crypto/crypto.dart';

import '../../providers/mcp_provider.dart';
import '../logging/log_redactor.dart';
import '../acp/acp_secret_redactor.dart';
import '../../../utils/authentication_uri.dart';
import 'mcp_secrets.dart';

/// Captures actual credentials before awaiting a server and adds live values
/// afterwards, so rotation or removal cannot expose the previous value.
class McpToolPrivacy {
  McpToolPrivacy(McpProvider provider) {
    capture(provider);
  }

  final Set<String> _knownSecrets = {};
  AcpSecretRedactor _known = AcpSecretRedactor(const []);
  final Set<McpServerConfig> _captured = {};
  final Map<String, McpServerConfig> _publicServers = {};

  void capture(McpProvider provider) {
    for (final server in [...provider.configuredServers, ...provider.servers]) {
      _publicServers[server.id] = server;
      if (!_captured.add(server)) continue;
      // An arbitrary endpoint route such as /object is not a credential.
      // Actual private placeholder inputs retain their own managed provenance.
      // Authentication query parameters and userInfo remain in these URLs.
      final credentialServer = server.copyWith(
        url: _withoutEndpointPath(server.url),
        command: server.command == null
            ? null
            : _withoutEndpointPaths(server.command!),
        args: server.args.map(_withoutEndpointPaths).toList(),
        managedSecrets: {
          for (final entry in server.managedSecrets.entries)
            if (!entry.key.startsWith('url:')) entry.key: entry.value,
        },
      );
      final sources = <String>{
        ...McpSecrets.privateFields(credentialServer).values,
        ...McpSecrets.urlCredentialValues(server.url),
      };
      for (final arg in [server.command ?? '', ...server.args]) {
        for (final match in RegExp(r'https?://[^\s]+').allMatches(arg)) {
          sources.addAll(
            McpSecrets.privateFields(
              credentialServer.copyWith(url: _withoutEndpointPath(match[0]!)),
            ).values,
          );
          sources.addAll(McpSecrets.urlCredentialValues(match[0]!));
        }
      }
      for (final secret
          in sources.where((value) => value.isNotEmpty).toList()) {
        if (secret.startsWith('Bearer ') || secret.startsWith('Basic ')) {
          sources.add(secret.substring(secret.indexOf(' ') + 1));
        }
      }
      _knownSecrets.addAll(
        sources.where(
          (value) =>
              value.isNotEmpty &&
              McpSecrets.placeholder.stringMatch(value) != value,
        ),
      );
    }
    // One replacement alphabet protects old and new short values together.
    _known = AcpSecretRedactor([
      for (final secret in _knownSecrets) ...[
        secret,
        Uri.encodeComponent(secret),
        Uri.encodeQueryComponent(secret),
      ],
    ]);
  }

  static String _withoutEndpointPath(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return input;
    }
    return uri.replace(path: '/mcp').toString();
  }

  static String _withoutEndpointPaths(String input) => input.replaceAllMapped(
    RegExp(r'https?://[^\s]+'),
    (match) => _withoutEndpointPath(match[0]!),
  );

  static final _tokenShape = RegExp(
    r'(?<![A-Za-z0-9_-])(?:sk-ant-|sk-|AIza|xai-|gsk_|hf_|AKIA)[A-Za-z0-9_-]+',
  );
  static final _authScheme = RegExp(
    r'^(?:Bearer|Basic|Token)\s+\S+(?:\s*)$',
    caseSensitive: false,
  );
  static final _authField = RegExp(
    r'''(?<![A-Za-z0-9_-])(["']?([A-Za-z0-9_-]+)["']?\s*[:=]\s*)(\{\{[A-Za-z_][A-Za-z0-9_]{0,63}\}\}|"(?:\\.|[^"\\])*"|'[^']*'|[^,;\r\n}\]&]+)''',
  );

  String text(String input) {
    input = _known.text(input);
    try {
      final decoded = jsonDecode(input);
      if (decoded is Map || decoded is List) {
        final safe = _argumentValue(decoded);
        // Preserve byte-for-byte business JSON when no credential changed.
        return jsonEncode(safe) == jsonEncode(decoded)
            ? input
            : jsonEncode(safe);
      }
    } catch (_) {}
    if (_authScheme.hasMatch(input)) return _known.text('[REDACTED]');
    input = input.replaceAll(_tokenShape, '[REDACTED]');
    input = input.replaceAllMapped(RegExp(r'https?://[^\s"<>]+'), (match) {
      final url = match[0]!;
      final uri = Uri.tryParse(url);
      if (uri != null &&
          !uri.hasFragment &&
          !isAuthenticationUri(uri.replace(query: '')) &&
          McpSecrets.placeholder.hasMatch(url) &&
          !McpSecrets.containsLiteralSecret({'url': url})) {
        return url;
      }
      if (uri != null && isAuthenticationUri(uri)) return '[REDACTED]';
      return LogRedactor.redactUrl(url) != url
          ? LogRedactor.redactDiagnosticText(url)
          : url;
    });
    return _known.text(
      input.replaceAllMapped(
        _authField,
        (match) =>
            _credentialFields.contains(_fieldName(match[2])) &&
                McpSecrets.placeholder.stringMatch(match[3]!) != match[3]
            ? '${match[1]}"[REDACTED]"'
            : match[0]!,
      ),
    );
  }

  Object? value(Object? input) => _argumentValue(input);

  McpToolConfig tool(McpToolConfig input) => input.copyWith(
    description: input.description == null ? null : text(input.description!),
    schema: input.schema == null
        ? null
        : _schema(input.schema) as Map<String, dynamic>,
    params: [
      for (final param in input.params)
        McpParamSpec(
          name: text(param.name),
          required: param.required,
          type: param.type,
          defaultValue: value(param.defaultValue),
        ),
    ],
  );

  static const _schemaKeys = {
    r'$schema',
    r'$id',
    r'$anchor',
    r'$dynamicAnchor',
    r'$ref',
    r'$dynamicRef',
    r'$defs',
    'definitions',
    'type',
    'format',
    'title',
    'description',
    'default',
    'examples',
    'enum',
    'const',
    'properties',
    'patternProperties',
    'additionalProperties',
    'unevaluatedProperties',
    'required',
    'items',
    'prefixItems',
    'additionalItems',
    'unevaluatedItems',
    'allOf',
    'anyOf',
    'oneOf',
    'not',
    'if',
    'then',
    'else',
    'contains',
    'dependentSchemas',
    'dependencies',
    'dependentRequired',
    'propertyNames',
    'minimum',
    'maximum',
    'exclusiveMinimum',
    'exclusiveMaximum',
    'multipleOf',
    'minLength',
    'maxLength',
    'pattern',
    'minItems',
    'maxItems',
    'uniqueItems',
    'minContains',
    'maxContains',
    'minProperties',
    'maxProperties',
    'readOnly',
    'writeOnly',
    'deprecated',
    'nullable',
    'propertyOrdering',
  };
  static const _schemaTypes = {
    'object',
    'array',
    'string',
    'number',
    'integer',
    'boolean',
    'null',
  };

  Object? _schema(Object? input) {
    if (input is List) return input.map(_schema).toList();
    if (input is! Map) return value(input);
    return <String, dynamic>{
      for (final entry in input.entries)
        _schemaKeys.contains(entry.key)
            ? entry.key.toString()
            : text(entry.key.toString()): switch (entry.key) {
          'type' =>
            entry.value is String && _schemaTypes.contains(entry.value)
                ? entry.value
                : entry.value is List
                ? [
                    for (final type in entry.value as List)
                      _schemaTypes.contains(type) ? type : value(type),
                  ]
                : value(entry.value),
          'properties' ||
          'patternProperties' ||
          r'$defs' ||
          'definitions' ||
          'dependentSchemas' =>
            entry.value is Map
                ? {
                    for (final property in (entry.value as Map).entries)
                      text(property.key.toString()): _schema(property.value),
                  }
                : value(entry.value),
          'default' ||
          'enum' ||
          'const' ||
          'examples' ||
          'required' ||
          'propertyOrdering' => value(entry.value),
          _ => _schema(entry.value),
        },
    };
  }

  /// Preserve transport fields and discriminators even when a short actual
  /// credential happens to equal a protocol word such as "text" or "content".
  mcp.CallToolResult result(mcp.CallToolResult input) => mcp.CallToolResult(
    [for (final content in input.content) _content(content)],
    structuredContent: input.structuredContent == null
        ? null
        : (value(input.structuredContent) as Map).cast<String, dynamic>(),
    isStreaming: input.isStreaming,
    isError: input.isError,
  );

  Map<String, dynamic>? _annotations(Map<String, dynamic>? input) =>
      input == null ? null : (value(input) as Map).cast<String, dynamic>();

  static final _binaryEncoding = RegExp(
    r'^(?:[A-Za-z0-9+/_-]{4})*(?:[A-Za-z0-9+/_-]{2}(?:==)?|[A-Za-z0-9+/_-]{3}=?)?$',
  );
  bool _privateBinary(String? input) =>
      input != null &&
      (_knownSecrets.contains(input) ||
          (!_binaryEncoding.hasMatch(input) && text(input) != input));
  mcp.TextContent get _omittedMedia =>
      mcp.TextContent(text: text('Private MCP media was omitted.'));

  mcp.Content _content(mcp.Content input) => switch (input) {
    mcp.TextContent() => mcp.TextContent(
      text: text(input.text),
      annotations: _annotations(input.annotations),
    ),
    mcp.ImageContent() =>
      _privateBinary(input.data)
          ? _omittedMedia
          : mcp.ImageContent(
              url: input.url == null ? null : text(input.url!),
              data: input.data,
              mimeType: text(input.mimeType),
              annotations: _annotations(input.annotations),
            ),
    mcp.AudioContent() =>
      _privateBinary(input.data)
          ? _omittedMedia
          : mcp.AudioContent(
              data: input.data,
              mimeType: text(input.mimeType),
              annotations: _annotations(input.annotations),
            ),
    mcp.ResourceContent() =>
      _privateBinary(input.blob)
          ? _omittedMedia
          : mcp.ResourceContent(
              uri: text(input.uri),
              text: input.text == null ? null : text(input.text!),
              blob: input.blob,
              mimeType: input.mimeType == null ? null : text(input.mimeType!),
              annotations: _annotations(input.annotations),
            ),
    mcp.ResourceLinkContent() => mcp.ResourceLinkContent(
      uri: text(input.uri),
      name: input.name == null ? null : text(input.name!),
      description: input.description == null ? null : text(input.description!),
      mimeType: input.mimeType == null ? null : text(input.mimeType!),
      annotations: _annotations(input.annotations),
      meta: _annotations(input.meta),
    ),
    _ => mcp.TextContent(text: text(jsonEncode(value(input.toJson())))),
  };

  /// Same opaque identity for route publication and per-server management.
  static String privateToolName(String serverId, String rawName) =>
      'mcp_tool_${sha256.convert(utf8.encode('$serverId\x00$rawName')).toString().substring(0, 24)}';

  String toolNameForModel(McpServerConfig server, String rawName) =>
      nameContainsCredential(rawName)
      ? privateToolName(server.id, rawName)
      : rawName;

  /// Known credential values only; safe placeholders and business shapes do
  /// not become credential evidence merely because of their field names.
  bool containsKnownCredential(Object? input) => switch (input) {
    String() => _known.text(input) != input,
    List() => input.any(containsKnownCredential),
    Map() => input.entries.any(
      (entry) =>
          containsKnownCredential(entry.key.toString()) ||
          containsKnownCredential(entry.value),
    ),
    _ => false,
  };

  bool nameContainsCredential(String input) {
    if (containsCredential(input)) return true;
    // Tool names can put a token prefix after an underscore; the diagnostic
    // redactor's ordinary word boundaries intentionally do not match that.
    return RegExp(r'sk-ant-|sk-|AIza|xai-|gsk_|hf_|AKIA')
        .allMatches(input)
        .any(
          (match) => McpSecrets.containsLiteralSecret({
            'args': [input.substring(match.start)],
          }),
        );
  }

  static const _credentialFields = {
    'authorization',
    'proxyauthorization',
    'apikey',
    'xapikey',
    'accesstoken',
    'refreshtoken',
    'clientsecret',
    'password',
    'passwd',
    'credential',
    'credentials',
    'secret',
    'auth',
    'securitytoken',
    'cookie',
    'cookies',
    'setcookie',
    'token',
    'authtoken',
    'bearertoken',
    'oauthtoken',
    'idtoken',
  };
  static String _fieldName(Object? input) =>
      input.toString().toLowerCase().replaceAll(RegExp(r'[-_ ]'), '');

  static bool _privateCredentialValue(Object? input) => switch (input) {
    String() =>
      input.isNotEmpty && McpSecrets.placeholder.stringMatch(input) != input,
    List() => input.any(_privateCredentialValue),
    Map() => input.values.any(_privateCredentialValue),
    _ => false,
  };

  bool containsCredential(Object? input) {
    if (input is String) {
      return text(input) != input;
    }
    if (input is List) {
      return input.any(containsCredential);
    }
    if (input is Map) {
      if (McpSecrets.containsLiteralSecret({
        for (final field in [
          'env',
          'headers',
          'command',
          'args',
          'url',
          'baseUrl',
        ])
          if (input.containsKey(field)) field: input[field],
      })) {
        return true;
      }
      for (final entry in input.entries) {
        if (_credentialFields.contains(_fieldName(entry.key)) &&
            _privateCredentialValue(entry.value)) {
          return true;
        }
        if (containsCredential(entry.key.toString()) ||
            containsCredential(entry.value)) {
          return true;
        }
      }
    }
    return false;
  }

  /// A separate model/history copy; callers continue dispatching raw values.
  Map<String, dynamic> argumentsForModel(Map<String, dynamic> arguments) =>
      (_argumentValue(arguments) as Map).cast<String, dynamic>();

  /// Manager protocol identities are public controls. Preserve declared keys,
  /// enums and published ids while sanitizing configuration/business payloads.
  Map<String, dynamic> managerArgumentsForModel(
    Map<String, dynamic> arguments, {
    Iterable<String> publicIds = const [],
  }) {
    const actions = {
      'list',
      'get',
      'add',
      'update',
      'enable',
      'disable',
      'remove',
      'test',
      'select',
      'unselect',
      'set_tool',
      'refresh',
      'reconnect',
      'import',
      'set_timeout',
    };
    const fields = {
      'action',
      'server_id',
      'assistant_id',
      'tool_name',
      'enabled',
      'needs_approval',
      'timeout_seconds',
      'json',
      'name',
      'config',
    };
    final ids = publicIds.toSet();
    final server = _publicServers[arguments['server_id']];
    final toolNames = server == null
        ? <String>{}
        : {
            for (final tool in server.tools)
              toolNameForModel(server, tool.name),
          };
    return {
      for (final entry in arguments.entries)
        fields.contains(entry.key)
            ? entry.key
            : text(entry.key): switch (entry.key) {
          'action' when actions.contains(entry.value) => entry.value,
          'server_id' when _publicServers.containsKey(entry.value) =>
            entry.value,
          'assistant_id' when ids.contains(entry.value) => entry.value,
          'tool_name' when toolNames.contains(entry.value) => entry.value,
          'config' when entry.value is Map => {
            for (final config in (entry.value as Map).entries)
              const {
                    'type',
                    'command',
                    'args',
                    'url',
                    'env',
                    'headers',
                    'cwd',
                    'workspaceId',
                    'disabled',
                  }.contains(config.key)
                  ? config.key.toString()
                  : text(config.key.toString()): switch (config.key) {
                'type'
                    when const {
                      'stdio',
                      'http',
                      'sse',
                    }.contains(config.value) =>
                  config.value,
                'workspaceId' when ids.contains(config.value) => config.value,
                _ => _argumentValue(
                  config.value,
                  privateFields: const {'env', 'headers'}.contains(config.key),
                  configuration: const {'command', 'args'}.contains(config.key),
                ),
              },
          },
          _ => _argumentValue(entry.value),
        },
    };
  }

  Object? _argumentValue(
    Object? input, {
    bool privateFields = false,
    bool configuration = false,
  }) {
    if (input is Map) {
      return {
        for (final entry in input.entries)
          text(entry.key.toString()):
              ((_credentialFields.contains(_fieldName(entry.key)) &&
                      _privateCredentialValue(entry.value)) ||
                  (entry.value is String &&
                      (entry.value as String).isNotEmpty &&
                      McpSecrets.placeholder.stringMatch(
                            entry.value as String,
                          ) !=
                          entry.value &&
                      privateFields &&
                      McpSecrets.isSecret(
                        entry.key.toString(),
                        entry.value as String,
                      )))
              ? _known.text('[REDACTED]')
              : _argumentValue(
                  entry.value,
                  privateFields: const {'env', 'headers'}.contains(entry.key),
                  configuration: const {'command', 'args'}.contains(entry.key),
                ),
      };
    }
    if (input is List) {
      var privateNext = false;
      final output = <Object?>[];
      for (final item in input) {
        output.add(
          privateNext &&
                  item is String &&
                  item.isNotEmpty &&
                  McpSecrets.placeholder.stringMatch(item) != item
              ? _known.text('[REDACTED]')
              : _argumentValue(item, configuration: configuration),
        );
        if (item is String) {
          final key = item.split('=').first;
          privateNext =
              configuration &&
              !item.contains('=') &&
              key.startsWith('-') &&
              McpSecrets.sensitiveName(key);
        } else {
          privateNext = false;
        }
      }
      return output;
    }
    if (configuration &&
        input is String &&
        McpSecrets.containsLiteralSecret({'command': input})) {
      final safe = LogRedactor.redactDiagnosticText(text(input));
      return safe != input ? safe : '[REDACTED]';
    }
    return input is String ? text(input) : input;
  }
}
