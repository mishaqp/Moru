import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/tool_call_argument_privacy.dart';
import 'package:Kelivo/core/services/skills/skills_service.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

import '../../../support/business_test_harness.dart';
import '../../workspace/skills/skills_test_fakes.dart';

void main() {
  late AssistantProvider assistants;
  late SettingsProvider settings;
  late _PolicyMcpProvider servers;
  late McpToolService tools;
  late Assistant assistant;

  setUp(() async {
    final preferences = createBusinessTestPreferences();
    assistants = AssistantProvider(preferences: preferences);
    settings = SettingsProvider(preferences);
    servers = _PolicyMcpProvider();
    tools = McpToolService();
    for (final provider in [assistants, settings, servers, tools]) {
      addTearDown(provider.dispose);
    }
    await assistants.loaded;
    await settings.loaded;
    final id = await assistants.addAssistant(name: 'Caller');
    assistant = assistants
        .getById(id)!
        .copyWith(
          localToolIds: [
            LocalToolNames.assistantManager,
            LocalToolNames.calendarCreate,
          ],
          mcpServerIds: ['server'],
          searchEnabled: true,
        );
    await assistants.updateAssistant(assistant);
  });

  Future<ToolCallHandler> build(
    WidgetTester tester, {
    ToolApprovalService? approval,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<McpProvider>.value(value: servers),
          ChangeNotifierProvider<McpToolService>.value(value: tools),
          ChangeNotifierProvider<SkillsService>(
            create: (_) => FakeSkillsService(),
          ),
          ChangeNotifierProvider<WorkspaceProvider>(
            create: (_) => _EmptyWorkspaces(),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    return ToolHandlerService(
      contextProvider: tester.element(find.byType(SizedBox)),
    ).buildToolCallHandler(
      settings,
      assistant,
      approvalService: approval,
      conversationId: 'chat',
    )!;
  }

  Map<String, dynamic> error(Object? result) {
    final content = ClientToolResult.fromHandler(result).content;
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {'content': content};
    }
  }

  testWidgets(
    'MCP approval is required when no approval service is available',
    (tester) async {
      final call = await build(tester);
      expect(error(await call('remote', {}))['error'], 'approval_unavailable');
      expect(servers.arguments, isEmpty);
    },
  );

  testWidgets(
    'full access runs MCP and assistant mutations without an approval service',
    (tester) async {
      await tester.runAsync(() => settings.setToolAutoApproveAll(true));
      final call = await build(tester);
      await call('remote', {});
      expect(servers.arguments, [{}]);
      final result = error(
        await tester.runAsync<Object?>(
          () => call('manage_assistants', {
            'action': 'create',
            'settings': {'name': 'Created'},
          }),
        ),
      );
      expect(result['ok'], true, reason: result.toString());
      expect(assistants.assistants.map((a) => a.name), contains('Created'));
    },
  );

  testWidgets(
    'assistant secrets are hidden by the registered handler and approval',
    (tester) async {
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      final call = await build(tester, approval: approvals);
      const secret = 'new-private-assistant-header';
      final arguments = <String, dynamic>{
        'action': 'update',
        'assistant_id': assistant.id,
        'settings': {
          'customHeaders': [
            {'name': 'Authorization', 'value': secret},
          ],
          'systemPrompt': 'Keep $secret private',
        },
      };
      expect(
        jsonEncode(
          ToolCallArgumentPrivacy.argumentsForModel(
            call,
            'manage_assistants',
            arguments,
          ),
        ),
        isNot(contains(secret)),
      );
      final pending = call(
        'manage_assistants',
        arguments,
        toolCallId: 'private-update',
      );
      await tester.pump();
      expect(
        jsonEncode(approvals.pendingRequests.single.arguments),
        isNot(contains(secret)),
      );
      approvals.deny('private-update', conversationId: 'chat');
      expect(error(await pending)['error'], 'approval_denied');
      expect(arguments['settings']['customHeaders'][0]['value'], secret);
      expect(assistants.getById(assistant.id)!.customHeaders, isEmpty);
    },
  );

  testWidgets('calendar mutation cannot proceed when approval is unavailable', (
    tester,
  ) async {
    final call = await build(tester);
    expect(
      error(
        await tester.runAsync<Object?>(() => call('calendar_create', {})),
      )['error'],
      'approval_unavailable',
    );
  });

  testWidgets('permission revoked during consent prevents assistant mutation', (
    tester,
  ) async {
    final approval = ToolApprovalService();
    addTearDown(approval.dispose);
    final call = await build(tester, approval: approval);
    final pending = call('manage_assistants', {
      'action': 'create',
      'settings': {'name': 'Forbidden'},
    }, toolCallId: 'create');
    await tester.pump();
    await tester.runAsync(
      () => assistants.updateAssistant(assistant.copyWith(localToolIds: [])),
    );
    approval.approve('create', conversationId: 'chat');
    expect(
      error(await tester.runAsync<Object?>(() => pending))['error'],
      'permission_denied',
    );
    expect(
      assistants.assistants.map((a) => a.name),
      isNot(contains('Forbidden')),
    );
  });

  testWidgets('search validates required query before network work', (
    tester,
  ) async {
    final call = await build(tester);
    for (final value in [null, '', '  ', 3, <String>[]]) {
      final result = error(
        await tester.runAsync<Object?>(
          () => call('search_web', {'query': value}),
        ),
      );
      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('query'));
    }
  });

  testWidgets('MCP execution uses source schema to omit synthetic nulls', (
    tester,
  ) async {
    await tester.runAsync(() => settings.setToolAutoApproveAll(true));
    final call = await build(tester);
    final args = <String, dynamic>{
      'optional': null,
      'nullable': null,
      'needed': null,
      'nested': {'optional': null},
    };
    await call('remote', args);
    expect(servers.arguments.single, {
      'nullable': null,
      'needed': null,
      'nested': <String, dynamic>{},
    });
    expect(args, contains('optional'));
  });

  testWidgets('MCP legacy parameter descriptors use the same null contract', (
    tester,
  ) async {
    servers.schemaSupplied = false;
    await tester.runAsync(() => settings.setToolAutoApproveAll(true));
    final call = await build(tester);
    await call('remote', {'optional': null, 'needed': null, 'unknown': null});
    expect(servers.arguments.single, {'needed': null, 'unknown': null});
  });
}

