import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submit assigns a unique id per call and emits a request', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);

    final received = <BrowserAskAiRequest>[];
    final sub = bridge.requests.listen(received.add);
    addTearDown(sub.cancel);

    final idA = bridge.submit('open example.com');
    final idB = bridge.submit('click the first link');
    await pumpEventQueue();

    expect(idA, isNot(idB));
    expect(received.map((r) => r.id), [idA, idB]);
    expect(received.map((r) => r.text), [
      'open example.com',
      'click the first link',
    ]);
  });

  test('cancel emits the request id on the cancellations stream', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);

    final cancelled = <String>[];
    final sub = bridge.cancellations.listen(cancelled.add);
    addTearDown(sub.cancel);

    bridge.cancel('req-1');
    await pumpEventQueue();

    expect(cancelled, ['req-1']);
  });

  test('reportOutcome emits on the outcomes stream', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);

    final outcomes = <BrowserAskAiOutcome>[];
    final sub = bridge.outcomes.listen(outcomes.add);
    addTearDown(sub.cancel);

    bridge.reportOutcome(
      const BrowserAskAiOutcome(requestId: 'req-1', ok: true),
    );
    bridge.reportOutcome(
      const BrowserAskAiOutcome(
        requestId: 'req-2',
        ok: false,
        error: 'no_conversation',
      ),
    );
    await pumpEventQueue();

    expect(outcomes, hasLength(2));
    expect(outcomes[0].ok, isTrue);
    expect(outcomes[0].error, isNull);
    expect(outcomes[1].ok, isFalse);
    expect(outcomes[1].error, 'no_conversation');
  });

  test(
    'consumeEarlyCancellation reports a cancel that raced submit, exactly once',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);

      bridge.cancel('req-1');

      expect(bridge.consumeEarlyCancellation('req-1'), isTrue);
      expect(bridge.consumeEarlyCancellation('req-1'), isFalse);
      expect(bridge.consumeEarlyCancellation('req-2'), isFalse);
    },
  );

  test('askAiErrorMessage covers every code the runner reports', () {
    expect(
      askAiErrorMessage('no_conversation', ru: true),
      'Нет активного чата.',
    );
    expect(
      askAiErrorMessage('no_conversation', ru: false),
      'No active conversation.',
    );
    expect(
      askAiErrorMessage('no_assistant', ru: false),
      'No assistant found for this conversation.',
    );
    expect(
      askAiErrorMessage('in_flight', ru: false),
      'The chat is already generating a reply.',
    );
    expect(
      askAiErrorMessage('some_unmapped_chat_action_error', ru: false),
      'Could not run the command.',
    );
    expect(askAiErrorMessage(null, ru: false), 'Could not run the command.');
  });

  test(
    'multiple listeners on the same broadcast stream all receive events',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);

      final first = <BrowserAskAiRequest>[];
      final second = <BrowserAskAiRequest>[];
      final subA = bridge.requests.listen(first.add);
      final subB = bridge.requests.listen(second.add);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      bridge.submit('do something');
      await pumpEventQueue();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    },
  );
}
