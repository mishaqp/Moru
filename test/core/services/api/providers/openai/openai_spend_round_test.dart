import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/generation/spend_round_control.dart';
import 'package:Kelivo/core/services/api/providers/openai/openai_provider.dart';

ProviderConfig _config() => ProviderConfig(
  id: 'spend-test',
  name: 'Spend test',
  enabled: true,
  baseUrl: 'https://example.test/v1',
  apiKey: 'test',
  providerType: ProviderKind.openai,
);

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'lookup',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  },
];

Map<String, dynamic> _response(int round, {bool stream = false}) {
  final call = {
    'id': 'call_$round',
    'type': 'function',
    'function': {'name': 'lookup', 'arguments': '{}'},
  };
  return {
    'choices': [
      {
        'index': 0,
        stream ? 'delta' : 'message': {
          'role': 'assistant',
          'content': round < 3 ? '' : 'Done',
          if (round < 3) 'tool_calls': [call],
        },
        'finish_reason': round < 3 ? 'tool_calls' : 'stop',
      },
    ],
    'usage': {
      'prompt_tokens': round * 100,
      'completion_tokens': round * 20,
      'prompt_tokens_details': {'cached_tokens': round == 1 ? 90 : 0},
    },
  };
}

void main() {
  for (final doneSentinel in [false, true]) {
    test(
      'OpenAI drains trailing usage before tools (DONE=$doneSentinel)',
      () async {
        var requests = 0;
        var toolCalls = 0;
        final client = MockClient((request) async {
          requests++;
          if (requests > 1) {
            return http.Response(
              'data: ${jsonEncode(_response(3, stream: true))}\n\ndata: [DONE]\n\n',
              200,
            );
          }
          final toolResponse = _response(1, stream: true);
          final usage = toolResponse.remove('usage');
          return http.Response(
            'data: ${jsonEncode(toolResponse)}\n\n'
            'data: ${jsonEncode({'choices': [], 'usage': usage})}\n\n'
            '${doneSentinel ? 'data: [DONE]\n\n' : ''}',
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
          sendOpenAIStream(
            client,
            _config(),
            'model',
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
        expect(control.completedUsage.totalTokens, 120);
      },
    );
  }

  test(
    'Responses rounds count fresh usage and replace request warnings',
    () async {
      final requests = <Map<String, dynamic>>[];
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Instructions'},
        {'role': 'user', 'content': 'Check'},
      ];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        final round = requests.length;
        final output = round == 1
            ? [
                {
                  'type': 'function_call',
                  'id': 'fc_1',
                  'call_id': 'call_1',
                  'name': 'lookup',
                  'arguments': '{}',
                  'status': 'completed',
                },
              ]
            : [];
        final events = [
          if (round == 1)
            {
              'type': 'response.output_item.done',
              'output_index': 0,
              'item': output.single,
            }
          else
            {'type': 'response.output_text.delta', 'delta': 'Done'},
          {
            'type': 'response.completed',
            'response': {
              'output': output,
              'usage': {
                'input_tokens': round * 100,
                'output_tokens': round * 20,
                'input_tokens_details': {'cached_tokens': round == 1 ? 90 : 0},
              },
            },
          },
        ];
        return http.Response(
          events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
          200,
        );
      });
      addTearDown(client.close);
      final control = SpendRoundControl(
        beforeRequest: (usage, rounds) async =>
            rounds > 0 ? 'Spend control — 120 used' : null,
      );

      await sendOpenAIStream(
        client,
        _config().copyWith(useResponseApi: true),
        'model',
        messages,
        tools: _tools,
        onToolCall: (name, args, {toolCallId}) async => 'Found',
        spendControl: control,
      ).toList();

      expect(requests, hasLength(2));
      expect(control.completedRounds, 2);
      expect(control.completedUsage.promptTokens, 300);
      expect(control.completedUsage.completionTokens, 60);
      expect(control.completedUsage.cachedTokens, 90);
      expect(messages.first['content'], 'Instructions');
      expect(requests.last['instructions'], contains('120 used'));
    },
  );

  for (final stream in [false, true]) {
    test('spend guard stops OpenAI follow-ups (stream=$stream)', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final response = _response(requests, stream: stream);
        return http.Response(
          stream
              ? 'data: ${jsonEncode(response)}\n\ndata: [DONE]\n\n'
              : jsonEncode(response),
          200,
        );
      });
      addTearDown(client.close);
      final control = SpendRoundControl(
        beforeRequest: (usage, rounds) async {
          if (usage.promptTokens + usage.completionTokens >= 100) {
            throw const SpendLimitExceeded('Limit reached');
          }
          return null;
        },
      );

      await expectLater(
        sendOpenAIStream(
          client,
          _config(),
          'model',
          [
            {'role': 'user', 'content': 'Check'},
          ],
          tools: _tools,
          onToolCall: (name, args, {toolCallId}) async => 'Found',
          stream: stream,
          spendControl: control,
        ).toList(),
        throwsA(isA<SpendLimitExceeded>()),
      );
      expect(requests, 1);
      expect(control.completedUsage.promptTokens, 100);
      expect(control.completedUsage.completionTokens, 20);
    });

    test('OpenAI rounds count fresh usage and request-only warnings '
        '(stream=$stream)', () async {
      final requests = <Map<String, dynamic>>[];
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Instructions'},
        {'role': 'user', 'content': 'Check'},
      ];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        final response = _response(requests.length, stream: stream);
        return http.Response(
          stream
              ? 'data: ${jsonEncode(response)}\n\ndata: [DONE]\n\n'
              : jsonEncode(response),
          200,
        );
      });
      addTearDown(client.close);
      final control = SpendRoundControl(
        beforeRequest: (usage, rounds) async => rounds > 0
            ? 'Spend control — ${usage.promptTokens + usage.completionTokens} used'
            : null,
      );

      await sendOpenAIStream(
        client,
        _config(),
        'model',
        messages,
        tools: _tools,
        onToolCall: (name, args, {toolCallId}) async => 'Found',
        stream: stream,
        spendControl: control,
      ).toList();

      expect(requests, hasLength(3));
      expect(control.completedRounds, 3);
      expect(control.completedUsage.promptTokens, 600);
      expect(control.completedUsage.completionTokens, 120);
      expect(control.completedUsage.cachedTokens, 90);
      expect(messages.first['content'], 'Instructions');
      expect(jsonEncode(requests.first), isNot(contains('Spend control')));
      expect(jsonEncode(requests[1]), contains('120 used'));
      expect(jsonEncode(requests[2]), contains('360 used'));
      expect(jsonEncode(requests[2]), isNot(contains('120 used')));
    });
  }
}
