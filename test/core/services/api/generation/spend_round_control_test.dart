import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/token_usage.dart';
import 'package:Kelivo/core/services/api/generation/spend_round_control.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';

void main() {
  test(
    'provider system shapes replace an initial notice inside merged text',
    () async {
      final control = SpendRoundControl(
        initialWarning: 'old warning',
        beforeRequest: (_, _) async => 'new warning',
      );
      await control.beforeRequest();
      final responses = {
        'input': [],
        'instructions': 'first\n\nold warning\n\nlast',
      };
      expect(
        control.decorateRequest(responses)['instructions'],
        'first\n\nlast\n\nnew warning',
      );
      final claude = <String, dynamic>{
        'messages': [],
        'system': [
          {'type': 'text', 'text': 'first'},
          {
            'type': 'text',
            'text': 'last\n\nold warning',
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      };
      final system = control.decorateRequest(claude)['system'] as List;
      expect(system.first['text'], 'first\n\nnew warning');
      expect(system.last['text'], 'last');
      expect(system.last['cache_control'], {'type': 'ephemeral'});
      expect((claude['system'] as List).last['text'], 'last\n\nold warning');
      final gemini = {
        'contents': [],
        'systemInstruction': {
          'parts': [
            {'text': 'first\n\nold warning'},
          ],
        },
      };
      expect(
        (control.decorateRequest(gemini)['systemInstruction'] as Map)['parts'],
        [
          {'text': 'first\n\nnew warning'},
        ],
      );
      expect(
        control.decorateRequest({
          'messages': [],
        }, systemField: 'system')['system'],
        'new warning',
      );
    },
  );
  test('retains reported partial usage if a model request fails', () async {
    final control = SpendRoundControl(beforeRequest: (_, _) async => null);
    Stream<StreamChunk> failingRound() async* {
      yield const Usage(
        TokenUsage(promptTokens: 60, completionTokens: 5, cachedTokens: 40),
      );
      throw StateError('connection lost');
    }

    await expectLater(
      control.trackRound(failingRound()).drain<void>(),
      throwsStateError,
    );
    expect(control.completedRounds, 0);
    expect(control.completedUsage.promptTokens, 0);
    expect(control.pendingUsage!.promptTokens, 60);
    expect(control.pendingUsage!.cachedTokens, 40);
  });
  test('sums completed rounds, not repeated usage snapshots', () async {
    final control = SpendRoundControl(beforeRequest: (_, _) async => null);
    await control
        .trackRound(
          Stream.fromIterable([
            const Usage(TokenUsage(promptTokens: 60, completionTokens: 5)),
            const Usage(TokenUsage(promptTokens: 60, completionTokens: 10)),
          ]),
        )
        .drain<void>();
    await control
        .trackRound(
          Stream.value(
            const Usage(
              TokenUsage(
                promptTokens: 90,
                completionTokens: 20,
                cachedTokens: 70,
              ),
            ),
          ),
        )
        .drain<void>();
    expect(control.completedUsage.promptTokens, 150);
    expect(control.completedUsage.completionTokens, 30);
    expect(control.completedUsage.cachedTokens, 70);
    expect(control.lastUsage.totalTokens, 110);
    expect(control.completedRounds, 2);
  });

  test(
    'replaces only request warning and leaves original transcript intact',
    () async {
      final control = SpendRoundControl(
        initialWarning: 'old warning',
        beforeRequest: (_, _) async => 'new warning',
      );
      await control.beforeRequest();
      final body = <String, dynamic>{
        'messages': [
          {'role': 'system', 'content': 'instructions\n\nold warning'},
          {'role': 'user', 'content': 'old warning'},
        ],
      };
      final sent = control.decorateRequest(body);
      expect(
        (sent['messages'] as List).first['content'],
        'instructions\n\nnew warning',
      );
      expect(
        (body['messages'] as List).first['content'],
        'instructions\n\nold warning',
      );
      expect((sent['messages'] as List).last['content'], 'old warning');
    },
  );

  test('without a warning request body remains identical', () async {
    final control = SpendRoundControl(beforeRequest: (_, _) async => null);
    await control.beforeRequest();
    final body = <String, dynamic>{
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
    };
    expect(identical(control.decorateRequest(body), body), isTrue);
  });
}
