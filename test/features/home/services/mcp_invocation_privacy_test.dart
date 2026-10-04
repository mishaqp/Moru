import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/core/services/mcp/mcp_oauth_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

import '../../../support/business_test_harness.dart';

const _secret = 'configured-private-value/with space';
const _rotated = 'new-private-value/with space';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_Fixture> fixture(
    WidgetTester tester, {
    bool fullTrust = false,
  }) async {
    final provider = _EchoProvider();
    final assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    final settings = SettingsProvider(createBusinessTestPreferences());
    final tools = McpToolService();
    final approval = ToolApprovalService();
    addTearDown(provider.dispose);
    addTearDown(assistants.dispose);
    addTearDown(settings.dispose);
    addTearDown(tools.dispose);
    addTearDown(approval.dispose);
    await Future.wait([provider.loaded, assistants.loaded, settings.loaded]);
    await settings.setToolAutoApproveAll(fullTrust);
    final id = await assistants.addAssistant(name: 'Test');
    await assistants.updateAssistant(
      assistants.getById(id)!.copyWith(mcpServerIds: ['private']),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<McpProvider>.value(value: provider),
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<McpToolService>.value(value: tools),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    return _Fixture(
      provider,
      assistants,
      settings,
      tools,
      approval,
      id,
      ToolHandlerService(
        contextProvider: tester.element(find.byType(SizedBox)),
      ),
    );
  }

  testWidgets('full trust bypasses MCP confirmation with stale approval mode', (
    tester,
  ) async {
    final f = await fixture(tester, fullTrust: true);
    expect(f.approval.autoApproveAll, isFalse);
    final handler = f.handler();
    final result = handler('echo', {'city': 'Seattle'}, toolCallId: 'trusted');
    await tester.pump();
    expect(f.approval.pendingRequests, isEmpty);
    expect(f.provider.calls, 1);
    expect(await result, isA<McpToolResult>());
  });

  testWidgets('without full trust needsApproval keeps ordinary confirmation', (
    tester,
  ) async {
    final f = await fixture(tester);
    final result = f.handler()('echo', {
      'city': 'Seattle',
    }, toolCallId: 'confirm');
    await tester.pump();
    expect(f.approval.pendingRequests, hasLength(1));
    expect(f.provider.calls, 0);
    f.approval.approve('confirm', conversationId: 'chat');
    expect(await result, isA<McpToolResult>());
    expect(f.provider.calls, 1);
  });

  testWidgets(
    'provider definitions scrub descriptions schemas and cached defaults',
    (tester) async {
      final f = await fixture(tester);
      final snapshot = f.service.captureMcpToolRoutes(
        f.assistants.getById(f.id),
      );
      f.provider.config = f.provider.config.copyWith(
        headers: {'Authorization': _rotated},
      );
      final definitions = f.service.buildToolDefinitions(
        f.settings,
        f.assistants.getById(f.id),
        'openai',
        'gpt',
        false,
        isToolModel: (_, __) => true,
        mcpRouteSnapshot: snapshot,
      );
      final encoded = jsonEncode(definitions);
      expect(encoded, isNot(contains(_secret)));
      expect(encoded, isNot(contains(Uri.encodeComponent(_secret))));
      expect(encoded, contains('business-description'));
      expect(f.provider.config.tools.first.description, contains(_secret));
    },
  );

  testWidgets(
    'results capture old and rotated credentials across an async call',
    (tester) async {
      final f = await fixture(tester, fullTrust: true);
      f.provider.response = Completer<mcp.CallToolResult>();
      final result = f.handler()('echo', {
        'city': 'Seattle',
      }, toolCallId: 'rotation');
      await tester.pump();
      f.provider.config = f.provider.config.copyWith(
        headers: {'Authorization': _rotated},
      );
      f.provider.response!.complete(
        mcp.CallToolResult(
          [
            mcp.TextContent(
              text:
                  'ordinary $_secret ${Uri.encodeComponent(_secret)} $_rotated',
            ),
            mcp.ResourceContent(
              uri:
                  'https://example.test/?token=${Uri.encodeComponent(_secret)}',
            ),
          ],
          structuredContent: {'token': _secret},
        ),
      );
      final output = await result as McpToolResult;
      expect(output.markdown, contains('ordinary'));
      expect(output.markdown, isNot(contains(_secret)));
      expect(output.markdown, isNot(contains(Uri.encodeComponent(_secret))));
      expect(output.markdown, isNot(contains(_rotated)));
    },
  );

  testWidgets(
    'configured credential arguments are rejected before invocation',
    (tester) async {
      final f = await fixture(tester, fullTrust: true);
      final output = await f.handler()('echo', {
        'query': _secret,
      }, toolCallId: 'secret');
      expect(jsonEncode(output), contains('credential'));
      expect(jsonEncode(output), isNot(contains(_secret)));
      expect(f.provider.calls, 0);
      expect(f.approval.pendingRequests, isEmpty);
    },
  );

  testWidgets(
    'managed and OAuth credentials are scrubbed before model results',
    (tester) async {
      final f = await fixture(tester, fullTrust: true);
      const managed = 'managed-private-value';
      const access = 'oauth-access-private-value';
      const refresh = 'oauth-refresh-private-value';
      const client = 'oauth-client-private-value';
      f.provider.config = f.provider.config.copyWith(
        managedSecrets: {'retained:0': managed},
        oauth: const McpOAuthState(
          clientId: 'public-client',
          authorizationServer: 'https://auth.test',
          authorizationEndpoint: 'https://auth.test/authorize',
          tokenEndpoint: 'https://auth.test/token',
          resource: 'https://mcp.test',
          accessToken: access,
          refreshToken: refresh,
          clientSecret: client,
        ),
      );
      f.provider.response = Completer<mcp.CallToolResult>()
        ..complete(
          const mcp.CallToolResult([
            mcp.TextContent(text: 'business $managed $access $refresh $client'),
          ]),
        );
      final output =
          await f.handler()('echo', {'city': 'Seattle'}, toolCallId: 'oauth')
              as McpToolResult;
      for (final secret in [managed, access, refresh, client]) {
        expect(output.markdown, isNot(contains(secret)));
      }
      expect(output.markdown, contains('business'));
    },
  );

  testWidgets('delayed errors remain private after a server is removed', (
    tester,
  ) async {
    final f = await fixture(tester, fullTrust: true);
    f.provider.response = Completer<mcp.CallToolResult>();
    final result = f.handler()('echo', {
      'city': 'Seattle',
    }, toolCallId: 'removed');
    await tester.pump();
    f.provider.visible = false;
    f.provider.response!.completeError(StateError('failure $_secret'));
    final output = await result as McpToolResult;
    expect(output.markdown, contains('failure'));
    expect(output.markdown, isNot(contains(_secret)));
  });

  testWidgets(
    'new selections appear in the next message while live removal wins',
    (tester) async {
      final f = await fixture(tester, fullTrust: true);
      final snapshot = f.service.captureMcpToolRoutes(
        f.assistants.getById(f.id),
      );
      f.provider.extra.add(
        McpServerConfig(
          id: 'new',
          enabled: true,
          name: 'New',
          transport: McpTransportType.http,
          tools: [McpToolConfig(name: 'new_tool', enabled: true)],
        ),
      );
      await f.assistants.updateAssistant(
        f.assistants.getById(f.id)!.copyWith(mcpServerIds: ['private', 'new']),
      );
      final sameMessage = f.tools.listAvailableToolsForAssistant(
        f.provider,
        f.assistants,
        f.id,
        routeSnapshot: snapshot,
      );
      expect(sameMessage.map((tool) => tool.name), ['echo']);
      final nextMessage = f.service.captureMcpToolRoutes(
        f.assistants.getById(f.id),
      );
      expect(
        f.tools
            .listAvailableToolsForAssistant(
              f.provider,
              f.assistants,
              f.id,
              routeSnapshot: nextMessage,
            )
            .map((tool) => tool.name),
        ['echo', 'new_tool'],
      );
      f.provider.visible = false;
      expect(
        await f.tools.callToolTextForAssistant(
          f.provider,
          f.assistants,
          assistantId: f.id,
          toolName: 'echo',
          routeSnapshot: snapshot,
        ),
        isEmpty,
      );
      expect(f.provider.calls, 0);
    },
  );

  testWidgets('ordinary endpoint route words remain valid business arguments', (
    tester,
  ) async {
    final f = await fixture(tester, fullTrust: true);
    f.provider.config = f.provider.config.copyWith(
      url: 'https://public.example.test/search/mcp',
      managedSecrets: {'url:0': 'search'},
    );
    final output = await f.handler()('echo', {
      'query': 'business search',
    }, toolCallId: 'route-word');
    expect(output, isA<McpToolResult>());
    expect(f.provider.calls, 1);
  });

  testWidgets(
    'explicit URL and private placeholder credentials still block invocation',
    (tester) async {
      final f = await fixture(tester);
      for (final config in [
        f.provider.config.copyWith(
          url:
              'https://public.example.test/mcp?access_token=private-query-value',
        ),
        f.provider.config.copyWith(
          url:
              'https://private-url-user:private-url-password@public.example.test/mcp',
        ),
        f.provider.config.copyWith(
          url: 'https://public.example.test/search/mcp',
          managedSecrets: {'SEARCH_TOKEN': 'search'},
        ),
      ]) {
        f.provider.config = config;
        final credential = config.url.contains('access_token=')
            ? 'private-query-value'
            : config.url.contains('@')
            ? 'private-url-password'
            : 'search';
        final output = await f.handler()('echo', {
          'query': credential,
        }, toolCallId: 'private-source');
        expect(jsonEncode(output), contains('credential_arguments'));
        expect(f.provider.calls, 0);
        expect(f.approval.pendingRequests, isEmpty);
      }
    },
  );

  for (final ordinary in ['/home/alice/x.json', ' 1']) {
    testWidgets('ordinary business value $ordinary reaches MCP', (
      tester,
    ) async {
      final f = await fixture(tester, fullTrust: true);
      final output = await f.handler()('echo', {
        'value': ordinary,
      }, toolCallId: 'ordinary');
      expect(output, isA<McpToolResult>());
      expect(f.provider.calls, 1);
      expect(f.approval.pendingRequests, isEmpty);
    });
  }

  for (final field in [
    'cookie',
    'cookies',
    'set_cookie',
    'token',
    'secret',
    'auth',
    'proxy_authorization',
    'security_token',
  ]) {
    testWidgets(
      'literal $field authentication is rejected before confirmation',
      (tester) async {
        final f = await fixture(tester);
        final output = await f.handler()('echo', {
          field: 'opaque-private-literal',
        }, toolCallId: 'literal-auth');
        expect(jsonEncode(output), contains('credential_arguments'));
        expect(f.provider.calls, 0);
        expect(f.approval.pendingRequests, isEmpty);
      },
    );
  }

  testWidgets(
    'private server-name qualifiers and token-shaped tool names get opaque stable aliases',
    (tester) async {
      final f = await fixture(tester, fullTrust: true);
      f.provider.config = f.provider.config.copyWith(name: 'Private $_secret');
      f.provider.extra.add(
        McpServerConfig(
          id: 'extra',
          name: 'Extra',
          enabled: true,
          transport: McpTransportType.http,
          tools: [
            McpToolConfig(name: 'echo', enabled: true),
            McpToolConfig(name: 'lookup_sk-exampleOpaqueKey', enabled: true),
          ],
        ),
      );
      await f.assistants.updateAssistant(
        f.assistants
            .getById(f.id)!
            .copyWith(mcpServerIds: ['private', 'extra']),
      );
      final snapshot = f.service.captureMcpToolRoutes(
        f.assistants.getById(f.id),
      );
      final published = f.tools.listAvailableToolsForAssistant(
        f.provider,
        f.assistants,
        f.id,
        routeSnapshot: snapshot,
      );
      expect(published.first.name, startsWith('mcp_tool_'));
      expect(published.last.name, startsWith('mcp_tool_'));
      expect(
        jsonEncode(published.map((tool) => tool.toJson()).toList()),
        isNot(contains(_secret)),
      );
      expect(published[1].name, 'Extra__echo');
      final output = await f.tools.callToolForAssistant(
        f.provider,
        f.assistants,
        assistantId: f.id,
        toolName: published.first.name,
        arguments: {'city': 'Seattle'},
        routeSnapshot: snapshot,
      );
      expect(output.markdown, 'ordinary');
      expect(f.provider.lastToolName, 'echo');
      expect(
        f.tools
            .listAvailableToolsForAssistant(
              f.provider,
              f.assistants,
              f.id,
              routeSnapshot: snapshot,
            )
            .map((tool) => tool.name),
        published.map((tool) => tool.name),
      );
    },
  );

  testWidgets('ordinary business argument names keep working', (tester) async {
    final f = await fixture(tester, fullTrust: true);
    final output = await f.handler()('echo', {
      'key': 'invoice-5',
      'session': 'afternoon',
      'code': 'product-7',
    }, toolCallId: 'business');
    expect(output, isA<McpToolResult>());
    expect(f.provider.calls, 1);
  });
}