class _EmptyWorkspaces extends ChangeNotifier implements WorkspaceProvider {
  @override
  List<Workspace> get workspaces => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PolicyMcpProvider extends McpProvider {
  _PolicyMcpProvider() : super(preferences: createBusinessTestPreferences());
  final List<Map<String, dynamic>> arguments = [];
  bool schemaSupplied = true;

  @override
  List<McpServerConfig> get servers => [
    McpServerConfig(
      id: 'server',
      enabled: true,
      name: 'Server',
      transport: McpTransportType.http,
      tools: [
        McpToolConfig(
          enabled: true,
          name: 'remote',
          needsApproval: true,
          params: [
            McpParamSpec(name: 'optional', required: false, type: 'integer'),
            McpParamSpec(name: 'needed', required: true, type: 'integer'),
          ],
          schema: schemaSupplied
              ? {
                  'type': 'object',
                  'properties': {
                    'optional': {'type': 'integer'},
                    'nullable': {
                      'type': ['string', 'null'],
                    },
                    'needed': {'type': 'integer'},
                    'nested': {
                      'type': 'object',
                      'properties': {
                        'optional': {'type': 'string'},
                      },
                    },
                  },
                  'required': ['needed'],
                }
              : null,
        ),
      ],
    ),
  ];

  @override
  Future<void> connect(String id) async {}

  @override
  Future<mcp.CallToolResult?> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    arguments.add(args);
    return mcp.CallToolResult([const mcp.TextContent(text: 'done')]);
  }
}
