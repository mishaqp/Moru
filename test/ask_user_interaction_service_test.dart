import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';

void _normalizeCollidingQuestionIds(SendPort port) {
  final questions = AskUserInteractionService.normalizeQuestions(const {
    'questions': [
      {'id': 'q3', 'question': 'First?'},
      {'id': 'q3_3', 'question': 'Second?'},
      {'question': 'Third?'},
    ],
  });
  port.send(questions.map((question) => question.id).toList());
}

void main() {
  group('AskUserInteractionService', () {
    test('generated question ids advance past repeated collisions', () async {
      // Isolate the synchronous normalizer so a regression cannot block the
      // runner indefinitely; always stop the isolate after the assertion.
      final port = ReceivePort();
      final worker = await Isolate.spawn(
        _normalizeCollidingQuestionIds,
        port.sendPort,
      );
      try {
        final ids = await port.first.timeout(const Duration(seconds: 5));
        expect(ids, ['q3', 'q3_3', 'q3_4']);
      } finally {
        worker.kill(priority: Isolate.immediate);
        port.close();
      }
    });

    test(
      'replacing a repeated call id cancels its previous pending result',
      () async {
        final service = AskUserInteractionService();
        addTearDown(service.cancelAll);
        const arguments = {
          'questions': [
            {'id': 'q', 'question': 'Choose?'},
          ],
        };
        final first = service.requestAnswer(
          toolCallId: 'same',
          arguments: arguments,
          conversationId: 'chat',
        );
        final second = service.requestAnswer(
          toolCallId: 'same',
          arguments: arguments,
          conversationId: 'chat',
        );
        expect(
          (await first.timeout(const Duration(seconds: 1))).error,
          'cancelled',
        );
        expect(service.pendingRequests, hasLength(1));
        service.answer('same', const {
          'q': AskUserAnswerValue.single(value: 'answer', custom: true),
        });
        expect((await second).answers['q']!.value, 'answer');
      },
    );

    test(
      'disposing cancels waiting results and rejects later requests',
      () async {
        final service = AskUserInteractionService();
        const arguments = {
          'questions': [
            {'id': 'q', 'question': 'Choose?'},
          ],
        };
        final pending = service.requestAnswer(
          toolCallId: 'wait',
          arguments: arguments,
        );
        service.dispose();
        expect(
          (await pending.timeout(const Duration(seconds: 1))).error,
          'cancelled',
        );
        expect(service.pendingRequests, isEmpty);
        final later = await service.requestAnswer(
          toolCallId: 'later',
          arguments: arguments,
        );
        expect(later.error, 'cancelled');
        expect(service.pendingRequests, isEmpty);
      },
    );

    test(
      'normalizes questions and completes with structured answers',
      () async {
        final service = AskUserInteractionService();
        final future = service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {
            'questions': [
              {
                'id': 'scope',
                'question': 'Choose scope?',
                'type': 'single',
                'options': ['Minimal', 'Complete'],
              },
              {
                'id': 'scope',
                'question': 'Add what?',
                'type': 'multi',
                'options': ['UI', 'Tests', ''],
              },
              {'question': 'Fallback choice?', 'type': 'unknown'},
            ],
          },
        );

        expect(service.pendingRequests.keys, contains('call_1'));
        final request = service.pendingRequests['call_1']!;
        expect(request.questions.map((question) => question.id), const [
          'scope',
          'q2',
          'q3',
        ]);
        expect(request.questions[0].kind, AskUserQuestionKind.single);
        expect(request.questions[1].kind, AskUserQuestionKind.multi);
        expect(request.questions[1].options, const ['UI', 'Tests']);
        expect(request.questions[2].kind, AskUserQuestionKind.single);

        service.answer('call_1', {
          'scope': const AskUserAnswerValue.single(
            value: 'Complete',
            custom: false,
          ),
          'q2': const AskUserAnswerValue.multi(
            value: ['UI', 'Tests'],
            custom: false,
          ),
          'q3': const AskUserAnswerValue.skipped(
            kind: AskUserQuestionKind.single,
          ),
        });

        final result = await future;
        expect(service.pendingRequests, isEmpty);
        final payload =
            jsonDecode(result.toJsonString()) as Map<String, dynamic>;
        expect(payload['type'], 'ask_user_answer');
        expect(payload['answers']['scope']['value'], 'Complete');
        expect(payload['answers']['q2']['value'], const ['UI', 'Tests']);
        expect(payload['answers']['q3']['skipped'], isTrue);
      },
    );

    test('throws for empty questions before creating pending request', () {
      final service = AskUserInteractionService();

      expect(
        () => service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {'questions': []},
        ),
        throwsA(isA<AskUserInvalidRequestException>()),
      );
      expect(service.pendingRequests, isEmpty);
    });

    test(
      'cancelAll completes pending requests with cancelled result',
      () async {
        final service = AskUserInteractionService();
        final future = service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {
            'questions': [
              {'id': 'notes', 'question': 'Any notes?', 'type': 'single'},
            ],
          },
        );

        service.cancelAll();

        final result = await future.timeout(const Duration(seconds: 1));
        expect(service.pendingRequests, isEmpty);
        final payload =
            jsonDecode(result.toJsonString()) as Map<String, dynamic>;
        expect(payload['type'], 'tool_error');
        expect(payload['error'], 'cancelled');
        expect(payload['tool'], 'ask_user_input_v0');
      },
    );

    test('keeps choice questions even when options are sparse', () async {
      final service = AskUserInteractionService();
      unawaited(
        service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {
            'questions': [
              {
                'id': 'scope',
                'question': 'Choose scope?',
                'type': 'single',
                'options': ['Only one'],
              },
            ],
          },
        ),
      );

      expect(
        service.pendingRequests['call_1']!.questions.single.kind,
        AskUserQuestionKind.single,
      );
      service.cancelAll();
    });
  });
}
