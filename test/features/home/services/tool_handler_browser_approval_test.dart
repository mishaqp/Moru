import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_webview_platform.dart';

void main() {
  final session = BrowserAgentSession.instance;
  late AssistantProvider assistants;
  late SettingsProvider settings;
  late McpProvider mcp;
  late McpToolService tools;
  late Assistant assistant;

  setUp(() async {
    installFakeWebViewPlatform();
    final onPageLoaded = session.onPageLoaded;
    final onVisit = session.onVisit;
    session
      ..onPageLoaded = (_, _) {}
      ..onVisit = (_, _) {};
    addTearDown(() {
      session
        ..onPageLoaded = onPageLoaded
        ..onVisit = onVisit;
    });
    final preferences = createBusinessTestPreferences();
    assistants = AssistantProvider(preferences: preferences);
    settings = SettingsProvider(preferences);
    mcp = McpProvider(preferences: preferences);
    tools = McpToolService();
    for (final notifier in [assistants, settings, mcp, tools]) {
      addTearDown(notifier.dispose);
    }
    await assistants.loaded;
    await settings.loaded;
    final id = await assistants.addAssistant(name: 'Browser');
    assistant = assistants.getById(id)!;
  });

  Future<ToolCallHandler> handler(
    WidgetTester tester, {
    ToolApprovalService? approvals,
  }) async {
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
    return ToolHandlerService(
      contextProvider: tester.element(find.byType(SizedBox)),
    ).buildToolCallHandler(
      settings,
      assistant,
      approvalService: approvals,
      conversationId: 'browser-chat',
    )!;
  }

  Future<FakeWebViewController> attach() async {
    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(controller, onClose: () async {});
    addTearDown(() => session.unregister(controller));
    await session.load(Uri.parse('https://example.com/a'));
    return FakeWebViewPlatform.lastCreated!;
  }

  Map<String, dynamic> result(Object? raw) =>
      jsonDecode(ClientToolResult.fromHandler(raw).content)
          as Map<String, dynamic>;

  testWidgets(
    'browser mutation fails closed when consent is unavailable',
    (tester) async {
      final call = await handler(tester);
      var executed = false;
      final raw = await tester.runAsync(() async {
        final fake = await attach();
        fake.jsHandler = (script) {
          if (script == 'browserApprovalMutationProbe()') executed = true;
          return jsonEncode({'ok': true});
        };
        final raw = await call('browser_use', {
          'action': 'eval_js',
          'code': 'browserApprovalMutationProbe()',
        }, toolCallId: 'unavailable');
        return raw;
      });
      expect(result(raw)['error'], 'approval_unavailable');
      expect(executed, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'full trust runs a browser mutation without an approval service',
    (tester) async {
      await tester.runAsync(() => settings.setToolAutoApproveAll(true));
      final call = await handler(tester);
      var executed = false;
      final raw = await tester.runAsync(() async {
        final fake = await attach();
        fake.jsHandler = (script) {
          if (script == 'browserApprovalMutationProbe()') executed = true;
          return jsonEncode({'ok': true});
        };
        return call('browser_use', {
          'action': 'eval_js',
          'code': 'browserApprovalMutationProbe()',
        }, toolCallId: 'trusted');
      });
      expect(result(raw)['ok'], isTrue);
      expect(executed, isTrue);
      expect(assistant.localToolIds, isNot(contains('browser_use')));
      expect(
        LocalToolsService.isEnabledForAssistant('browser_use', assistant),
        isTrue,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'disabling cookie export during consent rejects the action',
    (tester) async {
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      final call = await handler(tester, approvals: approvals);
      final pending = call('browser_use', {
        'action': 'export_cookies',
      }, toolCallId: 'export');
      await tester.pump();
      expect(approvals.pendingRequests, hasLength(1));
      await tester.runAsync(
        () => settings.setBrowserActionEnabled('export_cookies', false),
      );
      approvals.approve('export', conversationId: 'browser-chat');
      expect(result(await pending)['error'], 'action_disabled');
      expect(approvals.pendingRequests, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'disabling click during consent rejects the action',
    (tester) async {
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      final call = await handler(tester, approvals: approvals);
      final pending = call('browser_use', {
        'action': 'click',
        'element_id': 1,
      }, toolCallId: 'click');
      await tester.pump();
      expect(approvals.pendingRequests, hasLength(1));
      await tester.runAsync(
        () => settings.setBrowserActionEnabled('click', false),
      );
      approvals.approve('click', conversationId: 'browser-chat');
      expect(result(await pending)['error'], 'action_disabled');
      expect(approvals.pendingRequests, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
