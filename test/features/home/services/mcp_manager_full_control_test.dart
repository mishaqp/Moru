import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/home/services/mcp_manager_tool.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';

import '../../../support/business_test_harness.dart';

class _App {
  _App(
    this.assistants,
    this.settings,
    this.mcp,
    this.tools,
    this.approvals,
    this.currentId,
    this.otherId,
  );

  final AssistantProvider assistants;
  final SettingsProvider settings;
  final McpProvider mcp;
  final McpToolService tools;
  final ToolApprovalService approvals;
  final String currentId;
  final String otherId;

  static Future<_App> create() async {
    final harness = await createBusinessTestHarness(
      initial: {
        'mcp_servers_v1': jsonEncode([
          McpServerConfig(
            id: 'fixture',
            name: 'Fixture',
            enabled: false,
            transport: McpTransportType.stdio,
            command: 'fixture-not-installed',
            tools: [McpToolConfig(name: 'echo', enabled: true)],
          ).toJson(),
          McpServerConfig(
            id: 'kelivo_fetch',
            name: '@kelivo/fetch',
            enabled: false,
            transport: McpTransportType.inmemory,
          ).toJson(),
        ]),
      },
    );
    final assistants = AssistantProvider(preferences: harness.preferences);
    final settings = SettingsProvider(harness.preferences);
    final mcp = McpProvider(preferences: harness.preferences);
    final tools = McpToolService();
    final approvals = ToolApprovalService();
    for (final provider in [assistants, settings, mcp, tools, approvals]) {
      addTearDown(provider.dispose);
    }
    await Future.wait([assistants.loaded, settings.loaded, mcp.loaded]);
    final current = await assistants.addAssistant(name: 'Current');
    final other = await assistants.addAssistant(name: 'Other');
    await assistants.updateAssistant(
      assistants.getById(current)!.copyWith(localToolIds: ['manage_mcp']),
    );
    await settings.setToolAutoApproveAll(true);
    return _App(assistants, settings, mcp, tools, approvals, current, other);
  }

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<McpProvider>.value(value: mcp),
        ChangeNotifierProvider<McpToolService>.value(value: tools),
      ],
      child: const SizedBox.shrink(),
    ),
  );

  Future<Map<String, dynamic>> call(
    WidgetTester tester,
    Map<String, dynamic> args,
  ) async {
    final handler =
        ToolHandlerService(
          contextProvider: tester.element(find.byType(SizedBox)),
        ).buildToolCallHandler(
          settings,
          assistants.getById(currentId),
          approvalService: approvals,
          conversationId: 'chat',
        )!;
    return jsonDecode(
          await handler('manage_mcp', args, toolCallId: 'call') as String,
        )
        as Map<String, dynamic>;
  }
}

