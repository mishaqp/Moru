import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/generation/spend_round_control.dart';
import 'package:Kelivo/core/services/api/providers/claude_official.dart';
import 'package:Kelivo/core/services/api/providers/google_common.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'lookup',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  },
];

ProviderConfig _config(String provider) => ProviderConfig(
  id: 'spend-test',
  name: 'Spend test',
  enabled: true,
  apiKey: 'test',
  baseUrl: provider == 'claude'
      ? 'https://api.anthropic.com'
      : 'https://generativelanguage.googleapis.com',
  providerType: provider == 'claude'
      ? ProviderKind.claude
      : ProviderKind.google,
  vertexAI: provider == 'vertex-claude',
  projectId: 'project',
);

Stream<StreamChunk> _send(
  String provider,
  http.Client client,
  SpendRoundControl control,
  List<Map<String, dynamic>> messages, {
  required bool stream,
}) {
  final send = provider == 'claude' ? sendClaudeStream : sendGoogleStream;
  return send(
    client,
    _config(provider),
    provider == 'gemini' ? 'gemini-3-flash' : 'claude-sonnet-4-5',
    messages,
    tools: _tools,
    onToolCall: (name, args, {toolCallId}) async => 'Found',
    stream: stream,
    spendControl: control,
  );
}

http.Response _claudeResponse(int round, bool stream) {
  final content = round == 1
      ? {'type': 'tool_use', 'id': 'call_1', 'name': 'lookup', 'input': {}}
      : {'type': 'text', 'text': 'Done'};
  final usage = {
    'input_tokens': round * 100,
    'output_tokens': round * 20,
    'cache_read_input_tokens': round == 1 ? 90 : 0,
  };
  final stop = round == 1 ? 'tool_use' : 'end_turn';
  if (!stream) {
    return http.Response(
      jsonEncode({
        'content': [content],
        'usage': usage,
        'stop_reason': stop,
      }),
      200,
    );
  }
  final events = [
    {
      'type': 'message_start',
      'message': {
        'id': 'msg_$round',
        'usage': {...usage, 'output_tokens': 0},
      },
    },
    {'type': 'content_block_start', 'index': 0, 'content_block': content},
    {'type': 'content_block_stop', 'index': 0},
    {
      'type': 'message_delta',
      'delta': {'stop_reason': stop},
      'usage': {'output_tokens': round * 20},
    },
    {'type': 'message_stop'},
  ];
  return http.Response(
    events
        .map(
          (event) => 'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
        )
        .join(),
    200,
  );
}

http.Response _geminiResponse(int round, bool stream) {
  final response = {
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': [
            if (round == 1)
              {
                'functionCall': {'name': 'lookup', 'args': <String, dynamic>{}},
              }
            else
              {'text': 'Done'},
          ],
        },
        'finishReason': 'STOP',
      },
    ],
    'usageMetadata': {
      'promptTokenCount': round * 100,
      'candidatesTokenCount': round * 20,
      'totalTokenCount': round * 120,
      'cachedContentTokenCount': round == 1 ? 90 : 0,
    },
  };
  return http.Response(
    stream ? 'data: ${jsonEncode(response)}\n\n' : jsonEncode(response),
    200,
  );
}

