import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../workspace/workspace_runtime.dart';
import 'acp_mcp_server.dart';

/// A real loopback check from the selected Android Linux runtime. Nothing
/// assumes that PRoot or root/chroot share the application's network.
class AcpMcpProbe {
  static const marker = '__moru_mcp_available__';
  static const script = r'''
const http = require('node:http');
const request = http.request(process.env.MORU_MCP_URL, {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ' + process.env.MORU_MCP_TOKEN,
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream'
  }
}, response => {
  let body = '';
  response.setEncoding('utf8');
  response.on('data', data => { body += data; });
  response.on('error', fail);
  response.on('end', () => {
    clearTimeout(timer);
    try {
      const message = JSON.parse(body);
      if (response.statusCode !== 200 || message.jsonrpc !== '2.0' ||
          message.id !== 1 || !message.result || message.error) return fail();
      process.stdout.write('__moru_mcp_available__\n');
    } catch (_) { fail(); }
  });
});
function fail() {
  clearTimeout(timer);
  process.exitCode = 1;
  request.destroy();
}
const timer = setTimeout(fail, 8000);
request.on('error', fail);
request.end(JSON.stringify({jsonrpc: '2.0', id: 1, method: 'ping'}));
''';

  static Future<bool> check(
    WorkspaceRuntime runtime, {
    required Map<String, String> environment,
  }) async {
    AcpMcpServer? server;
    final id = 'acp-mcp-probe-${const Uuid().v4()}';
    try {
      server = await AcpMcpServer.start(
        tools: () => [],
        callTool: (_, _) async => {'content': []},
      );
      final output = <int>[];
      var code = -1;
      await for (final event
          in runtime
              .run(
                CommandRequest(
                  runId: id,
                  command: "node -e '${script.replaceAll("'", "'\\''")}'",
                  cwd: '/root',
                  timeout: const Duration(seconds: 12),
                  env: {
                    ...environment,
                    'MORU_MCP_URL': server.url,
                    'MORU_MCP_TOKEN': server.token,
                  },
                ),
              )
              .timeout(const Duration(seconds: 15))) {
        switch (event) {
          case CommandOutput(:final kind, :final bytes):
            if (kind == OutputStreamKind.stdout) output.addAll(bytes);
          case CommandExited(:final exitCode):
            code = exitCode;
          case CommandStarted():
            break;
        }
      }
      return code == 0 &&
          const LineSplitter()
              .convert(utf8.decode(output, allowMalformed: true))
              .contains(marker);
    } catch (_) {
      unawaited(runtime.cancel(id).catchError((Object _) {}));
      return false;
    } finally {
      await server?.close();
    }
  }
}
