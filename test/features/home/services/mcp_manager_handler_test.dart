import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';

import '../../../support/business_test_harness.dart';

void main() {
  late AssistantProvider assistants;
  late SettingsProvider settings;
  late McpProvider mcp;
  late McpToolService tools;
  late ToolApprovalService approvals;

  setUp(() async {
    final preferences = createBusinessTestPreferences();
    assistants = AssistantProvider(preferences: preferences);
    settings = SettingsProvider(preferences);
    mcp = McpProvider(preferences: preferences);
    tools = McpToolService();
    approvals = ToolApprovalService()..setAutoApproveAll(true);
    await Future.wait([assistants.loaded, settings.loaded, mcp.loaded]);
  });

  tearDown(() {
    for (final notifier in [assistants, settings, mcp, tools, approvals]) {
      notifier.dispose();
    }
  });

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

  const add = {
    'action': 'add',
    'name': 'Fixture',
    'config': {
      'type': 'http',
      'url': 'https://example.test/mcp',
      'disabled': true,
    },
  };

  testWidgets(
    'handler validates live permissions and consent before changing MCP',
    (tester) async {
      final snapshot = (await tester.runAsync(() async {
        final id = await assistants.addAssistant(name: 'Test');
        final snapshot = assistants.getById(id)!;
        await assistants.updateAssistant(
          snapshot.copyWith(localToolIds: ['manage_mcp']),
        );
        return snapshot;
      }))!;
      await mount(tester);
      final handler =
          ToolHandlerService(
            contextProvider: tester.element(find.byType(SizedBox)),
          ).buildToolCallHandler(
            settings,
            snapshot,
            approvalService: approvals,
            conversationId: 'chat',
          )!;
      try {
        await tester.runAsync(() async {
          final unknown = jsonDecode(
            await handler('manage_mcp', {
                  'action': 'remove',
                  'server_id': 'missing',
                }, toolCallId: 'unknown')
                as String,
          );
          expect(unknown['error'], 'unknown_server');
          expect(approvals.pendingRequests, isEmpty);

          final pending = handler('manage_mcp', add, toolCallId: 'add');
          await Future<void>.delayed(Duration.zero);
          expect(approvals.pendingRequests, hasLength(1));
          expect(
            approvals.pendingRequests.single.requiresExplicitConsent,
            isTrue,
          );
          expect(
            approvals.pendingRequests.single.arguments['server']['name'],
            'Fixture',
          );
          approvals.deny('add', conversationId: 'chat');
          expect(
            jsonDecode(await pending as String)['error'],
            'approval_denied',
          );

          final unavailable = ToolHandlerService(
            contextProvider: tester.element(find.byType(SizedBox)),
          ).buildToolCallHandler(settings, snapshot, conversationId: 'chat')!;
          expect(
            jsonDecode(await unavailable('manage_mcp', add) as String)['error'],
            'approval_unavailable',
          );

          final revoked = handler('manage_mcp', add, toolCallId: 'revoked');
          await Future<void>.delayed(Duration.zero);
          await assistants.updateAssistant(snapshot);
          approvals.approve('revoked', conversationId: 'chat');
          expect(
            jsonDecode(await revoked as String)['error'],
            'permission_denied',
          );
          expect(
            mcp.configuredServers.where((s) => s.name == 'Fixture'),
            isEmpty,
          );
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final withApprovals in [true, false]) {
    testWidgets(
      'handler full trust bypasses MCP consent (service: $withApprovals)',
      (tester) async {
        final assistant = (await tester.runAsync(() async {
          await settings.setToolAutoApproveAll(true);
          // Sync settings before the approval provider rebuilds.
          approvals.setAutoApproveAll(false);
          final id = await assistants.addAssistant(name: 'Test');
          final assistant = assistants
              .getById(id)!
              .copyWith(localToolIds: ['manage_mcp']);
          await assistants.updateAssistant(assistant);
          return assistant;
        }))!;
        await mount(tester);
        final handler =
            ToolHandlerService(
              contextProvider: tester.element(find.byType(SizedBox)),
            ).buildToolCallHandler(
              settings,
              assistant,
              approvalService: withApprovals ? approvals : null,
              conversationId: 'chat',
            )!;
        try {
          await tester.runAsync(() async {
            final added = jsonDecode(
              await handler('manage_mcp', add) as String,
            );
            expect(added['ok'], isTrue);
            expect(approvals.pendingRequests, isEmpty);
            final missing = jsonDecode(
              await handler('manage_mcp', {
                    'action': 'update',
                    'server_id': added['server']['id'],
                    'config': {
                      'headers': {'Authorization': ''},
                    },
                  })
                  as String,
            );
            expect(missing['error'], 'secret_required');
            expect(mcp.getById(added['server']['id'])!.headers, isEmpty);
            final removed = jsonDecode(
              await handler('manage_mcp', {
                    'action': 'remove',
                    'server_id': added['server']['id'],
                  })
                  as String,
            );
            expect(removed['ok'], isTrue);
            expect(mcp.getById(added['server']['id']), isNull);
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
