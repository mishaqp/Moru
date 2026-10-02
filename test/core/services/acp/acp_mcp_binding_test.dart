import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;

import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_binding.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_stdio_bridge.dart';
import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/api/tool_display_redaction.dart';

AcpMcpTools source({
  required Future<Map<String, Object?>> Function(
    String name,
    Map<String, dynamic> args, {
    required String toolCallId,
  })
  execute,
  void Function(String)? cancel,
}) => AcpMcpTools(
  key: 'assistant-1',
  definitions: () => [
    {
      'name': 'browser_use',
      'inputSchema': {'type': 'object'},
    },
  ],
  execute: execute,
  cancelApproval: cancel,
);

void main() {
  group('subscription browser authorization guard', () {
    const privateValue = 'private-authorization-test-value';
    const authUrl = 'https://login.example/callback?state=$privateValue';
    final inputs = <String, Map<String, dynamic>>{
      'authorization query': {'action': 'open', 'url': authUrl},
      'fragment token': {
        'action': 'new_tab',
        'url': 'https://login.example/#access_token=$privateValue',
      },
      'fragment route callback': {
        'action': 'open',
        'url': 'https://login.example/#/callback?CoDe=$privateValue',
      },
      'percent-encoded query key': {
        'action': 'open',
        'url': 'https://login.example/?%73TaTe=$privateValue',
      },
      'encoded fragment fields': {
        'action': 'open',
        'url': 'https://login.example/#state%3D$privateValue%26theme%3Ddark',
      },
      'Codex device endpoint without query': {
        'action': 'open',
        'url': 'https://auth.openai.com/codex/device',
      },
      'Claude endpoint without query': {
        'action': 'open',
        'url': 'https://claude.com/oauth/authorize',
      },
      'authorization link inside JavaScript': {
        'action': 'eval_js',
        'script': 'location.href = "$authUrl";',
      },
      'JSON-escaped authorization link': {
        'action': 'eval_js',
        'script':
            r'location.href = "https:\/\/login.example\/?state='
            '$privateValue";',
      },
      'nested authorization link': {
        'action': 'eval_js',
        'payload': {
          'links': [
            {'href': authUrl},
          ],
        },
      },
    };

    for (final entry in inputs.entries) {
      test('rejects ${entry.key} before executing the handler', () async {
        var executions = 0;
        final tools = source(
          execute: (name, args, {required toolCallId}) async {
            executions++;
            return {'content': []};
          },
        );
        final binding = await AcpMcpBinding.start(
          tools,
          redactor: AcpSecretRedactor([], protectAuthentication: true),
        );
        addTearDown(binding.close);
        binding.beginTurn(tools);
        binding.observe({
          'toolCallId': 'auth-page',
          'title': 'moru_browser_use',
          'rawInput': entry.value,
        });

        final result = await binding.callTool('browser_use', entry.value);

        expect(executions, 0);
        expect(result['isError'], isTrue);
        expect(result['content'], [
          {
            'type': 'text',
            'text':
                'Open Settings > Agents to sign in. '
                'Authentication pages cannot be opened by browser_use.',
          },
        ]);
        final response = jsonEncode(result);
        expect(response, isNot(contains(privateValue)));
        expect(response, isNot(contains('https://')));
      });
    }

    test('rejects an authorization link before waiting for a card', () async {
      final tools = source(
        execute: (name, args, {required toolCallId}) async => {'content': []},
      );
      final binding = await AcpMcpBinding.start(
        tools,
        redactor: AcpSecretRedactor([], protectAuthentication: true),
      );
      addTearDown(binding.close);
      binding.beginTurn(tools);

      final result = await binding
          .callTool('browser_use', {'action': 'open', 'url': authUrl})
          .timeout(const Duration(seconds: 1));

      expect(result['isError'], isTrue);
    });

    test('ordinary browser arguments reach the handler unchanged', () async {
      const input = <String, dynamic>{
        'action': 'open',
        'url': 'https://docs.example/article?stateful=true&codec=av1#section-2',
        'options': {
          'links': ['https://auth.openai.com/codex/device-help'],
        },
      };
      Map<String, dynamic>? received;
      final tools = source(
        execute: (name, args, {required toolCallId}) async {
          received = args;
          return {'content': []};
        },
      );
      final binding = await AcpMcpBinding.start(
        tools,
        redactor: AcpSecretRedactor([], protectAuthentication: true),
      );
      addTearDown(binding.close);
      binding.beginTurn(tools);
      binding.observe({
        'toolCallId': 'normal-page',
        'title': 'moru_browser_use',
        'rawInput': input,
      });

      final result = await binding.callTool('browser_use', input);

      expect(identical(received, input), isTrue);
      expect(result['isError'], isNot(true));
    });

    for (final protected in [false, true]) {
      test(
        protected
            ? 'other tools keep original arguments in subscription mode'
            : 'API key mode keeps browser execution arguments unchanged',
        () async {
          final input = <String, dynamic>{'action': 'open', 'url': authUrl};
          final name = protected ? 'mini_apps' : 'browser_use';
          Map<String, dynamic>? received;
          final tools = source(
            execute: (name, args, {required toolCallId}) async {
              received = args;
              return {'content': []};
            },
          );
          final binding = await AcpMcpBinding.start(
            tools,
            redactor: AcpSecretRedactor([], protectAuthentication: protected),
          );
          addTearDown(binding.close);
          binding.beginTurn(tools);
          binding.observe({
            'toolCallId': 'unchanged-arguments',
            'title': 'moru_$name',
            'rawInput': input,
          });

          final result = await binding.callTool(name, input);

          expect(identical(received, input), isTrue);
          expect(result['isError'], isNot(true));
        },
      );
    }
  });

  test(
    'concurrent MCP launches keep display filters scoped to their own call',
    () async {
      final gates = [Completer<void>(), Completer<void>()];
      final tools = [
        for (var index = 0; index < 2; index++)
          source(
            execute: (name, args, {required toolCallId}) async {
              gates[index].complete();
              await gates[1 - index].future;
              return {
                'display': ToolDisplayRedaction.current!.text('first second'),
              };
            },
          ),
      ];
      final bindings = [
        for (var index = 0; index < 2; index++)
          await AcpMcpBinding.start(
            tools[index],
            redactor: AcpSecretRedactor([index == 0 ? 'first' : 'second']),
          ),
      ];
      for (var index = 0; index < 2; index++) {
        addTearDown(bindings[index].close);
        bindings[index].beginTurn(tools[index]);
        bindings[index].observe({
          'toolCallId': 'call',
          'title': 'moru_browser_use',
          'rawInput': {'action': 'observe'},
        });
      }
      final results = await Future.wait([
        for (final binding in bindings)
          binding.callTool('browser_use', {'action': 'observe'}),
      ]).timeout(const Duration(seconds: 2));
      expect(results[0]['display'], '[REDACTED] second');
      expect(results[1]['display'], 'first [REDACTED]');
      expect(ToolDisplayRedaction.current, isNull);
    },
  );

  test(
    'HTTP capability selects HTTP, otherwise secrets go only into stdio env',
    () async {
      final binding = await AcpMcpBinding.start(
        source(
          execute: (name, args, {required toolCallId}) async => {'content': []},
        ),
      );
      addTearDown(binding.close);
      expect(binding.serverConfig(const AcpAgentInfo(mcpHttp: true)), {
        'type': 'http',
        'name': 'moru',
        'url': binding.server.url,
        'headers': [
          {'name': 'Authorization', 'value': 'Bearer ${binding.server.token}'},
        ],
      });
      final stdio = binding.serverConfig(const AcpAgentInfo());
      expect(stdio['name'], 'moru');
      expect(stdio['command'], 'node');
      expect(stdio['args'], ['/root/.config/moru-agents/moru-mcp.cjs']);
      expect(stdio['env'], [
        {'name': 'MORU_MCP_URL', 'value': binding.server.url},
        {'name': 'MORU_MCP_TOKEN', 'value': binding.server.token},
      ]);
      expect(
        AcpMcpStdioBridge.file.content,
        isNot(contains(binding.server.token)),
      );
    },
  );

  for (final agent in ['claude', 'codex', 'opencode']) {
    test('$agent MCP call uses the existing ACP card', () async {
      final calls = <String>[];
      final tools = source(
        execute: (name, args, {required toolCallId}) async {
          calls.add(toolCallId);
          return {
            'content': [
              {'type': 'text', 'text': args['action']},
            ],
          };
        },
      );
      final binding = await AcpMcpBinding.start(tools);
      addTearDown(binding.close);
      binding.beginTurn(tools);
      final input = {'action': 'observe'};
      binding.observe({
        'toolCallId': 'call-1',
        'sessionUpdate': 'tool_call',
        'status': 'in_progress',
        'title': switch (agent) {
          'claude' => 'mcp__moru__browser_use',
          'codex' => 'Tool: moru/browser_use',
          _ => 'moru_browser_use',
        },
        'rawInput': agent == 'codex'
            ? {'server': 'moru', 'tool': 'browser_use', 'arguments': input}
            : input,
      });
      final transport = await mcp.StreamableHttpClientTransport.create(
        baseUrl: binding.server.url,
        headers: {'Authorization': 'Bearer ${binding.server.token}'},
      );
      final client = mcp.McpClient.createClient(
        mcp.McpClient.simpleConfig(name: 'test', version: '1'),
      );
      addTearDown(client.disconnect);
      await client.connect(transport);
      final result = await client.callTool('browser_use', input);
      expect(result.isError, isFalse);
      expect(calls, ['acp-tool-call-1']);
      // ACP's permission gate delegates to the Moru handler, so it cannot
      // produce a second user prompt before the HTTP call.
      expect(
        binding.permissionChoice(
          AcpPermissionRequest(
            sessionId: 's',
            toolCallId: 'acp-tool-call-1',
            title: '',
            kind: 'other',
            input: input,
            options: const [
              AcpPermissionOption(
                id: 'allow',
                name: 'Allow',
                kind: 'allow_once',
              ),
            ],
          ),
        ),
        'allow',
      );
      await transport.waitForInitialGetAttempt();
    });
  }

  test('HTTP arriving before the card waits for the matching update', () async {
    final entered = Completer<String>();
    final tools = source(
      execute: (name, args, {required toolCallId}) async {
        entered.complete(toolCallId);
        return {'content': []};
      },
    );
    final binding = await AcpMcpBinding.start(tools);
    addTearDown(binding.close);
    binding.beginTurn(tools);
    final result = binding.callTool('browser_use', {'action': 'observe'});
    binding.observe({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'late',
      'title': 'moru_browser_use',
      'rawInput': {'action': 'observe'},
    });
    expect(await entered.future, 'acp-tool-late');
    expect((await result)['isError'], isNot(true));
  });

  test(
    'stopping a turn cancels a pending card and does not dispatch a waiting call',
    () async {
      var executions = 0;
      final tools = source(
        execute: (name, args, {required toolCallId}) async {
          executions++;
          return {'content': []};
        },
      );
      final binding = await AcpMcpBinding.start(tools);
      addTearDown(binding.close);
      binding.beginTurn(tools);
      final waiting = binding.callTool('browser_use', {'action': 'observe'});
      binding.endTurn();
      expect((await waiting)['isError'], isTrue);
      expect(executions, 0);
    },
  );

  test(
    'the dependency-free Node bridge connects and returns JSON-RPC results',
    () async {
      final tools = source(
        execute: (name, args, {required toolCallId}) async => {
          'content': [
            {'type': 'text', 'text': 'from Moru'},
          ],
        },
      );
      final binding = await AcpMcpBinding.start(tools);
      addTearDown(binding.close);
      binding.beginTurn(tools);
      binding.observe({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'node-call',
        'title': 'moru_browser_use',
        'rawInput': {'action': 'observe'},
      });
      final dir = await Directory.systemTemp.createTemp('moru-mcp-node-');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/bridge.cjs');
      await script.writeAsString(AcpMcpStdioBridge.file.content);
      final process = await Process.start(
        'node',
        [script.path],
        environment: {
          'MORU_MCP_URL': binding.server.url,
          'MORU_MCP_TOKEN': binding.server.token,
        },
      );
      addTearDown(() => process.kill());
      final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(lines.cancel);
      final errors = process.stderr.transform(utf8.decoder).join();
      process.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-11-25',
            'capabilities': {},
            'clientInfo': {'name': 'test', 'version': '1'},
          },
        }),
      );
      expect(await lines.moveNext(), isTrue);
      expect(jsonDecode(lines.current)['result']['serverInfo']['name'], 'moru');
      process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );
      process.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'browser_use',
            'arguments': {'action': 'observe'},
          },
        }),
      );
      expect(await lines.moveNext(), isTrue);
      final response = jsonDecode(lines.current);
      expect(response['id'], 2);
      expect(response['result']['content'][0]['text'], 'from Moru');
      await process.stdin.close();
      expect(await process.exitCode, 0, reason: await errors);
    },
  );
}
