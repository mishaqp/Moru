import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_server.dart';
import 'package:Kelivo/features/home/services/built_in_tool_names.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';

import '../../../support/business_test_harness.dart';

void main() {
  test('report_problem is reserved, opt-in and always requires approval', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const disabled = Assistant(id: 'test', name: 'Test');
    final enabled = disabled.copyWith(localToolIds: ['report_problem']);
    expect(BuiltInToolNames.all, contains('report_problem'));
    for (final assistant in [disabled, enabled]) {
      final names = LocalToolsService.buildToolDefinitions(
        assistant: assistant,
        supportsTools: true,
      ).map((tool) => tool['function']['name']);
      expect(names.contains('report_problem'), identical(assistant, enabled));
    }
    expect(
      LocalToolNames.requiresApprovalFor('report_problem', const {}),
      isTrue,
    );
    expect(
      AcpMcpServer.moruTools(
        LocalToolsService.buildToolDefinitions(
          assistant: enabled,
          supportsTools: true,
        ),
      ).map((tool) => tool['name']),
      contains('report_problem'),
    );
  });

  testWidgets(
    'a newly enabled report still asks before collecting data',
    (tester) async {
      final preferences = createBusinessTestPreferences();
      final assistants = AssistantProvider(preferences: preferences);
      final settings = SettingsProvider(preferences);
      final mcp = McpProvider(preferences: preferences);
      final tools = McpToolService();
      final approvals = ToolApprovalService()..setAutoApproveAll(true);
      for (final notifier in [assistants, settings, mcp, tools, approvals]) {
        addTearDown(notifier.dispose);
      }
      await assistants.loaded;
      await settings.loaded;
      final id = await assistants.addAssistant(name: 'Test');
      final oldSnapshot = assistants.getById(id)!;
      await assistants.updateAssistant(
        oldSnapshot.copyWith(localToolIds: ['report_problem']),
      );
      await tester.pumpWidget(
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
      final handler =
          ToolHandlerService(
            contextProvider: tester.element(find.byType(SizedBox)),
          ).buildToolCallHandler(
            settings,
            oldSnapshot,
            approvalService: approvals,
            conversationId: 'chat',
          )!;
      final result = handler('report_problem', {}, toolCallId: 'report');
      await tester.pump();
      expect(approvals.pendingRequests, hasLength(1));
      approvals.deny('report', conversationId: 'chat');
      expect(jsonDecode(await result as String)['error'], 'approval_denied');
      final unavailable =
          ToolHandlerService(
            contextProvider: tester.element(find.byType(SizedBox)),
          ).buildToolCallHandler(
            settings,
            assistants.getById(id),
            conversationId: 'chat',
          )!;
      expect(
        jsonDecode(await unavailable('report_problem', {}) as String)['error'],
        'approval_unavailable',
      );
      final revoked = handler('report_problem', {}, toolCallId: 'revoked');
      await tester.pump();
      expect(approvals.pendingRequests, hasLength(1));
      await assistants.updateAssistant(oldSnapshot);
      approvals.approve('revoked', conversationId: 'chat');
      expect(jsonDecode(await revoked as String)['error'], 'permission_denied');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