class _Fixture {
  _Fixture(
    this.provider,
    this.assistants,
    this.settings,
    this.tools,
    this.approval,
    this.id,
    this.service,
  );
  final _EchoProvider provider;
  final AssistantProvider assistants;
  final SettingsProvider settings;
  final McpToolService tools;
  final ToolApprovalService approval;
  final String id;
  final ToolHandlerService service;
  dynamic handler() => service.buildToolCallHandler(
    settings,
    assistants.getById(id),
    approvalService: approval,
    conversationId: 'chat',
  )!;
}

class _EchoProvider extends McpProvider {
  _EchoProvider() : super(preferences: createBusinessTestPreferences());
  McpServerConfig config = McpServerConfig(
    id: 'private',
    name: 'Private',
    enabled: true,
    transport: McpTransportType.http,
    headers: {'Authorization': _secret},
    tools: [
      McpToolConfig(
        name: 'echo',
        enabled: true,
        needsApproval: true,
        description: 'business-description $_secret',
        schema: {
          'type': 'object',
          'properties': {
            'city': {
              'type': 'string',
              'description': _secret,
              'default': Uri.encodeComponent(_secret),
            },
          },
        },
        params: [
          McpParamSpec(
            name: 'city',
            required: false,
            type: 'string',
            defaultValue: _secret,
          ),
        ],
      ),
    ],
  );
  int calls = 0;
  String? lastToolName;
  bool visible = true;
  final List<McpServerConfig> extra = [];
  Completer<mcp.CallToolResult>? response;
  @override
  List<McpServerConfig> get servers => [if (visible) config, ...extra];
  @override
  Future<mcp.CallToolResult?> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    calls++;
    lastToolName = toolName;
    return response == null
        ? mcp.CallToolResult([mcp.TextContent(text: 'ordinary')])
        : await response!.future;
  }
}
