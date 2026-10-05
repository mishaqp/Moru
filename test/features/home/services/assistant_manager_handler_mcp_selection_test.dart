import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/workspace_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/skills/skills_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final alreadySelected in [true, false]) {
    testWidgets(
      alreadySelected
          ? 'assistant handler keeps configured STDIO selection during an unrelated update while environment is unavailable'
          : 'assistant handler accepts a newly selected configured STDIO server while environment is unavailable',
      (tester) async {
        final setup = (await tester.runAsync(() async {
          final directory = await Directory.systemTemp.createTemp(
            'moru_assistant_mcp_catalog_',
          );
          addTearDown(() => directory.delete(recursive: true));
          final harness = await createBusinessTestHarness(
            initial: {
              'assistants_v1': jsonEncode([
                {
                  'id': 'assistant',
                  'name': 'Assistant',
                  'localToolIds': [LocalToolNames.assistantManager],
                  'mcpServerIds': [if (alreadySelected) 'stdio'],
                },
              ]),
              'mcp_servers_v1': jsonEncode([
                McpServerConfig(
                  id: 'stdio',
                  name: 'Saved STDIO',
                  enabled: false,
                  transport: McpTransportType.stdio,
                  command: 'mcp-server-fixture',
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
          final assistants = AssistantProvider(
            preferences: harness.preferences,
          );
          final settings = SettingsProvider(harness.preferences);
          final mcp = McpProvider(preferences: harness.preferences);
          final store = ExtensionEntityStore(harness.database);
          final workspaces = WorkspaceProvider(store: store);
          final skills = SkillsService(
            store: store,
            skillsDirectory: directory,
          );
          final tools = McpToolService();
          final approvals = ToolApprovalService()..setAutoApproveAll(true);
          for (final notifier in [
            assistants,
            settings,
            mcp,
            workspaces,
            skills,
            tools,
            approvals,
          ]) {
            addTearDown(notifier.dispose);
          }
          await Future.wait([
            assistants.loaded,
            settings.loaded,
            mcp.loaded,
            workspaces.loaded,
            skills.loaded,
          ]);
          await settings.setToolAutoApproveAll(true);
          assistants.bindMcpServers(
            liveMcpServerIds: () =>
                mcp.configuredServers.map((server) => server.id).toSet(),
            mcpServersLoaded: mcp.loaded,
          );
          expect(mcp.supportsStdio, isFalse);
          expect(
            mcp.servers.map((server) => server.id),
            isNot(contains('stdio')),
          );
          expect(
            mcp.configuredServers.map((server) => server.id),
            contains('stdio'),
          );
          return (
            harness: harness,
            assistants: assistants,
            settings: settings,
            mcp: mcp,
            workspaces: workspaces,
            skills: skills,
            tools: tools,
            approvals: approvals,
          );
        }))!;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AssistantProvider>.value(
                value: setup.assistants,
              ),
              ChangeNotifierProvider<SettingsProvider>.value(
                value: setup.settings,
              ),
              ChangeNotifierProvider<McpProvider>.value(value: setup.mcp),
              ChangeNotifierProvider<WorkspaceProvider>.value(
                value: setup.workspaces,
              ),
              ChangeNotifierProvider<SkillsService>.value(value: setup.skills),
              ChangeNotifierProvider<McpToolService>.value(value: setup.tools),
            ],
            child: const SizedBox.shrink(),
          ),
        );
        final handler =
            ToolHandlerService(
              contextProvider: tester.element(find.byType(SizedBox)),
            ).buildToolCallHandler(
              setup.settings,
              setup.assistants.getById('assistant'),
              approvalService: setup.approvals,
              conversationId: 'chat',
            )!;
        try {
          await tester.runAsync(() async {
            final result =
                jsonDecode(
                      await handler(LocalToolNames.assistantManager, {
                            'action': 'update',
                            'assistant_id': 'assistant',
                            'settings': {
                              'name': 'Renamed',
                              if (!alreadySelected) 'mcpServerIds': ['stdio'],
                            },
                          })
                          as String,
                    )
                    as Map<String, dynamic>;
            expect(result['ok'], isTrue, reason: '$result');
            expect(setup.assistants.getById('assistant')!.mcpServerIds, [
              'stdio',
            ]);
            final saved =
                jsonDecode(
                      setup.harness.preferences.getString('assistants_v1')!,
                    )
                    as List;
            expect(saved.single['mcpServerIds'], ['stdio']);
            expect(saved.single['name'], 'Renamed');
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
