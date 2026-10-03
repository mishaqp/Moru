import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_binding.dart';
import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/api/tool_display_redaction.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_approval_card.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secret = 'fake-api-key-sentinel';
  final browser = BrowserAgentSession.instance;
  setUp(installFakeWebViewPlatform);

  test(
    'unknown browser approval actions and nested strings remain safe display copies',
    () async {
      final approvals = ToolApprovalService();
      addTearDown(approvals.dispose);
      final redactor = AcpSecretRedactor([secret, 'code']);
      final raw = <String, dynamic>{
        'action': secret,
        'code': secret,
        'element_id': secret,
        'extra': {
          secret: [secret],
        },
      };
      final approved =
          ToolDisplayRedaction(text: redactor.text, value: redactor.value).run(
            () => approvals.requestApproval(
              toolCallId: 'unknown',
              toolName: 'browser_use',
              arguments: raw,
            ),
          );
      final display = approvals.pendingRequests.single.arguments;
      expect(display.toString(), isNot(contains(secret)));
      expect(display['action'], '[REDACTED]');
      expect(display['code'], '[REDACTED]');
      expect(display['element_id'], '[REDACTED]');
      expect(raw['code'], secret);
      approvals.approve('unknown');
      expect((await approved).approved, isTrue);
      expect(ToolDisplayRedaction.current, isNull);
    },
  );

  for (final action in ['eval_js', 'done']) {
    testWidgets(
      'Moru MCP $action keeps execution raw and browser display safe',
      (tester) async {
        final preferences = createBusinessTestPreferences();
        final assistants = AssistantProvider(preferences: preferences);
        final settings = SettingsProvider(preferences);
        final mcp = McpProvider(preferences: preferences);
        final toolService = McpToolService();
        final approvals = ToolApprovalService();
        for (final notifier in [
          assistants,
          settings,
          mcp,
          toolService,
          approvals,
        ]) {
          addTearDown(notifier.dispose);
        }
        await assistants.loaded;
        await settings.loaded;
        final id = await assistants.addAssistant(name: 'ACP browser');
        await assistants.updateAssistant(
          assistants.getById(id)!.copyWith(localToolIds: ['browser_use']),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AssistantProvider>.value(
                value: assistants,
              ),
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<McpProvider>.value(value: mcp),
              ChangeNotifierProvider<McpToolService>.value(value: toolService),
            ],
            child: const SizedBox.shrink(),
          ),
        );
        final handler =
            ToolHandlerService(
              contextProvider: tester.element(find.byType(SizedBox)),
            ).buildToolCallHandler(
              settings,
              assistants.getById(id),
              approvalService: approvals,
              conversationId: 'acp-chat',
            )!;
        final controller = WebViewController();
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: browser.pageStarted,
            onPageFinished: browser.pageFinished,
          ),
        );
        browser
          ..register(controller, onClose: () async {})
          ..recentActivityNotifier.value = const [];
        addTearDown(() => browser.unregister(controller));
        await browser.load(Uri.parse('https://example.com'));
        final scripts = <String>[];
        FakeWebViewPlatform.lastCreated!.jsHandler = (script) {
          scripts.add(script);
          return jsonEncode('safe execution result');
        };
        const code = 'window.moruTest = "$secret"';
        final arguments = <String, dynamic>{
          'action': action,
          if (action == 'eval_js') 'code': code,
          if (action == 'done') 'summary': 'Finished with $secret',
        };
        final tools = AcpMcpTools(
          key: id,
          definitions: () => [],
          execute: (name, args, {required toolCallId}) async {
            expect(args, arguments);
            final value = await handler(name, args, toolCallId: toolCallId);
            return {'value': value};
          },
        );
        ToolApprovalRequest? request;
        final result = await tester.runAsync(() async {
          final binding = await AcpMcpBinding.start(
            tools,
            redactor: AcpSecretRedactor([secret, 'code']),
          );
          addTearDown(binding.close);
          binding.beginTurn(tools);
          binding.observe({
            'toolCallId': 'call',
            'title': 'mcp__moru__browser_use',
            'rawInput': arguments,
          });
          if (action == 'eval_js') {
            final pending = Completer<void>();
            void onPending() {
              if (approvals.hasPending && !pending.isCompleted) {
                pending.complete();
              }
            }

            approvals.addListener(onPending);
            final executing = binding.callTool('browser_use', arguments);
            await pending.future.timeout(const Duration(seconds: 2));
            approvals.removeListener(onPending);
            request = approvals.pendingRequests.single;
            approvals.approve(request!.toolCallId, conversationId: 'acp-chat');
            return executing.timeout(const Duration(seconds: 2));
          }
          return binding
              .callTool('browser_use', arguments)
              .timeout(const Duration(seconds: 2));
        });
        final executed = jsonDecode(result!['value'] as String) as Map;
        expect(executed['ok'], isTrue);
        if (action == 'eval_js') {
          expect(scripts, contains(code));
          expect(request!.arguments['action'], 'eval_js');
          expect(request!.arguments['code'], isNot(contains(secret)));
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: BrowserApprovalCard(
                  request: request!,
                  siteUrl: 'https://example.com',
                  ru: false,
                  onApprove: () {},
                  onDeny: () {},
                  onChangeTrustSettings: () {},
                ),
              ),
            ),
          );
          expect(find.textContaining(secret), findsNothing);
          expect(find.textContaining('[REDACTED]'), findsOneWidget);
        } else {
          expect(executed['summary'], arguments['summary']);
          expect(browser.recentActivity.single.action, 'done');
          expect(browser.recentActivity.single.detail, isNot(contains(secret)));
          expect(
            browser.currentActivity.value!.detail,
            isNot(contains(secret)),
          );
        }
        expect(
          arguments[action == 'eval_js' ? 'code' : 'summary'],
          contains(secret),
        );
      },
    );
  }
}