void main() {
  test('definition exposes complete MCP management actions', () {
    final function = McpManagerTool.definition['function'] as Map;
    expect(
      function['parameters']['properties']['action']['enum'],
      containsAll([
        'select',
        'unselect',
        'set_tool',
        'refresh',
        'reconnect',
        'import',
        'set_timeout',
      ]),
    );
  });

  testWidgets('full trust selects assistants and configures individual tools', (
    tester,
  ) async {
    final app = (await tester.runAsync(_App.create))!;
    await app.mount(tester);
    try {
      await tester.runAsync(() async {
        for (final id in [app.currentId, app.otherId]) {
          final selected = await app.call(tester, {
            'action': 'select',
            'server_id': 'fixture',
            if (id == app.otherId) 'assistant_id': id,
          });
          expect(selected['ok'], isTrue, reason: '$selected');
          expect(app.assistants.getById(id)!.mcpServerIds, contains('fixture'));
        }
        final configured = await app.call(tester, {
          'action': 'set_tool',
          'server_id': 'fixture',
          'tool_name': 'echo',
          'enabled': false,
          'needs_approval': true,
        });
        expect(configured['ok'], isTrue, reason: '$configured');
        final tool = app.mcp.getById('fixture')!.tools.single;
        expect(tool.enabled, isFalse);
        expect(tool.needsApproval, isTrue);
        final summary = configured['server']['tools'].single;
        expect(summary['needs_approval'], isTrue);
        final unselected = await app.call(tester, {
          'action': 'unselect',
          'server_id': 'fixture',
          'assistant_id': app.otherId,
        });
        expect(unselected['ok'], isTrue);
        expect(
          app.assistants.getById(app.otherId)!.mcpServerIds,
          isNot(contains('fixture')),
        );
        expect(
          app.assistants.getById(app.currentId)!.mcpServerIds,
          contains('fixture'),
        );
        for (final invalid in [
          {
            'action': 'select',
            'server_id': 'fixture',
            'assistant_id': 'missing',
          },
          {
            'action': 'set_tool',
            'server_id': 'fixture',
            'tool_name': 'missing',
            'enabled': false,
          },
        ]) {
          expect((await app.call(tester, invalid))['ok'], isFalse);
        }
        expect(app.approvals.pendingRequests, isEmpty);
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
    'add and enable select the chat assistant and remove cleans selections',
    (tester) async {
      final app = (await tester.runAsync(_App.create))!;
      await app.mount(tester);
      try {
        await tester.runAsync(() async {
          final added = await app.call(tester, {
            'action': 'add',
            'name': 'Memory',
            'config': {
              'command': 'mcp-server-memory',
              'disabled': true,
              'env': {'MEMORY_FILE_PATH': '/workspace/x.json'},
            },
          });
          expect(added['ok'], isTrue);
          final id = added['server']['id'];
          expect(
            app.assistants.getById(app.currentId)!.mcpServerIds,
            contains(id),
          );
          await app.call(tester, {'action': 'unselect', 'server_id': id});
          final enabled = await app.call(tester, {
            'action': 'enable',
            'server_id': id,
          });
          expect(enabled['ok'], isTrue);
          expect(
            app.assistants.getById(app.currentId)!.mcpServerIds,
            contains(id),
          );
          await app.call(tester, {
            'action': 'select',
            'server_id': id,
            'assistant_id': app.otherId,
          });
          expect(
            (await app.call(tester, {
              'action': 'remove',
              'server_id': id,
            }))['ok'],
            isTrue,
          );
          for (final assistantId in [app.currentId, app.otherId]) {
            expect(
              app.assistants.getById(assistantId)!.mcpServerIds,
              isNot(contains(id)),
            );
          }
          expect(app.approvals.pendingRequests, isEmpty);
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'full trust imports atomically and changes the existing global timeout',
    (tester) async {
      final app = (await tester.runAsync(_App.create))!;
      await app.mount(tester);
      try {
        await tester.runAsync(() async {
          final imported = await app.call(tester, {
            'action': 'import',
            'json': jsonEncode({
              'mcpServers': {
                'Memory': {
                  'command': 'mcp-server-memory',
                  'disabled': true,
                  'cwd': '/workspace',
                  'env': {'MEMORY_FILE_PATH': '/workspace/x.json'},
                },
                'Thinking': {
                  'command': 'mcp-server-sequential-thinking',
                  'disabled': true,
                },
              },
            }),
          });
          expect(imported['ok'], isTrue, reason: '$imported');
          expect(imported['servers'], hasLength(2));
          expect(
            app.assistants.getById(app.currentId)!.mcpServerIds,
            containsAll((imported['servers'] as List).map((s) => s['id'])),
          );
          final previous = app.mcp.configuredServers.length;
          final rejected = await app.call(tester, {
            'action': 'import',
            'json': jsonEncode({
              'mcpServers': {
                'Good': {'command': 'srv', 'disabled': true},
                'Bad': {
                  'command': 'srv',
                  'env': {'API_KEY': 'sk-private-literal'},
                },
              },
            }),
          });
          expect(rejected['error'], 'secret_required');
          expect(app.mcp.configuredServers, hasLength(previous));
          final changed = await app.call(tester, {
            'action': 'set_timeout',
            'timeout_seconds': 45,
          });
          expect(changed['ok'], isTrue);
          expect(app.mcp.requestTimeoutSeconds, 45);
          expect(
            (await app.call(tester, {
              'action': 'set_timeout',
              'timeout_seconds': 0,
            }))['ok'],
            isFalse,
          );
          expect(app.approvals.pendingRequests, isEmpty);
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  for (final trusted in [true, false]) {
    testWidgets(
      'import collects private fields and reuses them: trust=$trusted',
      (tester) async {
        final app = (await tester.runAsync(_App.create))!;
        await app.mount(tester);
        try {
          await tester.runAsync(() async {
            await app.settings.setToolAutoApproveAll(trusted);
            final arguments = {
              'action': 'import',
              'json': jsonEncode({
                'mcpServers': {
                  'Private STDIO': {
                    'command': 'srv',
                    'disabled': true,
                    'env': {'API_KEY': ''},
                  },
                  'Private HTTP': {
                    'url': 'https://example.com/mcp',
                    'disabled': true,
                    'headers': {'Authorization': ''},
                  },
                },
              }),
            };
            final before = app.mcp.configuredServers.length;
            final cancelled = app.call(tester, arguments);
            while (app.approvals.pendingRequests.isEmpty) {
              await Future<void>.delayed(Duration.zero);
            }
            expect(app.mcp.configuredServers, hasLength(before));
            final first = app.approvals.pendingRequests.single;
            expect(first.secretInputOnly, trusted);
            expect(first.requiresExplicitConsent, isTrue);
            app.approvals.deny('call', conversationId: 'chat');
            expect((await cancelled)['error'], 'approval_denied');
            expect(app.mcp.configuredServers, hasLength(before));

            final imported = app.call(tester, arguments);
            while (app.approvals.pendingRequests.isEmpty) {
              await Future<void>.delayed(Duration.zero);
            }
            final request = app.approvals.pendingRequests.single;
            expect(request.secretInputOnly, trusted);
            expect(
              request.secretFields,
              unorderedEquals([
                'Private STDIO / env:API_KEY',
                'Private HTTP / header:Authorization',
              ]),
            );
            const key = 'sk-user-entered-private-key';
            const authorization = 'Bearer user-entered-private-token';
            app.approvals.approve(
              'call',
              conversationId: 'chat',
              secretValues: {
                'Private STDIO / env:API_KEY': key,
                'Private HTTP / header:Authorization': authorization,
              },
            );
            final result = await imported;
            expect(result['ok'], isTrue, reason: '$result');
            for (final visible in [
              jsonEncode(arguments),
              jsonEncode(request.arguments),
              jsonEncode(result),
            ]) {
              expect(visible, isNot(contains(key)));
              expect(visible, isNot(contains(authorization)));
            }
            final stdio = app.mcp.configuredServers.singleWhere(
              (server) => server.name == 'Private STDIO',
            );
            expect(stdio.env['API_KEY'], key);
            expect(stdio.managedSecrets['env:API_KEY'], key);
            final http = app.mcp.configuredServers.singleWhere(
              (server) => server.name == 'Private HTTP',
            );
            expect(http.managedSecrets['header:Authorization'], authorization);

            // Reusing this server's named credential needs no new private input.
            await app.settings.setToolAutoApproveAll(true);
            final reused = await app.call(tester, {
              'action': 'update',
              'server_id': stdio.id,
              'config': {
                'args': ['--key', '{{API_KEY}}'],
                'cwd': '/workspace/data',
                'workspaceId': null,
              },
            });
            expect(reused['ok'], isTrue, reason: '$reused');
            final updated = app.mcp.getById(stdio.id)!;
            expect(updated.args, ['--key', key]);
            expect(updated.workingDirectory, '/workspace/data');
            expect(updated.workspaceId, isNull);
            expect(jsonEncode(reused), isNot(contains(key)));
            expect(app.approvals.pendingRequests, isEmpty);
            final cleared = await app.call(tester, {
              'action': 'update',
              'server_id': stdio.id,
              'config': {'cwd': null},
            });
            expect(cleared['ok'], isTrue, reason: '$cleared');
            expect(app.mcp.getById(stdio.id)!.workingDirectory, isNull);
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
