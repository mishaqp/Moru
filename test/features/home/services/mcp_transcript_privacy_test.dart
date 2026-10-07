import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk_handler.dart';
import 'package:Kelivo/core/services/api/stream/stream_trace.dart';
import 'package:Kelivo/core/services/api/tool_call_argument_privacy.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';
import 'package:Kelivo/features/home/services/tool_handler_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';

import '../../../support/business_test_harness.dart';

class _LogPaths extends PathProviderPlatform {
  _LogPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _RealHttp extends HttpOverrides {}

class _Mcp extends McpProvider {
  _Mcp() : super(preferences: createBusinessTestPreferences());
  int calls = 0;
  @override
  List<McpServerConfig> get servers => [
    McpServerConfig(
      id: 'private',
      name: 'Private',
      enabled: true,
      transport: McpTransportType.http,
      headers: {'Authorization': 'configured-secret'},
      tools: [McpToolConfig(name: 'echo', enabled: true)],
    ),
  ];
  @override
  Future<mcp.CallToolResult?> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    calls++;
    return const mcp.CallToolResult([mcp.TextContent(text: 'ordinary')]);
  }
}

Map<String, dynamic> _reply(
  ProviderKind kind,
  String name,
  Map<String, dynamic> args,
  bool done, {
  bool responses = false,
}) {
  if (responses) {
    return {
      'id': 'resp',
      'object': 'response',
      'status': 'completed',
      'output': done
          ? [
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': 'done'},
                ],
              },
            ]
          : [
              {
                'id': 'item_1',
                'type': 'function_call',
                'call_id': 'call_1',
                'name': name,
                'arguments': jsonEncode(args),
              },
            ],
    };
  }
  switch (kind) {
    case ProviderKind.openai:
      return {
        'choices': [
          {
            'message': done
                ? {'role': 'assistant', 'content': 'done'}
                : {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': name,
                          'arguments': jsonEncode(args),
                        },
                      },
                    ],
                  },
            'finish_reason': done ? 'stop' : 'tool_calls',
          },
        ],
      };
    case ProviderKind.claude:
      return {
        'id': 'msg',
        'content': done
            ? [
                {'type': 'text', 'text': 'done'},
              ]
            : [
                {
                  'type': 'tool_use',
                  'id': 'call_1',
                  'name': name,
                  'input': args,
                },
              ],
        'stop_reason': done ? 'end_turn' : 'tool_use',
      };
    default:
      return {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': done
                  ? [
                      {'text': 'done'},
                    ]
                  : [
                      {
                        'functionCall': {'name': name, 'args': args},
                      },
                    ],
            },
            'finishReason': 'STOP',
          },
        ],
      };
  }
}

