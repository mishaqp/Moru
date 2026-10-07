import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/tool_schema_override.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/tool_schema_normalizer.dart';
import 'package:Kelivo/core/services/api/providers/google_vertex.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Kelivo/core/services/memory/memory_prompts.dart';
import 'package:Kelivo/core/services/tools/built_in_tool_catalog.dart';
import 'package:Kelivo/core/services/tools/tool_schema_overrides.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

import 'support/tool_schema_contract.dart';
import 'support/tool_schema_fixtures.dart';

void main() {
  for (final customBody in [false, true]) {
    test(
      'Vertex Claude normalizes source schemas on both tool rounds, customBody=$customBody',
      () async {
        final parameters = mcpToolSchemaFixtures['nullable_and_unions']!;
        final tool = <String, dynamic>{
          'type': 'function',
          'function': {'name': 'vertex_fixture', 'parameters': parameters},
        };
        final before = jsonEncode(tool);
        final bodies = <Map<String, dynamic>>[];
        final client = MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'id': 'msg_${bodies.length}',
              'type': 'message',
              'role': 'assistant',
              'content': bodies.length == 1
                  ? [
                      {
                        'type': 'tool_use',
                        'id': 'call',
                        'name': 'vertex_fixture',
                        'input': {'label': null},
                      },
                    ]
                  : [
                      {'type': 'text', 'text': 'done'},
                    ],
              'stop_reason': bodies.length == 1 ? 'tool_use' : 'end_turn',
              'usage': {'input_tokens': 1, 'output_tokens': 1},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        addTearDown(client.close);
        await sendGoogleVertexClaudeStream(
          client: client,
          config: ProviderConfig(
            id: 'VertexContract',
            enabled: true,
            name: 'Vertex',
            apiKey: 'test-key',
            baseUrl: 'https://aiplatform.googleapis.com',
            providerType: ProviderKind.google,
            vertexAI: true,
            location: 'global',
            projectId: 'test',
          ),
          modelId: 'claude-sonnet-4@20250514',
          messages: [
            {'role': 'user', 'content': 'done'},
          ],
          tools: [tool],
          extraBody: customBody
              ? {
                  'tools': [
                    {'name': 'vertex_fixture', 'input_schema': parameters},
                  ],
                }
              : null,
          onToolCall: (_, _, {toolCallId}) async => 'done',
          stream: false,
        ).toList();
        expect(bodies, hasLength(2));
        for (final body in bodies) {
          final schema = body['tools'][0]['input_schema'] as Map;
          expect(
            schema,
            normalizeToolSchema(parameters, ToolSchemaTarget.claude).parameters,
          );
          assertToolSchemaForProvider(
            schema,
            ToolSchemaTarget.claude,
            strict: false,
            path: 'Vertex Claude',
          );
        }
        expect(jsonEncode(tool), before);
      },
    );
  }
  for (final testCase in [
    (
      name: 'Chat Completions',
      kind: ProviderKind.openai,
      responses: false,
      target: ToolSchemaTarget.openai,
    ),
    (
      name: 'Chat Completions strict',
      kind: ProviderKind.openai,
      responses: false,
      target: ToolSchemaTarget.openaiStrict,
    ),
    (
      name: 'Responses strict default',
      kind: ProviderKind.openai,
      responses: true,
      target: ToolSchemaTarget.openaiStrict,
    ),
    (
      name: 'Responses ordinary',
      kind: ProviderKind.openai,
      responses: true,
      target: ToolSchemaTarget.openai,
    ),
    (
      name: 'Claude',
      kind: ProviderKind.claude,
      responses: false,
      target: ToolSchemaTarget.claude,
    ),
    (
      name: 'Gemini',
      kind: ProviderKind.google,
      responses: false,
      target: ToolSchemaTarget.gemini,
    ),
  ]) {
    for (final customBody in [false, true]) {
      test(
        '${testCase.name} sends catalog and MCP schemas, customBody=$customBody',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final source = <String, Map<String, dynamic>>{};
          for (final legacy in [false, true]) {
            for (final entry in BuiltInToolCatalog.entries(
              lang: MemoryPromptLang.en,
              legacyMemoryMode: legacy,
            )) {
              source[entry.name] = entry.defaultDefinition;
            }
          }
          source.addAll(LocalToolsService.definitions);
          for (final entry in mcpToolSchemaFixtures.entries) {
            source['mcp_${entry.key}'] = {
              'type': 'function',
              'function': {
                'name': 'mcp_${entry.key}',
                'parameters': entry.value,
              },
            };
          }
          var tools = ToolSchemaOverrides.apply(source.values.toList(), {
            'calculate': const ToolSchemaOverride(
              description: 'User-defined description',
              paramDescriptions: {'expression': 'User-defined expression'},
            ),
          });
          tools = [
            for (final tool in tools)
              {
                ...tool,
                'function': <String, dynamic>{
                  ...tool['function'] as Map,
                  if (testCase.target == ToolSchemaTarget.openai)
                    'strict': false,
                  if (testCase.target == ToolSchemaTarget.openaiStrict &&
                      (tool['function'] as Map)['strict'] != false)
                    'strict': true,
                },
              },
          ];
          final before = jsonEncode(tools);
          late Map<String, dynamic> body;
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          server.listen((request) async {
            body =
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(switch (testCase.kind) {
                ProviderKind.claude => {
                  'id': 'msg',
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {'type': 'text', 'text': 'done'},
                  ],
                  'stop_reason': 'end_turn',
                  'usage': {'input_tokens': 1, 'output_tokens': 1},
                },
                ProviderKind.google => {
                  'candidates': [
                    {
                      'content': {
                        'role': 'model',
                        'parts': [
                          {'text': 'done'},
                        ],
                      },
                      'finishReason': 'STOP',
                    },
                  ],
                },
                _ when testCase.responses => {
                  'id': 'resp',
                  'object': 'response',
                  'status': 'completed',
                  'output': [
                    {
                      'type': 'message',
                      'role': 'assistant',
                      'content': [
                        {'type': 'output_text', 'text': 'done'},
                      ],
                    },
                  ],
                },
                _ => {
                  'choices': [
                    {
                      'message': {'role': 'assistant', 'content': 'done'},
                      'finish_reason': 'stop',
                    },
                  ],
                },
              }),
            );
            await request.response.close();
          });
          final nativeTools = switch (testCase.kind) {
            ProviderKind.claude => [
              for (final tool in tools)
                {
                  'name': tool['function']['name'],
                  'input_schema': tool['function']['parameters'],
                },
            ],
            ProviderKind.google => [
              {
                'function_declarations': [
                  for (final tool in tools)
                    {
                      'name': tool['function']['name'],
                      'parameters': tool['function']['parameters'],
                    },
                ],
              },
            ],
            _ => tools,
          };
          final result = await ChatApiService.generateMessage(
            config: ProviderConfig(
              id: 'SchemaContract',
              enabled: true,
              name: 'Contract',
              apiKey: 'test-key',
              baseUrl: 'http://${server.address.address}:${server.port}/v1',
              providerType: testCase.kind,
              useResponseApi: testCase.responses,
            ),
            modelId: testCase.kind == ProviderKind.google
                ? 'gemini-2.5-flash'
                : testCase.kind == ProviderKind.claude
                ? 'claude-sonnet-4-5'
                : 'gpt-4.1',
            messages: [
              {'role': 'user', 'content': 'done'},
            ],
            tools: tools,
            extraBody: customBody ? {'tools': nativeTools} : null,
          );
          expect(result.text, 'done');
          final sent = <Map>[];
          for (final tool in body['tools'] as List) {
            if (testCase.kind == ProviderKind.google) {
              sent.addAll(
                ((tool['function_declarations'] ?? tool['functionDeclarations'])
                        as List)
                    .whereType<Map>(),
              );
            } else {
              sent.add(tool as Map);
            }
          }
          expect(sent.length, tools.length);
          for (final tool in sent) {
            final fn = tool['function'] as Map? ?? tool;
            final parameters = (fn['input_schema'] ?? fn['parameters']) as Map;
            assertToolSchemaForProvider(
              parameters,
              testCase.target,
              strict: fn['strict'] == true,
              path: '${testCase.name}/${fn['name']}',
            );
            final sourceTool = tools.singleWhere(
              (tool) => tool['function']['name'] == fn['name'],
            );
            final expected =
                normalizeToolDefinition(sourceTool, testCase.target)['function']
                    as Map;
            expect(
              parameters,
              expected['parameters'],
              reason: fn['name'].toString(),
            );
          }
          expect(jsonEncode(tools), before);
        },
      );
    }
  }
}
