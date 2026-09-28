import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/generation/tool_result_images.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

/// A 1x1 PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

const _tool = {
  'type': 'function',
  'function': {
    'name': 'browser_use',
    'description': 'Browser',
    'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
  },
};

/// The screenshot a browser_use call returns, as its handler does.
Future<Object?> _screenshotTool(
  String name,
  Map<String, dynamic> args, {
  String? toolCallId,
}) async => ClientToolResult(
  '{"ok":true,"screenshot":"attached"}',
  metadata: {
    kMcpResultMetadataKey: mcpResultMetadata(['data:image/png;base64,$_png']),
  },
);

/// Serves [first] for the first request and [second] after it, recording
/// every request body.
Future<(HttpServer, List<Map<String, dynamic>>)> _serve(
  String contentType,
  String first,
  String second,
) async {
  final bodies = <Map<String, dynamic>>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>,
    );
    request.response.headers.set('content-type', contentType);
    request.response.write(bodies.length == 1 ? first : second);
    await request.response.close();
  });
  return (server, bodies);
}

String _openaiSse(Map<String, dynamic> delta, String finish) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
    })}\n\ndata: [DONE]\n\n';

void main() {
  test(
    'tool images load from data URLs and files, never from the web',
    () async {
      final dir = await Directory.systemTemp.createTemp('tool-images-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'shot.png'))
        ..writeAsBytesSync(base64Decode(_png));
      final images = await loadToolResultImages({
        kMcpResultMetadataKey: mcpResultMetadata([
          'https://example.com/a.png',
          file.path,
          p.join(dir.path, 'missing.png'),
          'data:image/png;base64,$_png',
          'data:image/png;base64,$_png',
          'data:image/png;base64,$_png',
        ]),
      });
      expect(images, hasLength(maxToolResultImages));
      expect(images.first, (mime: 'image/png', base64: _png));
      expect(await loadToolResultImages(null), isEmpty);
      expect(claudeToolResultWithImages('ok', const []), 'ok');
    },
  );

  for (final (model, vision) in [('gpt-4o', true), ('deepseek-chat', false)]) {
    test('Chat Completions: a screenshot follows the tool message '
        '($model)', () async {
      final (server, bodies) = await _serve(
        'text/event-stream',
        _openaiSse({
          'role': 'assistant',
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'browser_use', 'arguments': '{}'},
            },
          ],
        }, 'tool_calls'),
        _openaiSse({'role': 'assistant', 'content': 'seen'}, 'stop'),
      );
      addTearDown(() => server.close(force: true));
      await ChatApiService.sendMessageStream(
        config: ProviderConfig(
          id: 'OpenAIImages',
          enabled: true,
          name: 'OpenAIImages',
          apiKey: 'k',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          providerType: ProviderKind.openai,
        ),
        modelId: model,
        messages: const [
          {'role': 'user', 'content': 'look'},
        ],
        tools: const [_tool],
        onToolCall: _screenshotTool,
      ).toList();
      expect(bodies, hasLength(2));
      final messages = (bodies[1]['messages'] as List).cast<Map>();
      final toolIndex = messages.indexWhere((m) => m['role'] == 'tool');
      expect(toolIndex, greaterThan(0));
      if (vision) {
        final after = messages[toolIndex + 1];
        expect(after['role'], 'user');
        expect(jsonEncode(after['content']), contains('image_url'));
        expect(jsonEncode(after['content']), contains(_png));
      } else {
        expect(jsonEncode(bodies[1]), isNot(contains(_png)));
      }
    });
  }

  test('Responses API: a screenshot follows the function output', () async {
    String sse(List<Map<String, dynamic>> events) => [
      for (final e in events) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
    ].join();
    final completed = {
      'type': 'response.completed',
      'response': {
        'id': 'r',
        'status': 'completed',
        'output': <Object>[],
        'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
      },
    };
    final (server, bodies) = await _serve(
      'text/event-stream',
      sse([
        {
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': {
            'type': 'function_call',
            'id': 'fc_1',
            'call_id': 'call_1',
            'name': 'browser_use',
            'arguments': '{}',
          },
        },
        completed,
      ]),
      sse([
        {'type': 'response.output_text.delta', 'delta': 'seen'},
        completed,
      ]),
    );
    addTearDown(() => server.close(force: true));
    await ChatApiService.sendMessageStream(
      config: ProviderConfig(
        id: 'ResponsesImages',
        enabled: true,
        name: 'ResponsesImages',
        apiKey: 'k',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        providerType: ProviderKind.openai,
        useResponseApi: true,
      ),
      modelId: 'gpt-4o',
      messages: const [
        {'role': 'user', 'content': 'look'},
      ],
      tools: const [_tool],
      onToolCall: _screenshotTool,
    ).toList();
    expect(bodies, hasLength(2));
    final input = (bodies[1]['input'] as List).cast<Map>();
    final outputIndex = input.indexWhere(
      (item) => item['type'] == 'function_call_output',
    );
    expect(outputIndex, greaterThan(0));
    final after = input[outputIndex + 1];
    expect(after['role'], 'user');
    expect(
      jsonEncode(after['content']),
      contains('data:image/png;base64,$_png'),
    );
  });

  test('Claude: the screenshot is an image block of the tool result', () async {
    String sse(List<Map<String, dynamic>> events) => [
      'event: message_start\ndata: ${jsonEncode({
        'type': 'message_start',
        'message': {
          'id': 'm',
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        },
      })}\n\n',
      for (final e in events) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
    ].join();
    final (server, bodies) = await _serve(
      'text/event-stream',
      sse([
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'browser_use',
            'input': <String, dynamic>{},
          },
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 1},
        },
        {'type': 'message_stop'},
      ]),
      sse([
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': 'seen'},
        },
        {'type': 'content_block_stop', 'index': 0},
        {'type': 'message_stop'},
      ]),
    );
    addTearDown(() => server.close(force: true));
    await ChatApiService.sendMessageStream(
      config: ProviderConfig(
        id: 'ClaudeImages',
        enabled: true,
        name: 'ClaudeImages',
        apiKey: 'k',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        providerType: ProviderKind.claude,
      ),
      modelId: 'claude-sonnet-4-5',
      messages: const [
        {'role': 'user', 'content': 'look'},
      ],
      tools: const [_tool],
      onToolCall: _screenshotTool,
    ).toList();
    expect(bodies, hasLength(2));
    final last = (bodies[1]['messages'] as List).last as Map;
    final result = (last['content'] as List).first as Map;
    expect(result['type'], 'tool_result');
    final blocks = (result['content'] as List).cast<Map>();
    expect(blocks.first['type'], 'text');
    expect(blocks[1]['type'], 'image');
    expect((blocks[1]['source'] as Map)['data'], _png);
  });

  test('Gemini: the screenshot follows the function response', () async {
    String chunk(List<Map<String, dynamic>> parts, String finish) =>
        'data: ${jsonEncode({
          'candidates': [
            {
              'content': {'role': 'model', 'parts': parts},
              'finishReason': finish,
            },
          ],
          'usageMetadata': {'promptTokenCount': 1, 'candidatesTokenCount': 1, 'totalTokenCount': 2},
        })}\n\n';
    final (server, bodies) = await _serve(
      'text/event-stream',
      chunk([
        {
          'functionCall': {'name': 'browser_use', 'args': <String, dynamic>{}},
        },
      ], 'STOP'),
      chunk([
        {'text': 'seen'},
      ], 'STOP'),
    );
    addTearDown(() => server.close(force: true));
    await ChatApiService.sendMessageStream(
      config: ProviderConfig(
        id: 'GeminiImages',
        enabled: true,
        name: 'GeminiImages',
        apiKey: 'k',
        baseUrl: 'http://127.0.0.1:${server.port}/v1beta',
        providerType: ProviderKind.google,
      ),
      modelId: 'gemini-2.5-flash',
      messages: const [
        {'role': 'user', 'content': 'look'},
      ],
      tools: const [_tool],
      onToolCall: _screenshotTool,
    ).toList();
    expect(bodies, hasLength(2));
    final parts =
        ((bodies[1]['contents'] as List).last as Map)['parts'] as List;
    expect((parts.first as Map).containsKey('functionResponse'), isTrue);
    expect(
      parts.any((part) => (part as Map)['inlineData']?['data'] == _png),
      isTrue,
    );
  });
}