String _sse(
  ProviderKind kind,
  String name,
  Map<String, dynamic> args,
  bool done, {
  bool responses = false,
}) {
  String event(Map<String, dynamic> data) => 'data: ${jsonEncode(data)}\n\n';
  if (responses) {
    final reply = _reply(kind, name, args, done, responses: true);
    if (done) return event({'type': 'response.completed', 'response': reply});
    final item = (reply['output'] as List).single as Map;
    final text = jsonEncode(args);
    final split = text.indexOf('literal-private-value') + 7;
    return event({
          'type': 'response.output_item.added',
          'output_index': 0,
          'item': {...item, 'arguments': ''},
        }) +
        event({
          'type': 'response.function_call_arguments.delta',
          'item_id': 'item_1',
          'output_index': 0,
          'delta': text.substring(0, split),
        }) +
        event({
          'type': 'response.function_call_arguments.delta',
          'item_id': 'item_1',
          'output_index': 0,
          'delta': text.substring(split),
        }) +
        event({
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': item,
        }) +
        event({'type': 'response.completed', 'response': reply});
  }
  if (kind == ProviderKind.openai) {
    if (done) {
      return '${event({
        'choices': [
          {
            'delta': {'content': 'done'},
            'finish_reason': 'stop',
          },
        ],
      })}data: [DONE]\n\n';
    }
    final text = jsonEncode(args);
    final split = text.indexOf('literal-private-value') + 7;
    return [
      event({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': name,
                    'arguments': text.substring(0, split),
                  },
                },
              ],
            },
          },
        ],
      }),
      event({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': text.substring(split)},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      }),
      'data: [DONE]\n\n',
    ].join();
  }
  if (kind == ProviderKind.claude) {
    final text = jsonEncode(args);
    final split = text.indexOf('literal-private-value') + 7;
    final events = done
        ? [
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'text', 'text': ''},
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'done'},
            },
            {'type': 'content_block_stop', 'index': 0},
          ]
        : [
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {
                'type': 'tool_use',
                'id': 'call_1',
                'name': name,
                'input': {},
              },
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': text.substring(0, split),
              },
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': text.substring(split),
              },
            },
            {'type': 'content_block_stop', 'index': 0},
          ];
    return [
      {
        'type': 'message_start',
        'message': {
          'id': 'msg',
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        },
      },
      ...events,
      {
        'type': 'message_delta',
        'delta': {'stop_reason': done ? 'end_turn' : 'tool_use'},
      },
      {'type': 'message_stop'},
    ].map((data) => 'event: ${data['type']}\n${event(data)}').join();
  }
  return event(_reply(kind, name, args, done));
}