void main() {
  for (final provider in ['claude', 'vertex-claude', 'gemini']) {
    test(
      '$provider does not charge a previous snapshot for an unreported round',
      () async {
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          if (requests == 1) {
            return provider == 'gemini'
                ? _geminiResponse(requests, false)
                : _claudeResponse(requests, false);
          }
          if (provider == 'gemini') {
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Thinking', 'thought': true},
                        {'text': 'Done'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Done'},
              ],
              'stop_reason': 'end_turn',
            }),
            200,
          );
        });
        addTearDown(client.close);
        final control = SpendRoundControl(
          beforeRequest: (usage, rounds) async => null,
        );

        await _send(provider, client, control, [
          {'role': 'user', 'content': 'Check'},
        ], stream: false).toList();

        expect(requests, 2);
        expect(control.completedRounds, 1);
        expect(
          control.completedUsage.promptTokens,
          provider == 'gemini' ? 100 : 190,
        );
        expect(control.completedUsage.completionTokens, 20);
      },
    );

    test(
      '$provider checks the completed stream before running client tools',
      () async {
        var requests = 0;
        var toolCalls = 0;
        final client = MockClient((request) async {
          requests++;
          return provider == 'gemini'
              ? _geminiResponse(requests, true)
              : _claudeResponse(requests, true);
        });
        addTearDown(client.close);
        final control = SpendRoundControl(
          beforeRequest: (usage, rounds) async {
            if (usage.totalTokens >= 100) {
              throw const SpendLimitExceeded('Limit reached');
            }
            return null;
          },
        );
        final send = provider == 'claude' ? sendClaudeStream : sendGoogleStream;

        await expectLater(
          send(
            client,
            _config(provider),
            provider == 'gemini' ? 'gemini-3-flash' : 'claude-sonnet-4-5',
            [
              {'role': 'user', 'content': 'Check'},
            ],
            tools: _tools,
            onToolCall: (name, args, {toolCallId}) async {
              toolCalls++;
              return 'Found';
            },
            spendControl: control,
          ).toList(),
          throwsA(isA<SpendLimitExceeded>()),
        );
        expect(requests, 1);
        expect(toolCalls, 0);
        expect(control.completedRounds, 1);
      },
    );

    test(
      '$provider adds a warning when the original system is empty',
      () async {
        final requests = <Map<String, dynamic>>[];
        final client = MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return provider == 'gemini'
              ? _geminiResponse(requests.length, false)
              : _claudeResponse(requests.length, false);
        });
        addTearDown(client.close);
        final control = SpendRoundControl(
          beforeRequest: (usage, rounds) async =>
              rounds > 0 ? 'Spend control — small replies' : null,
        );

        await _send(provider, client, control, [
          {'role': 'user', 'content': 'Check'},
        ], stream: false).toList();

        expect(requests, hasLength(2));
        if (provider == 'gemini') {
          expect(
            jsonEncode(requests.last['systemInstruction']),
            contains('small replies'),
          );
        } else {
          expect(requests.last['system'], contains('small replies'));
          expect(
            (requests.last['messages'] as List).where(
              (m) => (m as Map)['role'] == 'system',
            ),
            isEmpty,
          );
        }
      },
    );

    for (final stream in [false, true]) {
      test('$provider accounts each round once (stream=$stream)', () async {
        final requests = <Map<String, dynamic>>[];
        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': 'Instructions'},
          {'role': 'user', 'content': 'Check'},
        ];
        final client = MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return provider == 'gemini'
              ? _geminiResponse(requests.length, stream)
              : _claudeResponse(requests.length, stream);
        });
        addTearDown(client.close);
        final control = SpendRoundControl(
          beforeRequest: (usage, rounds) async => rounds > 0
              ? 'Spend control — ${usage.promptTokens + usage.completionTokens} used'
              : null,
        );

        await _send(
          provider,
          client,
          control,
          messages,
          stream: stream,
        ).toList();

        expect(requests, hasLength(2));
        expect(control.completedRounds, 2);
        expect(
          control.completedUsage.promptTokens,
          provider == 'gemini' ? 300 : 390,
        );
        expect(control.completedUsage.completionTokens, 60);
        expect(control.completedUsage.cachedTokens, 90);
        expect(messages.first['content'], 'Instructions');
        expect(jsonEncode(requests.last), contains('Found'));
        expect(jsonEncode(requests.first), isNot(contains('Spend control')));
        expect(
          jsonEncode(requests.last),
          contains(provider == 'gemini' ? '120 used' : '210 used'),
        );
      });
    }
  }

  for (final provider in ['claude', 'gemini']) {
    test('$provider stops a continuation without client calls', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (provider == 'claude') {
          return http.Response(
            'event: message_start\n'
            'data: {"type":"message_start","message":{"usage":{"input_tokens":100,"output_tokens":0}}}\n\n'
            'event: message_delta\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"pause_turn"},"usage":{"output_tokens":20}}\n\n'
            'event: message_stop\n'
            'data: {"type":"message_stop"}\n\n',
            200,
          );
        }
        return http.Response(
          'data: {"candidates":[{"finishReason":"MALFORMED_RESPONSE","content":{"parts":[]}}],"usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":20,"totalTokenCount":120}}\n\n',
          200,
        );
      });
      addTearDown(client.close);
      final control = SpendRoundControl(
        beforeRequest: (usage, rounds) async {
          if (usage.totalTokens >= 100) {
            throw const SpendLimitExceeded('Limit reached');
          }
          return null;
        },
      );

      await expectLater(
        _send(provider, client, control, [
          {'role': 'user', 'content': 'Check'},
        ], stream: true).toList(),
        throwsA(isA<SpendLimitExceeded>()),
      );
      expect(requests, 1);
      expect(control.completedRounds, 1);
      expect(control.completedUsage.totalTokens, 120);
    });
  }
}
