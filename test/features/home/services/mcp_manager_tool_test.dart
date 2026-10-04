import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_oauth_service.dart';
import 'package:Kelivo/core/services/logging/flutter_logger.dart';
import 'package:Kelivo/features/home/services/mcp_manager_tool.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';

import '../../../support/business_test_harness.dart';

Future<HttpServer> _errorServer(String message) async {
  HttpOverrides.global = null;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    final rpc = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpc['id'],
        'error': {'code': -32000, 'message': message},
      }),
    );
    await request.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late McpProvider provider;
  late ToolApprovalService approvals;
  late McpManagerTool tool;

  setUp(() async {
    provider = McpProvider(preferences: createBusinessTestPreferences());
    await provider.loaded;
    approvals = ToolApprovalService();
    tool = McpManagerTool(provider: provider, approvals: approvals);
  });
  tearDown(() {
    provider.dispose();
    approvals.dispose();
  });

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async =>
      jsonDecode(
            await tool.execute(
              args,
              toolCallId: 'call',
              conversationId: 'chat',
            ),
          )
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> addDisabled({
    Map<String, dynamic>? config,
  }) async {
    final pending = run({
      'action': 'add',
      'name': 'Fixture',
      'config':
          config ??
          {'type': 'http', 'url': 'https://example.test/mcp', 'disabled': true},
    });
    await Future<void>.delayed(Duration.zero);
    approvals.approve('call', conversationId: 'chat');
    return pending;
  }

  test(
    'ordinary env values are confirmed, saved and returned unchanged',
    () async {
      const path = '/workspace/mcp-memory.json';
      final pending = run({
        'action': 'add',
        'name': 'Memory',
        'config': {
          'command': 'mcp-server-memory',
          'disabled': true,
          'env': {
            'MEMORY_FILE_PATH': path,
            'DATA_DIRECTORY': '/home/alice/mcp',
            'MODE': '',
          },
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(approvals.pendingRequests, hasLength(1));
      final request = approvals.pendingRequests.single;
      expect(request.secretFields, isEmpty);
      expect(
        request.arguments['server']['env']['MEMORY_FILE_PATH']['value'],
        path,
      );
      expect(
        request.arguments['server']['env']['DATA_DIRECTORY']['value'],
        '/home/alice/mcp',
      );
      approvals.approve('call', conversationId: 'chat');
      final added = await pending;
      final id = added['server']['id'];
      expect(added['ok'], isTrue);
      expect(provider.getById(id)!.env['MEMORY_FILE_PATH'], path);
      expect(added['server']['env']['MEMORY_FILE_PATH']['value'], path);
      expect(
        added['server']['env']['DATA_DIRECTORY']['value'],
        '/home/alice/mcp',
      );
      expect(added['server']['env']['MODE']['value'], '');
      approvals.setAutoApproveAll(true);
      final updated = await run({
        'action': 'update',
        'server_id': id,
        'config': {
          'env': {'MEMORY_FILE_PATH': '/workspace/x.json'},
        },
      });
      expect(
        updated['server']['env']['MEMORY_FILE_PATH']['value'],
        '/workspace/x.json',
      );
      expect(approvals.pendingRequests, isEmpty);
    },
  );

  test(
    'ordinary headers are visible and can be updated in full trust',
    () async {
      approvals.setAutoApproveAll(true);
      final added = await run({
        'action': 'add',
        'name': 'Public',
        'config': {
          'type': 'http',
          'url': 'https://example.test/mcp',
          'disabled': true,
          'headers': {'X-Transport': 'mcp', 'Accept': 'application/json'},
        },
      });
      expect(added['ok'], isTrue);
      final id = added['server']['id'];
      expect(added['server']['headers']['Accept']['value'], 'application/json');
      final updated = await run({
        'action': 'update',
        'server_id': id,
        'config': {
          'headers': {'Accept': 'text/event-stream'},
        },
      });
      expect(
        updated['server']['headers']['Accept']['value'],
        'text/event-stream',
      );
      expect(provider.getById(id)!.headers['Accept'], 'text/event-stream');
    },
  );

  test('old private metadata does not hide an ordinary file path', () async {
    const path = '/workspace/x.json';
    await provider.importServers([
      McpServerConfig(
        id: 'legacy',
        name: 'Memory',
        enabled: false,
        transport: McpTransportType.stdio,
        command: 'mcp-server-memory',
        env: {'MEMORY_FILE_PATH': path},
        managedSecrets: {'env:MEMORY_FILE_PATH': path},
      ),
    ]);
    final result = await run({'action': 'get', 'server_id': 'legacy'});
    expect(result['server']['env']['MEMORY_FILE_PATH']['value'], path);
  });

  test(
    'diagnostic credential shapes are private regardless of field name',
    () async {
      const secret = 'PRIVATE_CONNECTION_SENTINEL';
      approvals.setAutoApproveAll(true);
      for (final field in ['env', 'headers']) {
        for (final value in [
          'Server=db;Password=$secret',
          'Authorization: Bearer $secret',
          'API_TOKEN=$secret',
        ]) {
          final rejected = await run({
            'action': 'add',
            'name': 'Rejected',
            'config': {
              'type': 'http',
              'url': 'https://example.test/mcp',
              'disabled': true,
              field: {'CONFIG': value},
            },
          });
          expect(rejected['error'], 'secret_required', reason: value);
          expect(jsonEncode(rejected), isNot(contains(secret)));
        }
      }
      await provider.importServers([
        McpServerConfig(
          id: 'saved-connection',
          name: 'Saved',
          enabled: false,
          transport: McpTransportType.stdio,
          command: 'srv',
          env: {'DATABASE_CONNECTION_STRING': 'Server=db;Password=$secret'},
        ),
      ]);
      final result = await run({
        'action': 'get',
        'server_id': 'saved-connection',
      });
      expect(result['server']['env']['DATABASE_CONNECTION_STRING'], {
        'value_set': true,
      });
      expect(jsonEncode(result), isNot(contains(secret)));
      approvals.setAutoApproveAll(false);
      final renamed = run({
        'action': 'update',
        'server_id': 'saved-connection',
        'name': 'Rename again',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        jsonEncode(approvals.pendingRequests.single.arguments),
        isNot(contains(secret)),
      );
      approvals.deny('call', conversationId: 'chat');
      expect((await renamed)['error'], 'approval_denied');
    },
  );

  test(
    'secret assignments cannot bypass validation through shell or argv',
    () async {
      approvals.setAutoApproveAll(true);
      for (final arg in [
        'API_TOKEN=abc exec srv',
        'export API_TOKEN="abc"; exec srv',
        "env PWD='abc' srv",
        'API_TOKEN={{TOKEN}}abc exec srv',
        'export API_TOKEN+=abc; exec srv',
      ]) {
        final result = await run({
          'action': 'add',
          'name': 'Rejected',
          'config': {
            'command': '/bin/sh',
            'args': ['-lc', arg],
            'disabled': true,
          },
        });
        expect(result['error'], 'secret_required', reason: arg);
        expect(approvals.pendingRequests, isEmpty);
      }
      final direct = await run({
        'action': 'add',
        'name': 'Rejected',
        'config': {
          'command': 'env',
          'args': ['API_TOKEN=abc', 'srv'],
          'disabled': true,
        },
      });
      expect(direct['error'], 'secret_required');
    },
  );

  test(
    'ordinary and private placeholder shell assignments remain usable',
    () async {
      const secret = 'PRIVATE_SHELL_SENTINEL';
      final pending = run({
        'action': 'add',
        'name': 'Shell placeholders',
        'config': {
          'command': '/bin/sh',
          'args': [
            '-lc',
            "MEMORY_FILE_PATH=/workspace/x.json API_TOKEN='{{TOKEN}}' exec srv",
          ],
          'disabled': true,
        },
      });
      await Future<void>.delayed(Duration.zero);
      final request = approvals.pendingRequests.single;
      expect(request.secretFields, ['TOKEN']);
      expect(jsonEncode(request.arguments), contains('/workspace/x.json'));
      approvals.approve(
        'call',
        conversationId: 'chat',
        secretValues: {'TOKEN': secret},
      );
      final result = await pending;
      expect(result['ok'], isTrue);
      expect(
        provider.getById(result['server']['id'])!.args.last,
        contains(secret),
      );
      expect(jsonEncode(result), isNot(contains(secret)));
      expect(jsonEncode(result), contains('/workspace/x.json'));
    },
  );

  test('unknown ids are rejected before confirmation', () async {
    for (final action in [
      'get',
      'update',
      'remove',
      'enable',
      'disable',
      'test',
    ]) {
      final result = await run({
        'action': action,
        'server_id': 'missing',
        'config': {'url': 'https://example.test'},
      });
      expect(result['error'], 'unknown_server', reason: action);
      expect(result['message'], contains('list'));
      expect(approvals.pendingRequests, isEmpty);
    }
  });

  test(
    'mutations ask every time, describe the server and honor denial',
    () async {
      final result = await addDisabled();
      final id = result['server']['id'];
      for (final action in ['update', 'enable', 'disable', 'remove']) {
        final pending = run({
          'action': action,
          'server_id': id,
          if (action == 'update') 'name': 'Renamed',
        });
        await Future<void>.delayed(Duration.zero);
        final request = approvals.pendingRequests.single;
        expect(request.requiresExplicitConsent, isTrue);
        expect(request.arguments['action'], action);
        expect(
          request.arguments['server']['name'],
          action == 'update' ? 'Renamed' : 'Fixture',
        );
        expect(request.arguments['server']['type'], 'http');
        expect(request.arguments['server']['url'], 'https://example.test/mcp');
        approvals.deny('call', conversationId: 'chat');
        expect((await pending)['error'], 'approval_denied');
      }
      expect(provider.getById(id), isNotNull);
      expect((await run({'action': 'list'}))['ok'], isTrue);
      expect((await run({'action': 'get', 'server_id': id}))['ok'], isTrue);
      expect(
        (await run({'action': 'test', 'server_id': id}))['connected'],
        isFalse,
      );
      expect(approvals.pendingRequests, isEmpty);
    },
  );

  test(
    'full trust skips consent and collects missing secrets privately',
    () async {
      approvals.setAutoApproveAll(true);
      final result = await run({
        'action': 'add',
        'name': 'Trusted',
        'config': {
          'type': 'http',
          'url': 'https://example.test',
          'disabled': true,
        },
      });
      expect(result['ok'], isTrue);
      expect(approvals.pendingRequests, isEmpty);
      final pending = run({
        'action': 'add',
        'name': 'Private',
        'config': {
          'type': 'http',
          'url': 'https://example.test',
          'headers': {'Authorization': ''},
          'disabled': true,
        },
      });
      await Future<void>.delayed(Duration.zero);
      final request = approvals.pendingRequests.single;
      expect(request.secretInputOnly, isTrue);
      expect(request.secretFields, ['header:Authorization']);
      expect(provider.servers.where((s) => s.name == 'Private'), isEmpty);
      const secret = 'PRIVATE_TRUSTED_INPUT';
      approvals.approve(
        'call',
        conversationId: 'chat',
        secretValues: {'header:Authorization': 'Bearer $secret'},
      );
      final saved = await pending;
      expect(saved['ok'], isTrue);
      expect(jsonEncode(saved), isNot(contains(secret)));
      expect(jsonEncode(request.arguments), isNot(contains(secret)));
      expect(FlutterLogger.technicalTail, isNot(contains(secret)));
      expect(
        provider
            .getById(saved['server']['id'])!
            .managedSecrets['header:Authorization'],
        'Bearer $secret',
      );
    },
  );

  test(
    'enabling a saved server with missing secrets requires private input',
    () async {
      final id = await provider.addServer(
        enabled: false,
        name: 'Incomplete',
        transport: McpTransportType.http,
        url: 'https://example.test/mcp',
        headers: {'Authorization': ''},
      );
      approvals.setAutoApproveAll(true);
      final trusted = run({'action': 'enable', 'server_id': id});
      await Future<void>.delayed(Duration.zero);
      expect(approvals.pendingRequests.single.secretInputOnly, isTrue);
      expect(provider.getById(id)!.enabled, isFalse);
      approvals.deny('call', conversationId: 'chat');
      expect((await trusted)['error'], 'approval_denied');
      approvals.setAutoApproveAll(false);
      final pending = run({'action': 'enable', 'server_id': id});
      await Future<void>.delayed(Duration.zero);
      expect(approvals.pendingRequests.single.secretFields, [
        'header:Authorization',
      ]);
      approvals.deny('call', conversationId: 'chat');
      expect((await pending)['error'], 'approval_denied');
    },
  );

  test(
    'private values never enter arguments, results or diagnostics',
    () async {
      const secret = 'PRIVATE_MCP_SENTINEL';
      final pending = run({
        'action': 'add',
        'name': 'Private',
        'config': {
          'type': 'http',
          'url': 'https://example.test/mcp?token={{TOKEN}}',
          'disabled': true,
          'headers': {'Authorization': ''},
        },
      });
      await Future<void>.delayed(Duration.zero);
      final request = approvals.pendingRequests.single;
      expect(
        request.secretFields,
        containsAll(['TOKEN', 'header:Authorization']),
      );
      final before = jsonEncode(request.arguments);
      approvals.approve(
        'call',
        conversationId: 'chat',
        secretValues: {
          'TOKEN': secret,
          'header:Authorization': 'Bearer $secret',
        },
      );
      final result = await pending;
      expect(result['ok'], isTrue, reason: '$result');
      final id = result['server']['id'] as String;
      expect(provider.getById(id)!.headers['Authorization'], 'Bearer $secret');
      expect(provider.getById(id)!.url, contains(secret));
      final outputs = [
        before,
        jsonEncode(result),
        jsonEncode(await run({'action': 'list'})),
        jsonEncode(await run({'action': 'get', 'server_id': id})),
        FlutterLogger.technicalTail,
      ];
      for (final output in outputs) {
        expect(output, isNot(contains(secret)));
      }
      expect(result['server']['headers']['Authorization'], {'value_set': true});
      final renamed = run({
        'action': 'update',
        'server_id': id,
        'name': 'Safe rename',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        jsonEncode(approvals.pendingRequests.single.arguments),
        isNot(contains(secret)),
      );
      expect(approvals.pendingRequests.single.secretFields, isEmpty);
      approvals.approve('call', conversationId: 'chat');
      expect((await renamed)['ok'], isTrue);
      expect(provider.getById(id)!.headers['Authorization'], 'Bearer $secret');
      final restored = McpServerConfig.fromJson(provider.getById(id)!.toJson());
      expect(
        jsonEncode(McpManagerTool.serverSummary(restored, provider)),
        isNot(contains(secret)),
      );
    },
  );

  test('raw credentials are rejected without echoing them', () async {
    const secret = 'PRIVATE_MCP_SENTINEL';
    for (final config in [
      {
        'command': 'node',
        'env': {'TOKEN': secret},
      },
      {
        'command': 'node',
        'env': {'API_KEY': 'sk-privateSentinel'},
      },
      {
        'command': 'node',
        'env': {'ORDINARY': 'sk-privateSentinel'},
      },
      {
        'type': 'http',
        'url': 'https://example.test',
        'headers': {'X-Value': 'Bearer x'},
      },
      {
        'type': 'http',
        'url': 'https://example.test',
        'headers': {'Authorization': 'Bearer $secret'},
      },
      {
        'command': 'node',
        'args': ['--password', secret],
      },
      {
        'command': 'node',
        'args': ['--token=$secret'],
      },
      {'type': 'http', 'url': 'https://user:$secret@example.test'},
      {'type': 'http', 'url': 'https://example.test?api_key=$secret'},
      {'type': 'http', 'url': 'https://example.test/mcp?sig=$secret'},
      {
        'command': 'node',
        'args': ['--data=sk-secretABC/{{SAFE}}'],
      },
    ]) {
      final result = await run({
        'action': 'add',
        'name': 'Rejected',
        'config': config,
      });
      expect(result['error'], 'secret_required');
      expect(jsonEncode(result), isNot(contains(secret)));
      expect(approvals.pendingRequests, isEmpty);
    }
  });

  test(
    'STDIO is listed without a runtime and secrets stay private after edits',
    () async {
      const secret = 'PRIVATE_STDIO_SECRET';
      final pending = run({
        'action': 'add',
        'name': 'STDIO',
        'config': {
          'command': 'node',
          'args': ['server.js', '--token={{TOKEN}}'],
          'env': {'API_KEY': ''},
          'disabled': true,
        },
      });
      await Future<void>.delayed(Duration.zero);
      final description = jsonEncode(
        approvals.pendingRequests.single.arguments,
      );
      expect(description, contains('node'));
      expect(description, contains('server.js'));
      expect(description, contains('API_KEY'));
      approvals.approve(
        'call',
        conversationId: 'chat',
        secretValues: {'TOKEN': secret, 'env:API_KEY': secret},
      );
      final added = await pending;
      expect(added['ok'], isTrue, reason: '$added');
      final id = added['server']['id'] as String;
      expect(provider.getById(id)!.args.last, '--token=$secret');
      expect(provider.getById(id)!.env['API_KEY'], secret);
      expect(jsonEncode(await run({'action': 'list'})), contains(id));
      expect(jsonEncode(added), isNot(contains(secret)));
      await provider.updateServer(
        provider
            .getById(id)!
            .copyWith(
              tools: [
                McpToolConfig(enabled: true, name: 'echo', description: secret),
              ],
            ),
      );
      approvals.setAutoApproveAll(true);
      final edited = await run({
        'action': 'update',
        'server_id': id,
        'config': {
          'env': {},
          'args': ['other.js'],
        },
      });
      expect(edited['ok'], isTrue, reason: '$edited');
      expect(jsonEncode(edited), isNot(contains(secret)));
      await provider.replaceAllFromJson(provider.exportServersAsUiJson());
      expect(provider.getById(id)!.managedSecrets['TOKEN'], secret);
      expect(
        jsonEncode(await run({'action': 'get', 'server_id': id})),
        isNot(contains(secret)),
      );
    },
  );

  test(
    'removing a saved header cannot expose its value through cached tools',
    () async {
      const secret = 'PRIVATE_SAVED_HEADER';
      final id = await provider.addServer(
        enabled: false,
        name: 'Saved',
        transport: McpTransportType.http,
        url: 'https://example.test',
        headers: {'Authorization': secret},
      );
      await provider.updateServer(
        provider
            .getById(id)!
            .copyWith(
              tools: [
                McpToolConfig(enabled: true, name: 'echo', description: secret),
              ],
            ),
      );
      approvals.setAutoApproveAll(true);
      final edited = await run({
        'action': 'update',
        'server_id': id,
        'config': {'headers': {}},
      });
      expect(edited['ok'], isTrue);
      expect(jsonEncode(edited), isNot(contains(secret)));
    },
  );

  test(
    'turning on full trust while a secret card is pending does not invent values',
    () async {
      final pending = run({
        'action': 'add',
        'name': 'Private',
        'config': {
          'type': 'http',
          'url': 'https://example.test',
          'headers': {'Authorization': ''},
        },
      });
      await Future<void>.delayed(Duration.zero);
      approvals.setAutoApproveAll(true);
      expect(approvals.pendingRequests.single.secretInputOnly, isTrue);
      expect(
        provider.configuredServers.where((s) => s.name == 'Private'),
        isEmpty,
      );
      approvals.deny('call', conversationId: 'chat');
      expect((await pending)['error'], 'approval_denied');
    },
  );

  test(
    'a removed or changed server cannot reuse an old confirmation',
    () async {
      final result = await addDisabled();
      final id = result['server']['id'] as String;
      final pending = run({'action': 'remove', 'server_id': id});
      await Future<void>.delayed(Duration.zero);
      await provider.updateServerMetadata(
        provider.getById(id)!.copyWith(name: 'Changed'),
      );
      approvals.approve('call', conversationId: 'chat');
      expect((await pending)['error'], 'server_changed');
      expect(provider.getById(id), isNotNull);
    },
  );

  for (final action in ['remove', 'set_tool', 'cancel_set_tool']) {
    test('queued settings writes guard the mutation: $action', () async {
      final fixture = McpServerConfig(
        id: 'queued',
        enabled: false,
        name: 'Original',
        transport: McpTransportType.http,
        url: 'https://example.test',
        tools: [McpToolConfig(name: 'echo', enabled: true)],
      );
      final harness = await createBusinessTestHarness(
        initial: {
          'mcp_servers_v1': jsonEncode([
            McpServerConfig(
              id: 'kelivo_fetch',
              enabled: false,
              name: '@kelivo/fetch',
              transport: McpTransportType.inmemory,
            ).toJson(),
            fixture.toJson(),
          ]),
        },
      );
      final queuedProvider = McpProvider(preferences: harness.preferences);
      addTearDown(queuedProvider.dispose);
      await queuedProvider.loaded;
      final locked = Completer<void>();
      final release = Completer<void>();
      final transaction = harness.database.transaction(() async {
        locked.complete();
        await release.future;
      });
      await locked.future;
      final writeStarted = Completer<void>();
      final settingsWrite = queuedProvider.updateServerMetadata(
        fixture.copyWith(
          name: action == 'cancel_set_tool' ? 'Original' : 'Changed',
        ),
        beforeCommit: writeStarted.complete,
      );
      await writeStarted.future;
      var allowed = true;
      final mutation =
          McpManagerTool(
            provider: queuedProvider,
            autoApproveAll: true,
            checkAllowed: () {
              if (!allowed) throw StateError('permission_denied');
            },
          ).execute({
            'action': action == 'remove' ? 'remove' : 'set_tool',
            'server_id': fixture.id,
            if (action != 'remove') ...{
              'tool_name': 'echo',
              'enabled': false,
              'needs_approval': true,
            },
          }, toolCallId: 'queued');
      await Future<void>.delayed(Duration.zero);
      if (action == 'cancel_set_tool') allowed = false;
      release.complete();
      await transaction;
      await settingsWrite;
      expect(
        jsonDecode(await mutation)['error'],
        action == 'cancel_set_tool' ? 'permission_denied' : 'server_changed',
      );
      final tool = queuedProvider.getById(fixture.id)!.tools.single;
      expect(tool.enabled, isTrue);
      expect(tool.needsApproval, isFalse);
      expect(
        queuedProvider.getById(fixture.id)!.name,
        action == 'cancel_set_tool' ? 'Original' : 'Changed',
      );
    });
  }

  test('opaque endpoint path credentials from settings are hidden', () async {
    const secret = 'PRIVATE_ENDPOINT_PATH';
    final id = await provider.addServer(
      enabled: false,
      name: 'Endpoint',
      transport: McpTransportType.http,
      url: 'https://mcp.example.test/api/$secret/mcp',
    );
    expect(
      jsonEncode(await run({'action': 'get', 'server_id': id})),
      isNot(contains(secret)),
    );
    final pending = run({'action': 'remove', 'server_id': id});
    await Future<void>.delayed(Duration.zero);
    expect(
      jsonEncode(approvals.pendingRequests.single.arguments),
      isNot(contains(secret)),
    );
    approvals.deny('call', conversationId: 'chat');
    await pending;
  });

  test('private tool names can be managed using safe aliases', () async {
    const secret = 'OPAQUE_TOOL_NAME_CREDENTIAL';
    final id = await provider.addServer(
      enabled: false,
      name: 'Private tool',
      transport: McpTransportType.stdio,
      command: 'srv',
      env: {'API_KEY': secret},
    );
    await provider.updateServer(
      provider
          .getById(id)!
          .copyWith(
            tools: [McpToolConfig(name: 'lookup_$secret', enabled: true)],
          ),
    );
    final listed = await run({'action': 'get', 'server_id': id});
    final name = listed['server']['tools'].single['name'] as String;
    expect(name, startsWith('mcp_tool_'));
    expect(name, isNot(contains(secret)));
    final pending = run({
      'action': 'set_tool',
      'server_id': id,
      'tool_name': name,
      'enabled': false,
      'needs_approval': true,
    });
    await Future<void>.delayed(Duration.zero);
    final request = approvals.pendingRequests.single;
    expect(request.arguments['tool_settings']['name'], name);
    expect(jsonEncode(request.arguments), isNot(contains(secret)));
    approvals.approve('call', conversationId: 'chat');
    final result = await pending;
    expect(result['ok'], isTrue, reason: '$result');
    expect(jsonEncode(result), isNot(contains(secret)));
    final tool = provider.getById(id)!.tools.single;
    expect(tool.name, 'lookup_$secret');
    expect(tool.enabled, isFalse);
    expect(tool.needsApproval, isTrue);
    expect(
      (await run({
        'action': 'set_tool',
        'server_id': id,
        'tool_name': tool.name,
        'enabled': true,
      }))['error'],
      'unknown_tool',
    );
  });

  test(
    'another server credential cannot leak through manager summaries',
    () async {
      const secret = 'OPAQUE_OTHER_SERVER_CREDENTIAL';
      await provider.addServer(
        enabled: false,
        name: 'Private',
        transport: McpTransportType.stdio,
        command: 'srv',
        env: {'API_KEY': secret},
      );
      final id = await provider.addServer(
        enabled: false,
        name: 'Other',
        transport: McpTransportType.http,
        url: 'https://example.test/mcp',
      );
      await provider.updateServer(
        provider
            .getById(id)!
            .copyWith(
              tools: [
                McpToolConfig(name: 'echo', description: secret, enabled: true),
              ],
            ),
      );
      expect(
        jsonEncode(await run({'action': 'get', 'server_id': id})),
        isNot(contains(secret)),
      );
      final pending = run({'action': 'remove', 'server_id': id});
      await Future<void>.delayed(Duration.zero);
      expect(
        jsonEncode(approvals.pendingRequests.single.arguments),
        isNot(contains(secret)),
      );
      approvals.deny('call', conversationId: 'chat');
      await pending;
      final literal =
          await McpManagerTool(
            provider: provider,
            autoApproveAll: true,
          ).execute({
            'action': 'add',
            'name': 'Copied private value',
            'config': {
              'command': 'srv',
              'disabled': true,
              'env': {'ORDINARY_NAME': secret},
            },
          }, toolCallId: 'copy');
      expect(jsonDecode(literal)['error'], 'secret_required');
    },
  );

  test(
    'settings rotation and JSON removal retain former credentials',
    () async {
      const oldSecret = 'ROTATED_HEADER_OLD_SENTINEL';
      const newSecret = 'ROTATED_HEADER_NEW_SENTINEL';
      final id = await provider.addServer(
        enabled: false,
        name: 'Rotating',
        transport: McpTransportType.http,
        url: 'https://example.test/mcp',
        headers: {'Authorization': oldSecret},
      );
      await provider.updateServer(
        provider
            .getById(id)!
            .copyWith(
              headers: {'Authorization': newSecret},
              tools: [
                McpToolConfig(
                  enabled: true,
                  name: 'echo',
                  description: '$oldSecret $newSecret',
                ),
              ],
            ),
      );
      final exported = jsonDecode(provider.exportServersAsUiJson()) as Map;
      exported['mcpServers'][id]['headers'] = <String, String>{};
      await provider.replaceAllFromJson(jsonEncode(exported));
      final result = jsonEncode(await run({'action': 'get', 'server_id': id}));
      expect(result, isNot(contains(oldSecret)));
      expect(result, isNot(contains(newSecret)));
      approvals.setAutoApproveAll(true);
      final renamed = jsonEncode(
        await run({'action': 'update', 'server_id': id, 'name': 'Renamed'}),
      );
      expect(renamed, isNot(contains(oldSecret)));
      expect(renamed, isNot(contains(newSecret)));
    },
  );

  test(
    'changing an OAuth resource keeps former tokens out of cached tools',
    () async {
      const secret = 'FORMER_OAUTH_PRIVATE_SENTINEL';
      final id = await provider.addServer(
        enabled: false,
        name: 'OAuth',
        transport: McpTransportType.http,
        url: 'https://example.test/mcp',
      );
      final saved = provider
          .getById(id)!
          .copyWith(
            oauth: const McpOAuthState(
              clientId: 'fixture',
              authorizationServer: 'https://auth.test',
              authorizationEndpoint: 'https://auth.test/authorize',
              tokenEndpoint: 'https://auth.test/token',
              resource: 'https://example.test/mcp',
              accessToken: secret,
            ),
            tools: [
              McpToolConfig(enabled: true, name: 'echo', description: secret),
            ],
          );
      await provider.replaceAllFromJson(jsonEncode([saved.toJson()]));
      expect(provider.getById(id)!.oauth, isNotNull);
      approvals.setAutoApproveAll(true);
      final result = await run({
        'action': 'update',
        'server_id': id,
        'config': {'url': 'https://other.test/mcp'},
      });
      expect(result['ok'], isTrue);
      expect(provider.getById(id)!.oauth, isNull);
      expect(jsonEncode(result), isNot(contains(secret)));
    },
  );

  test(
    'public URL arguments are accepted independently of output masking',
    () async {
      final pending = run({
        'action': 'add',
        'name': 'Bridge',
        'config': {
          'command': 'node',
          'args': [
            'https://example.test/service/mcp',
            'https://example.test/api/mcp/a/{{TOKEN}}/mcp',
          ],
          'disabled': true,
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(approvals.pendingRequests, hasLength(1));
      approvals.approve(
        'call',
        conversationId: 'chat',
        secretValues: {'TOKEN': 'PRIVATE_BRIDGE_SENTINEL'},
      );
      final result = await pending;
      expect(result['ok'], isTrue);
      expect(jsonEncode(result), isNot(contains('PRIVATE_BRIDGE_SENTINEL')));
    },
  );

  test('add → test → remove uses a real connection to a fixture', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method == 'DELETE') {
        await request.response.close();
        return;
      }
      final rpc = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final id = rpc['id'];
      if (id == null) {
        request.response.statusCode = 202;
        await request.response.close();
        return;
      }
      final result = switch (rpc['method']) {
        'initialize' => {
          'protocolVersion': '2025-03-26',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'Fixture', 'version': '1'},
        },
        'tools/list' => {
          'tools': [
            {
              'name': 'echo',
              'description': 'Fixture tool',
              'inputSchema': {'type': 'object'},
            },
          ],
        },
        _ => <String, dynamic>{},
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
      );
      await request.response.close();
    });
    approvals.setAutoApproveAll(true);
    final added = await run({
      'action': 'add',
      'name': 'Fixture',
      'config': {'type': 'http', 'url': 'http://127.0.0.1:${server.port}/mcp'},
    });
    final id = added['server']['id'];
    expect(added['availability_notice'], contains('next message'));
    final tested = await run({'action': 'test', 'server_id': id});
    expect(tested['connected'], isTrue, reason: '$tested');
    expect(tested['tool_count'], 1);
    expect(tested['tools'].single['name'], 'echo');
    expect(tested['availability_notice'], contains('next message'));
    for (final action in ['refresh', 'reconnect']) {
      final refreshed = await run({'action': action, 'server_id': id});
      expect(refreshed['ok'], isTrue, reason: '$refreshed');
      expect(refreshed['server']['tool_count'], 1);
      expect(refreshed['server']['tools'].single['name'], 'echo');
    }
    final updated = await run({
      'action': 'update',
      'server_id': id,
      'name': 'Updated fixture',
    });
    expect(updated['availability_notice'], contains('next message'));
    await run({'action': 'disable', 'server_id': id});
    final listed = await run({'action': 'list'});
    final disabled = (listed['servers'] as List).singleWhere(
      (s) => s['id'] == id,
    );
    expect(disabled['tools'].single['enabled'], isFalse);
    final enabled = await run({'action': 'enable', 'server_id': id});
    expect(enabled['availability_notice'], contains('next message'));
    expect((await run({'action': 'remove', 'server_id': id}))['ok'], isTrue);
    expect(provider.getById(id), isNull);
  });

  test('test reports a connection error without echoed credentials', () async {
    const secret = 'MCP_ERROR_PRIVATE_SENTINEL';
    final server = await _errorServer('Fixture failed: $secret');
    final pending = run({
      'action': 'add',
      'name': 'Failing fixture',
      'config': {
        'type': 'http',
        'url': 'http://127.0.0.1:${server.port}/mcp',
        'headers': {'Authorization': ''},
      },
    });
    await Future<void>.delayed(Duration.zero);
    approvals.approve(
      'call',
      conversationId: 'chat',
      secretValues: {'header:Authorization': 'Bearer $secret'},
    );
    final added = await pending;
    final result = await run({
      'action': 'test',
      'server_id': added['server']['id'],
    });
    expect(result['connected'], isFalse);
    expect(result['tool_count'], 0);
    expect(result['error'], contains('Fixture failed'));
    expect(jsonEncode(result), isNot(contains(secret)));
    expect(FlutterLogger.technicalTail, isNot(contains(secret)));
    expect(approvals.pendingRequests, isEmpty);
  });

  test(
    'automatic OAuth refresh keeps previous tokens private after failure',
    () async {
      const secret = 'EXPIRED_OAUTH_PRIVATE_SENTINEL';
      final server = await _errorServer('Fixture failed: $secret');
      var refreshCalls = 0;
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://auth.test/token');
        refreshCalls++;
        return http.Response(
          jsonEncode({
            'access_token': 'FRESH_OAUTH_PRIVATE_SENTINEL',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final oauth = McpOAuthService(httpClient: client);
      final refreshedProvider = McpProvider(
        preferences: createBusinessTestPreferences(),
        oauthService: oauth,
      );
      addTearDown(refreshedProvider.dispose);
      addTearDown(oauth.dispose);
      await refreshedProvider.loaded;
      final url = 'http://127.0.0.1:${server.port}/mcp';
      final id = await refreshedProvider.addServer(
        enabled: true,
        name: 'Refreshing',
        transport: McpTransportType.http,
        url: url,
        oauth: McpOAuthState(
          clientId: 'fixture',
          authorizationServer: 'https://auth.test',
          authorizationEndpoint: 'https://auth.test/authorize',
          tokenEndpoint: 'https://auth.test/token',
          resource: url,
          accessToken: secret,
          refreshToken: 'PRIVATE_REFRESH_SENTINEL',
          expiresAt: DateTime(2000),
        ),
      );
      final result = jsonDecode(
        await McpManagerTool(provider: refreshedProvider).execute({
          'action': 'test',
          'server_id': id,
        }, toolCallId: 'refresh-test'),
      );
      expect(refreshCalls, 1);
      expect(
        refreshedProvider.getById(id)!.oauth!.accessToken,
        'FRESH_OAUTH_PRIVATE_SENTINEL',
      );
      expect(result['connected'], isFalse);
      expect(result['error'], contains('Fixture failed'));
      expect(jsonEncode(result), isNot(contains(secret)));
    },
  );
}
