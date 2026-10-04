import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/business_test_harness.dart';

const _private = 'provider-private-value/with space';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'direct MCP calls sanitize content, structured results, and server errors',
    () async {
      final server = await _EchoServer.start();
      final harness = await createBusinessTestHarness();
      final provider = McpProvider(preferences: harness.preferences);
      addTearDown(provider.dispose);
      addTearDown(server.close);
      await provider.loaded;
      final id = await provider.addServer(
        enabled: true,
        name: 'Echo',
        transport: McpTransportType.http,
        url: server.url,
        headers: {'Authorization': _private},
      );
      await provider.connect(id);
      expect(provider.isConnected(id), isTrue);
      final success = await provider.callTool(id, 'echo', {
        'message': 'business',
      });
      expect(success, isNotNull);
      final output = jsonEncode(success!.toJson());
      expect(output, contains('business'));
      expect(output, isNot(contains(_private)));
      expect(output, isNot(contains(Uri.encodeComponent(_private))));
      expect(success.structuredContent!['value'], isNot(_private));

      final error = await provider.callTool(id, 'echo', {'message': 'error'});
      expect(error!.isError, isTrue);
      expect(jsonEncode(error.toJson()), isNot(contains(_private)));
      expect(
        jsonEncode(error.toJson()),
        isNot(contains(Uri.encodeComponent(_private))),
      );

      final blocked = await provider.callTool(id, 'echo', {
        'message': _private,
      });
      expect(blocked!.isError, isTrue);
      expect(server.toolCalls, 2);
    },
  );

  for (final privateName in [false, true]) {
    test(
      'serialized provider requests and history tool parts contain sanitized MCP output (privateName=$privateName)',
      () async {
        final mcpServer = await _EchoServer.start(
          onlyText: true,
          toolName: privateName ? 'lookup_$_private' : 'echo',
        );
        final harness = await createBusinessTestHarness();
        final provider = McpProvider(preferences: harness.preferences);
        final assistants = AssistantProvider(
          preferences: createBusinessTestPreferences(),
        );
        final tools = McpToolService();
        addTearDown(provider.dispose);
        addTearDown(assistants.dispose);
        addTearDown(tools.dispose);
        addTearDown(mcpServer.close);
        await Future.wait([provider.loaded, assistants.loaded]);
        final serverId = await provider.addServer(
          enabled: true,
          name: 'Echo',
          transport: McpTransportType.http,
          url: mcpServer.url.replaceFirst(
            '/mcp',
            privateName ? '/tools' : '/object',
          ),
          headers: {'Authorization': _private},
        );
        await provider.connect(serverId);
        await provider.refreshTools(serverId);
        final assistantId = await assistants.addAssistant(name: 'Privacy');
        await assistants.updateAssistant(
          assistants.getById(assistantId)!.copyWith(mcpServerIds: [serverId]),
        );
        final published = tools.listAvailableToolsForAssistant(
          provider,
          assistants,
          assistantId,
        );
        final exposedName = published.single.name;
        expect(exposedName, isNot(contains(_private)));
        final snapshot = tools.captureRoutesForAssistant(
          provider,
          assistants,
          assistantId: assistantId,
        );
        expect(
          tools
              .listAvailableToolsForAssistant(
                provider,
                assistants,
                assistantId,
                routeSnapshot: snapshot,
              )
              .single
              .name,
          exposedName,
        );
        final definitions = [
          for (final tool in published)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.schema,
              },
            },
        ];
        final requests = <Map<String, dynamic>>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          requests.add(
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, dynamic>(),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': requests.length == 1 ? 'tool_calls' : 'stop',
                  'message': requests.length == 1
                      ? {
                          'role': 'assistant',
                          'content': null,
                          'tool_calls': [
                            {
                              'id': 'wire-call',
                              'type': 'function',
                              'function': {
                                'name': exposedName,
                                'arguments':
                                    '{"message":"business","tools":"business-tool"}',
                              },
                            },
                          ],
                        }
                      : {'role': 'assistant', 'content': 'done'},
                },
              ],
            }),
          );
          await request.response.close();
        });
        final generated = await ChatApiService.generateMessage(
          config: ProviderConfig(
            id: 'privacy',
            enabled: true,
            name: 'Privacy',
            apiKey: 'test-provider-key',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            providerType: ProviderKind.openai,
          ),
          modelId: 'gpt',
          messages: [
            {'role': 'user', 'content': 'Look up business'},
          ],
          tools: definitions,
          onToolCall: (name, arguments, {toolCallId}) =>
              tools.callToolForAssistant(
                provider,
                assistants,
                assistantId: assistantId,
                toolName: name,
                arguments: arguments,
                routeSnapshot: snapshot,
              ),
        ).timeout(const Duration(seconds: 15));
        expect(requests, hasLength(2));
        final schema =
            ((requests.first['tools'] as List).single
                    as Map)['function']['parameters']
                as Map;
        expect(schema['type'], 'object');
        expect((schema['properties'] as Map).containsKey('tools'), isTrue);
        expect(schema['required'], ['tools']);
        final wire = jsonEncode(requests);
        expect(wire, isNot(contains(_private)));
        expect(wire, isNot(contains(Uri.encodeComponent(_private))));
        final toolMessage = (requests.last['messages'] as List)
            .whereType<Map>()
            .singleWhere((message) => message['role'] == 'tool');
        expect(toolMessage['content'], contains('business'));
        final history = generated.parts
            .whereType<ToolCallPart>()
            .map((part) => part.payloadJson)
            .join();
        expect(history, contains('business'));
        expect(history, isNot(contains(_private)));
        expect(history, isNot(contains(Uri.encodeComponent(_private))));
        expect(mcpServer.toolCalls, 1);
        expect(mcpServer.calledNames, [mcpServer.toolName]);
      },
    );
  }

  test(
    'ordinary endpoint rotation does not retain route words as credential payloads',
    () async {
      final server = await _EchoServer.start(onlyText: true);
      final harness = await createBusinessTestHarness();
      final provider = McpProvider(preferences: harness.preferences);
      final assistants = AssistantProvider(
        preferences: createBusinessTestPreferences(),
      );
      final tools = McpToolService();
      addTearDown(provider.dispose);
      addTearDown(assistants.dispose);
      addTearDown(tools.dispose);
      addTearDown(server.close);
      await Future.wait([provider.loaded, assistants.loaded]);
      final id = await provider.addServer(
        enabled: true,
        name: 'Echo',
        transport: McpTransportType.http,
        url: server.url.replaceFirst('/mcp', '/tools'),
        headers: {'Authorization': _private},
      );
      await provider.connect(id);
      await provider.refreshTools(id);
      await provider.updateServer(
        provider
            .getById(id)!
            .copyWith(url: server.url.replaceFirst('/mcp', '/object')),
      );
      await provider.connect(id);
      await provider.refreshTools(id);
      final assistantId = await assistants.addAssistant(name: 'Privacy');
      await assistants.updateAssistant(
        assistants.getById(assistantId)!.copyWith(mcpServerIds: [id]),
      );
      final schema = tools
          .listAvailableToolsForAssistant(provider, assistants, assistantId)
          .single
          .schema!;
      expect(schema['type'], 'object');
      expect((schema['properties'] as Map).containsKey('tools'), isTrue);
      expect(schema['required'], ['tools']);
    },
  );

  test(
    'configured credential defaults cannot be injected into ordinary MCP calls',
    () async {
      final server = await _EchoServer.start(secretDefault: true);
      final harness = await createBusinessTestHarness();
      final provider = McpProvider(preferences: harness.preferences);
      addTearDown(provider.dispose);
      addTearDown(server.close);
      await provider.loaded;
      final id = await provider.addServer(
        enabled: true,
        name: 'Echo',
        transport: McpTransportType.http,
        url: server.url,
        headers: {'Authorization': _private},
      );
      await provider.connect(id);
      await provider.refreshTools(id);
      expect(
        provider
            .getById(id)!
            .tools
            .single
            .schema!['properties']['message']['default'],
        _private,
      );
      final result = await provider.callTool(id, 'echo', {});
      expect(result!.isError, isTrue);
      expect(server.toolCalls, 0);
    },
  );
}

