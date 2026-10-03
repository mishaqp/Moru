import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;

import 'package:Kelivo/core/services/acp/acp_mcp_server.dart';

Map<String, dynamic> definition(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': 'Test tool',
    'parameters': {'type': 'object'},
  },
};

Future<(int, Map<String, dynamic>?)> rpc(
  AcpMcpServer server,
  Map<String, Object?> message, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(server.url));
    request.headers
      ..contentType = ContentType.json
      ..set('Accept', 'application/json, text/event-stream')
      ..set('Authorization', 'Bearer ${token ?? server.token}');
    request.write(jsonEncode(message));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (
      response.statusCode,
      body.isEmpty ? null : jsonDecode(body) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('our mcp_client lists only Moru tools and calls the handler', () async {
    final definitions = [
      definition('browser_use'),
      definition('publish_mini_app'),
      definition('memory_read'),
      definition('manage_scheduled_tasks'),
      definition('shell'),
      definition('read_file'),
      definition('root_shell'),
      definition('unselected_external_tool'),
    ];
    final calls = <String>[];
    final server = await AcpMcpServer.start(
      tools: () => AcpMcpServer.moruTools(definitions),
      callTool: (name, args) async {
        calls.add('$name:${args['action']}');
        return {
          'content': [
            {'type': 'text', 'text': 'browser result'},
          ],
        };
      },
    );
    addTearDown(server.close);
    final transport = await mcp.StreamableHttpClientTransport.create(
      baseUrl: server.url,
      headers: {'Authorization': 'Bearer ${server.token}'},
    );
    final client = mcp.McpClient.createClient(
      mcp.McpClient.simpleConfig(name: 'Moru test', version: '1'),
    );
    addTearDown(client.disconnect);
    await client.connect(transport);
    expect((await client.listTools()).map((t) => t.name), [
      'browser_use',
      'publish_mini_app',
      'memory_read',
      'manage_scheduled_tasks',
    ]);
    final result = await client.callTool('browser_use', {'action': 'observe'});
    expect(result.isError, isFalse);
    expect((result.content.single as mcp.TextContent).text, 'browser result');
    expect(calls, ['browser_use:observe']);
    await expectLater(
      client.callTool('shell', {}),
      throwsA(isA<mcp.McpError>()),
    );
    expect(calls, ['browser_use:observe']);
    // A live switch takes effect for both discovery and execution.
    definitions.removeWhere(
      (d) => (d['function'] as Map)['name'] == 'browser_use',
    );
    expect(
      (await client.listTools()).map((t) => t.name),
      isNot(contains('browser_use')),
    );
    await expectLater(
      client.callTool('browser_use', {}),
      throwsA(isA<mcp.McpError>()),
    );
    await transport.waitForInitialGetAttempt();
  });

  test('incorrect and old tokens are rejected before dispatch', () async {
    var calls = 0;
    Future<AcpMcpServer> start() => AcpMcpServer.start(
      tools: () => AcpMcpServer.moruTools([definition('memory_read')]),
      callTool: (name, args) async {
        calls++;
        return {'content': <Object>[]};
      },
    );
    final first = await start();
    final oldToken = first.token;
    final oldPort = Uri.parse(first.url).port;
    await first.close();
    // Probe before replacement: the OS may otherwise give next the old port.
    final rebound = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      oldPort,
    );
    final next = await start();
    await rebound.close(force: true);
    addTearDown(next.close);
    expect(next.token, isNot(oldToken));
    final message = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': 'memory_read', 'arguments': {}},
    };
    for (final token in ['incorrect', oldToken]) {
      expect((await rpc(next, message, token: token)).$1, 401);
    }
    expect(calls, 0);
  });

  test(
    'notifications have no response and malformed calls do not execute',
    () async {
      final server = await AcpMcpServer.start(
        tools: () => AcpMcpServer.moruTools([definition('memory_read')]),
        callTool: (name, args) async => throw StateError('must not execute'),
      );
      addTearDown(server.close);
      expect(
        await rpc(server, {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }),
        (202, null),
      );
      final response = await rpc(server, {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'memory_read', 'arguments': 'invalid'},
      });
      expect(response.$2!['error'], containsPair('code', -32602));
    },
  );
}
