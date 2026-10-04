import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/api/generation/spend_round_control.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _RealHttpOverrides extends HttpOverrides {}

const _tool = {
  'type': 'function',
  'function': {
    'name': 'read_status',
    'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
  },
};

Map<String, dynamic> _reply(ProviderKind kind, {required bool toolCall}) {
  if (kind == ProviderKind.claude) {
    return {
      'id': toolCall ? 'msg-tool' : 'msg-done',
      'type': 'message',
      'role': 'assistant',
      'model': 'claude-sonnet-4',
      'content': [
        if (toolCall)
          {
            'type': 'tool_use',
            'id': 'call_1',
            'name': 'read_status',
            'input': <String, dynamic>{},
          }
        else
          {'type': 'text', 'text': 'Done.'},
      ],
      'stop_reason': toolCall ? 'tool_use' : 'end_turn',
      'usage': {'input_tokens': 70, 'output_tokens': 10},
    };
  }
  return {
    'choices': [
      {
        'message': {
          'role': 'assistant',
          if (toolCall)
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'read_status', 'arguments': '{}'},
              },
            ]
          else
            'content': 'Done.',
        },
        'finish_reason': toolCall ? 'tool_calls' : 'stop',
      },
    ],
    'usage': {'prompt_tokens': 70, 'completion_tokens': 10, 'total_tokens': 80},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;
  late bool previousSaveOutput;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moru_spend_privacy_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    previousSaveOutput = RequestLogger.saveOutput;
    RequestLogger.saveOutput = true;
    await RequestLogger.setEnabled(true);
  });

  tearDown(() async {
    await RequestLogger.setEnabled(false);
    RequestLogger.saveOutput = previousSaveOutput;
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  for (final kind in [ProviderKind.openai, ProviderKind.claude]) {
    test('follow-up spend notice reaches HTTP without history or log writes '
        '($kind)', () async {
      const warning = 'Spend control: ephemeral-budget-notice at 80%.';
      final bodies = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(_reply(kind, toolCall: bodies.length == 1)),
        );
        await request.response.close();
      });

      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Keep the answer short.'},
        {'role': 'user', 'content': 'Read the status.'},
      ];
      final originalMessages = jsonEncode(messages);
      final observedSpend = <int>[];
      final control = SpendRoundControl(
        beforeRequest: (usage, rounds) async {
          observedSpend.add(usage.totalTokens);
          return usage.totalTokens >= 100 * 0.8 ? warning : null;
        },
      );
      var toolCalls = 0;
      final chunks = await HttpOverrides.runZoned(
        () => ChatApiService.sendMessageStream(
          config: ProviderConfig(
            id: 'SpendPrivacy',
            enabled: true,
            name: 'SpendPrivacy',
            apiKey: 'test-key',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            providerType: kind,
          ),
          modelId: kind == ProviderKind.claude ? 'claude-sonnet-4' : 'gpt-4o',
          messages: messages,
          stream: false,
          tools: const [_tool],
          onToolCall: (name, args, {toolCallId}) async {
            toolCalls++;
            return '{"status":"ok"}';
          },
          spendControl: control,
        ).toList(),
        createHttpClient: (context) =>
            _RealHttpOverrides().createHttpClient(context),
      );

      expect(bodies, hasLength(2));
      expect(toolCalls, 1);
      expect(observedSpend.first, 0);
      expect(observedSpend, contains(80));
      expect(jsonEncode(bodies.first), isNot(contains(warning)));
      expect(jsonEncode(bodies.last), contains(warning));
      expect(jsonEncode(messages), originalMessages);
      final artifacts = chunks.whereType<ProviderArtifact>();
      if (kind == ProviderKind.claude) expect(artifacts, isNotEmpty);
      for (final artifact in artifacts) {
        expect(jsonEncode(artifact.payload), isNot(contains(warning)));
      }
      final log = File('${tempDir.path}/logs/logs.txt');
      expect(await log.exists() ? await log.readAsString() : '', isEmpty);
    });
  }

  test(
    'ordinary requests still write request logs without spend control',
    () async {
      const marker = 'ordinary-request-log-sentinel';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(_reply(ProviderKind.openai, toolCall: false)),
        );
        await request.response.close();
      });
      await HttpOverrides.runZoned(
        () => ChatApiService.sendMessageStream(
          config: ProviderConfig(
            id: 'OrdinaryPrivacy',
            enabled: true,
            name: 'OrdinaryPrivacy',
            apiKey: 'test-key',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            providerType: ProviderKind.openai,
          ),
          modelId: 'gpt-4o',
          messages: [
            {'role': 'user', 'content': marker},
          ],
          stream: false,
        ).drain<void>(),
        createHttpClient: (context) =>
            _RealHttpOverrides().createHttpClient(context),
      );
      final log = File('${tempDir.path}/logs/logs.txt');
      var contents = '';
      for (var attempt = 0; attempt < 50; attempt++) {
        if (await log.exists()) contents = await log.readAsString();
        if (contents.contains(marker) && contents.contains('done')) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(contents, contains(marker));
      expect(contents, contains('status=200'));
      expect(contents, contains('Done.'));
    },
  );
}