class _EchoServer {
  _EchoServer(this.server, this.secretDefault, this.onlyText, this.toolName);
  final HttpServer server;
  final bool secretDefault;
  final bool onlyText;
  final String toolName;
  final List<String> calledNames = [];
  int toolCalls = 0;
  String get url => 'http://127.0.0.1:${server.port}/mcp';
  static Future<_EchoServer> start({
    bool secretDefault = false,
    bool onlyText = false,
    String toolName = 'echo',
  }) async {
    final fixture = _EchoServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      secretDefault,
      onlyText,
      toolName,
    );
    fixture.server.listen(fixture.handle);
    return fixture;
  }

  Future<void> handle(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    if (!body.containsKey('id')) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }
    final response = <String, dynamic>{'jsonrpc': '2.0', 'id': body['id']};
    switch (body['method']) {
      case 'initialize':
        response['result'] = {
          'protocolVersion': '2025-03-26',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'echo', 'version': '1'},
        };
      case 'tools/list':
        response['result'] = {
          'tools': [
            {
              'name': toolName,
              'description': 'Business echo $_private',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'message': {
                    'type': 'string',
                    if (secretDefault) 'default': _private,
                  },
                  if (onlyText) 'tools': {'type': 'string'},
                },
                if (onlyText) 'required': ['tools'],
              },
            },
          ],
        };
      case 'tools/call':
        toolCalls++;
        calledNames.add((body['params'] as Map)['name'] as String);
        final message = (body['params'] as Map)['arguments']['message'];
        if (message == 'error') {
          response['error'] = {
            'code': -32602,
            'message': 'Bad input $_private ${Uri.encodeComponent(_private)}',
          };
        } else {
          response['result'] = {
            'content': [
              {
                'type': 'text',
                'text': 'business $_private ${Uri.encodeComponent(_private)}',
              },
              if (!onlyText)
                {
                  'type': 'resource',
                  'resource': {
                    'uri':
                        'https://example.test/?token=${Uri.encodeComponent(_private)}',
                    'text': _private,
                  },
                },
              if (!onlyText)
                {
                  'type': 'image',
                  'mimeType': 'image/png',
                  'url':
                      'https://example.test/image?token=${Uri.encodeComponent(_private)}',
                },
            ],
            'structuredContent': {'value': _private},
          };
        }
      default:
        response['result'] = {};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}
