import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mcp_client/mcp_client.dart' show McpProtocol;

import '../memory/memory_tools.dart';

typedef AcpMcpToolHandler =
    Future<Map<String, Object?>> Function(
      String name,
      Map<String, dynamic> args,
    );

/// A stateless Streamable HTTP endpoint owned by one chat's agent process.
/// Uses JSON POST responses; the optional server-initiated GET stream is not
/// offered. Tools and their live policy are supplied by the chat adapter.
class AcpMcpServer {
  AcpMcpServer._(this._server, this.token, this.tools, this.callTool);

  final HttpServer _server;
  final String token;
  final List<Map<String, dynamic>> Function() tools;
  final AcpMcpToolHandler callTool;
  Future<void>? _closing;

  static const int maxMessageBytes = 8 * 1024 * 1024;

  String get url => 'http://127.0.0.1:${_server.port}/mcp';

  static Set<String> get allowedNames => {
    'browser_use',
    'publish_mini_app',
    'mini_apps',
    'manage_scheduled_tasks',
    'report_problem',
    ...MemoryTools.allToolNames,
    ...MemoryTools.legacyToolNames,
  };

  /// Convert the normal model's definitions, retaining only Moru's tools.
  /// Workspace file/shell tools and third-party MCP servers never pass here.
  static List<Map<String, dynamic>> moruTools(
    Iterable<Map<String, dynamic>> definitions,
  ) => [
    for (final definition in definitions)
      if (definition['function'] case final Map function)
        if (function['name'] is String &&
            allowedNames.contains(function['name']))
          {
            'name': function['name'],
            if (function['description'] is String)
              'description': function['description'],
            'inputSchema': function['parameters'] ?? {'type': 'object'},
          },
  ];

  static Future<AcpMcpServer> start({
    required List<Map<String, dynamic>> Function() tools,
    required AcpMcpToolHandler callTool,
  }) async {
    final random = Random.secure();
    final token = base64Url.encode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = AcpMcpServer._(server, token, tools, callTool);
    server.listen((request) => unawaited(endpoint._handle(request)));
    return endpoint;
  }

  Future<void> close() => _closing ??= _server.close(force: true).then((_) {});

  List<Map<String, dynamic>> _available() => [
    for (final tool in tools())
      if (allowedNames.contains(tool['name'])) tool,
  ];

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (_closing != null || !_authorized(request)) {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      // A loopback bind alone does not protect against browser DNS rebinding.
      final origin = request.headers.value('Origin');
      if (origin != null) {
        final uri = Uri.tryParse(origin);
        if (uri == null ||
            !const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
      }
      if (request.uri.path != '/mcp') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'POST') {
        response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set('Allow', 'POST');
        return;
      }
      final version = request.headers.value('MCP-Protocol-Version');
      if (version != null && !McpProtocol.isVersionSupported(version)) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        if (bytes.length + chunk.length > maxMessageBytes) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        bytes.addAll(chunk);
      }
      Object? message;
      try {
        message = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        _write(response, _error(null, -32700, 'Invalid JSON'));
        return;
      }
      if (message is! Map ||
          message['jsonrpc'] != '2.0' ||
          message['method'] is! String ||
          (message['id'] != null &&
              message['id'] is! String &&
              message['id'] is! num)) {
        _write(response, _error(null, -32600, 'Invalid JSON-RPC request'));
        return;
      }
      if (!message.containsKey('id')) {
        response.statusCode = HttpStatus.accepted;
        return;
      }
      final id = message['id'];
      final rawParams = message['params'];
      if (rawParams != null && rawParams is! Map) {
        _write(response, _error(id, -32602, 'Parameters must be an object'));
        return;
      }
      final params = rawParams as Map? ?? const {};
      Object? result;
      switch (message['method']) {
        case 'initialize':
          final requested = params['protocolVersion'];
          result = {
            'protocolVersion':
                requested is String && McpProtocol.isVersionSupported(requested)
                ? requested
                : McpProtocol.defaultVersion,
            'capabilities': {'tools': <String, Object?>{}},
            'serverInfo': {'name': 'moru', 'version': '1'},
          };
        case 'ping':
          result = <String, Object?>{};
        case 'tools/list':
          result = {'tools': _available()};
        case 'tools/call':
          final name = params['name'];
          final arguments = params['arguments'];
          if (name is! String || (arguments != null && arguments is! Map)) {
            _write(
              response,
              _error(id, -32602, 'Expected tool name and arguments object'),
            );
            return;
          }
          if (!_available().any((tool) => tool['name'] == name)) {
            _write(response, _error(id, -32602, 'Tool is unavailable: $name'));
            return;
          }
          try {
            result = {
              'isError': false,
              ...await callTool(
                name,
                Map<String, dynamic>.from(arguments as Map? ?? const {}),
              ),
            };
          } catch (error) {
            result = {
              'isError': true,
              'content': [
                {'type': 'text', 'text': 'The Moru tool failed: $error'},
              ],
            };
          }
        default:
          _write(response, _error(id, -32601, 'Method not found'));
          return;
      }
      _write(response, {'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (_) {
      // A client may disappear during an approval or while the agent stops.
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      await response.close().catchError((_) {});
    }
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final expected = 'Bearer $token';
    var diff = header.length ^ expected.length;
    for (var i = 0; i < header.length && i < expected.length; i++) {
      diff |= header.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static void _write(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}