void main() {
  for (final protocol in [
    (kind: ProviderKind.openai, responses: false, model: 'gpt-4o'),
    (kind: ProviderKind.openai, responses: true, model: 'gpt-4o'),
    (kind: ProviderKind.claude, responses: false, model: 'claude-sonnet-4-6'),
    (kind: ProviderKind.google, responses: false, model: 'gemini-2.5-flash'),
    (kind: ProviderKind.google, responses: false, model: 'gemini-3-flash'),
  ]) {
    final kind = protocol.kind;
    for (final stream in [false, true]) {
      for (final variant in [
        'echo',
        'manage_mcp',
        'import',
        'unknown',
        'ordinary',
      ]) {
        final name = variant == 'ordinary'
            ? 'echo'
            : variant == 'import'
            ? 'manage_mcp'
            : variant == 'unknown'
            ? 'unknown-configured-secret'
            : variant;
        testWidgets(
          '$kind responses=${protocol.responses} ${protocol.model} $stream $variant secrets stay out of continuation and checkpoints',
          (tester) async {
            final fixture = (await tester.runAsync(() async {
              final provider = _Mcp();
              final assistants = AssistantProvider(
                preferences: createBusinessTestPreferences(),
              );
              final settings = SettingsProvider(
                createBusinessTestPreferences(),
              );
              final tools = McpToolService();
              for (final notifier in [provider, assistants, settings, tools]) {
                addTearDown(notifier.dispose);
              }
              await Future.wait([
                provider.loaded,
                assistants.loaded,
                settings.loaded,
              ]);
              await settings.setToolAutoApproveAll(true);
              final id = await assistants.addAssistant(name: 'Test');
              final assistant = assistants
                  .getById(id)!
                  .copyWith(
                    mcpServerIds: ['private'],
                    localToolIds: ['manage_mcp'],
                  );
              await assistants.updateAssistant(assistant);
              return (
                provider: provider,
                assistants: assistants,
                settings: settings,
                tools: tools,
                assistant: assistant,
              );
            }))!;
            final provider = fixture.provider;
            final assistants = fixture.assistants;
            final settings = fixture.settings;
            final tools = fixture.tools;
            final assistant = fixture.assistant;
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<McpProvider>.value(value: provider),
                  ChangeNotifierProvider<SettingsProvider>.value(
                    value: settings,
                  ),
                  ChangeNotifierProvider<AssistantProvider>.value(
                    value: assistants,
                  ),
                  ChangeNotifierProvider<McpToolService>.value(value: tools),
                ],
                child: const SizedBox.shrink(),
              ),
            );
            final handler = ToolHandlerService(
              contextProvider: tester.element(find.byType(SizedBox)),
            ).buildToolCallHandler(settings, assistant)!;
            final dispatched = <Map<String, dynamic>>[];
            final capturedHandler = ToolCallArgumentPrivacy.propagate(handler, (
              name,
              args, {
              toolCallId,
            }) {
              dispatched.add(args);
              return handler(name, args, toolCallId: toolCallId);
            });
            final args = variant == 'ordinary'
                ? <String, dynamic>{
                    'city': 'Seattle',
                    'key': 'invoice-5',
                    'session': 'afternoon',
                    'code': 'product-7',
                  }
                : variant == 'echo' || variant == 'unknown'
                ? <String, dynamic>{
                    'api_key': 'literal-private-value',
                    'city': 'Seattle',
                    'query': 'configured-secret',
                  }
                : variant == 'import'
                ? <String, dynamic>{
                    'action': 'import',
                    'json': jsonEncode({
                      'mcpServers': {
                        'Seattle': {
                          'type': 'http',
                          'url': 'https://example.test/mcp',
                          'headers': {'Authorization': 'literal-private-value'},
                        },
                      },
                    }),
                  }
                : <String, dynamic>{
                    'action': 'add',
                    'name': 'Seattle',
                    'config': {
                      'type': 'http',
                      'url': 'https://example.test/mcp',
                      'headers': {'Authorization': 'literal-private-value'},
                    },
                  };
            await tester.runAsync(
              () => HttpOverrides.runZoned(() async {
                final bodies = <Map<String, dynamic>>[];
                final server = await HttpServer.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                final directory = await Directory.systemTemp.createTemp(
                  'mcp_transcript_',
                );
                final previousPaths = PathProviderPlatform.instance;
                PathProviderPlatform.instance = _LogPaths(directory.path);
                RequestLogger.saveOutput = true;
                await RequestLogger.setEnabled(true);
                final repository = ChatDatabaseRepository.open(
                  file: File('${directory.path}/chat.sqlite'),
                );
                try {
                  await repository.ensureReady();
                  await repository.putMigrationBatch(
                    conversations: [
                      Conversation(
                        id: 'chat',
                        title: 'Chat',
                        messageIds: const ['reply'],
                      ),
                    ],
                    messages: [
                      (
                        message: ChatMessage(
                          id: 'reply',
                          role: 'assistant',
                          content: '',
                          conversationId: 'chat',
                          isStreaming: true,
                        ),
                        messageOrder: 0,
                      ),
                    ],
                    toolEventsByMessageId: const {},
                    geminiSignaturesByMessageId: const {},
                  );
                  server.listen((request) async {
                    bodies.add(
                      (jsonDecode(await utf8.decoder.bind(request).join())
                              as Map)
                          .cast<String, dynamic>(),
                    );
                    request.response.headers.contentType = stream
                        ? ContentType('text', 'event-stream')
                        : ContentType.json;
                    request.response.write(
                      stream
                          ? _sse(
                              kind,
                              name,
                              args,
                              bodies.length > 1,
                              responses: protocol.responses,
                            )
                          : jsonEncode(
                              _reply(
                                kind,
                                name,
                                args,
                                bodies.length > 1,
                                responses: protocol.responses,
                              ),
                            ),
                    );
                    await request.response.close();
                  });
                  final config = ProviderConfig(
                    id: kind == ProviderKind.google ? 'Gemini' : 'PrivacyTest',
                    enabled: true,
                    name: 'PrivacyTest',
                    apiKey: 'test-key',
                    baseUrl: 'http://127.0.0.1:${server.port}/v1',
                    providerType: kind,
                    useResponseApi: protocol.responses,
                  );
                  final folder = StreamChunkHandler();
                  final chunks = <StreamChunk>[];
                  await for (final chunk in ChatApiService.sendMessageStream(
                    config: config,
                    modelId: protocol.model,
                    messages: const [
                      {'role': 'user', 'content': 'before'},
                      {
                        'role': 'assistant',
                        'content': '',
                        'tool_calls': [
                          {
                            'id': 'old_1',
                            'type': 'function',
                            'function': {
                              'name': 'echo',
                              'arguments':
                                  '{"api_key":"literal-private-value","query":"configured-secret","city":"Portland"}',
                            },
                          },
                        ],
                      },
                      {
                        'role': 'tool',
                        'tool_call_id': 'old_1',
                        'name': 'echo',
                        'content': 'rejected earlier',
                      },
                      {'role': 'user', 'content': 'go'},
                    ],
                    tools: [
                      {
                        'type': 'function',
                        'function': {
                          'name': variant == 'unknown' ? 'echo' : name,
                          'parameters': {'type': 'object'},
                        },
                      },
                    ],
                    onToolCall: capturedHandler,
                    stream: stream,
                  )) {
                    chunks.add(chunk);
                    folder.handle(chunk);
                    final published = chunk is ToolCallDelta
                        ? chunk.inputDelta
                        : chunk is ProviderArtifact
                        ? chunk.payload
                        : '';
                    expect(published, isNot(contains('literal-private')));
                    await repository.updateStreamingCheckpoint(
                      ChatMessage(
                        id: 'reply',
                        role: 'assistant',
                        content: '',
                        conversationId: 'chat',
                        isStreaming: true,
                        parts: folder.parts,
                      ),
                      [
                        for (final part
                            in folder.parts.whereType<ToolCallPart>())
                          (jsonDecode(part.payloadJson) as Map)
                              .cast<String, dynamic>(),
                      ],
                    );
                  }
                  final logFile = File('${directory.path}/logs/logs.txt');
                  var logged = '';
                  for (var attempt = 0; attempt < 100; attempt++) {
                    if (await logFile.exists()) {
                      logged = await logFile.readAsString();
                    }
                    if (RegExp(
                          r'\[RES \d+\] status=200',
                        ).allMatches(logged).length >=
                        (protocol.responses && !stream ? 1 : 2)) {
                      break;
                    }
                    await Future<void>.delayed(
                      const Duration(milliseconds: 10),
                    );
                  }
                  expect(logged, contains('status=200'));
                  expect(logged, isNot(contains('configured-secret')));
                  expect(logged, isNot(contains('literal-private-value')));
                  if (protocol.responses && !stream) {
                    // The existing Responses non-stream path does not run client
                    // tools. Its raw response still must stay out of logging.
                    expect(dispatched, isEmpty);
                    expect(bodies, hasLength(1));
                    expect(chunks.whereType<ToolCallDelta>(), isEmpty);
                    return;
                  }
                  expect(dispatched, [args]);
                  expect(bodies, hasLength(2));
                  expect(
                    jsonEncode(bodies.last),
                    isNot(contains('literal-private-value')),
                  );
                  expect(jsonEncode(bodies.last), contains('Seattle'));
                  expect(
                    chunks.whereType<ToolCallResult>().single.output.toString(),
                    variant == 'ordinary'
                        ? contains('ordinary')
                        : anyOf(
                            contains('credential'),
                            contains('secret_required'),
                          ),
                  );
                  expect(provider.calls, variant == 'ordinary' ? 1 : 0);
                  final persisted = await repository.getMessage('reply');
                  final persistedParts = persisted!.parts
                      .map((part) => part.encodePayload())
                      .join();
                  expect(
                    persistedParts,
                    isNot(contains('literal-private-value')),
                  );
                  expect(persistedParts, contains('Seattle'));
                  expect(
                    jsonEncode(streamTraceSnapshot(chunks: chunks)),
                    isNot(contains('literal-private-value')),
                  );
                } finally {
                  await RequestLogger.setEnabled(false);
                  RequestLogger.saveOutput = false;
                  PathProviderPlatform.instance = previousPaths;
                  await repository.close();
                  await server.close(force: true);
                  await directory.delete(recursive: true);
                }
              }, createHttpClient: _RealHttp().createHttpClient),
            );
          },
        );
      }
    }
  }
}
