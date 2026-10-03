import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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

class _ReportPathProvider extends PathProviderPlatform {
  _ReportPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
}

void main() {
  test('report_problem is reserved, opt-in and marked for approval', () {
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
    'a newly enabled report asks with full trust disabled even before approval state sync',
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
      expect(settings.toolAutoApproveAll, isFalse);
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

  for (final withApprovalService in [true, false]) {
    testWidgets(
      'full trust creates reports without consent (approval service: $withApprovalService)',
      (tester) async {
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('moru-trusted-report-'),
        ))!;
        final previousPathProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _ReportPathProvider(root.path);
        addTearDown(() async {
          PathProviderPlatform.instance = previousPathProvider;
          await root.delete(recursive: true);
        });
        PackageInfo.setMockInitialValues(
          appName: 'Moru',
          packageName: 'com.moru',
          version: '0.1.47',
          buildNumber: '48',
          buildSignature: '',
        );
        const deviceChannel = MethodChannel('app.device_tools');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          deviceChannel,
          (_) async => {'android': '16', 'sdk': 36, 'model': 'Test Phone'},
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            deviceChannel,
            null,
          );
        });
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
        await settings.setToolAutoApproveAll(true);
        final id = await assistants.addAssistant(name: 'Test');
        final assistant = assistants
            .getById(id)!
            .copyWith(localToolIds: ['report_problem']);
        await assistants.updateAssistant(assistant);
        try {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AssistantProvider>.value(
                  value: assistants,
                ),
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
                assistant,
                approvalService: withApprovalService ? approvals : null,
                conversationId: 'chat',
              )!;
          late Future<Object?> result;
          await tester.runAsync(() async {
            result = handler('report_problem', {}, toolCallId: 'trusted');
            await Future<void>.delayed(Duration.zero);
          });
          expect(approvals.pendingRequests, isEmpty);
          final report = (await tester.runAsync(
            () async =>
                jsonDecode(await result as String) as Map<String, dynamic>,
          ))!;
          expect(report['ok'], isTrue);
          expect(report['name'], startsWith('moru-problem-'));
          expect(
            await tester.runAsync(
              () => File(report['path'] as String).exists(),
            ),
            isTrue,
          );

          await assistants.updateAssistant(
            assistant.copyWith(localToolIds: []),
          );
          final revoked = jsonDecode(
            await handler('report_problem', {}) as String,
          );
          expect(revoked['error'], 'permission_denied');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
