import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/shared/pages/webview/webview_ask_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BrowserAskAiBridge bridge;
  late AskAiPanelController controller;

  setUp(() {
    bridge = BrowserAskAiBridge();
    controller = AskAiPanelController(
      bridge: bridge,
      completedHoldDuration: const Duration(milliseconds: 50),
    );
  });

  tearDown(() {
    controller.dispose();
    bridge.dispose();
  });

  test('starts idle', () {
    expect(controller.state, AskAiPanelState.idle);
    expect(controller.activeRequestId, isNull);
    expect(controller.isBusy, isFalse);
  });

  test('submit() moves to starting and returns an id', () {
    final id = controller.submit('open example.com');
    expect(id, isNotNull);
    expect(controller.state, AskAiPanelState.starting);
    expect(controller.activeRequestId, id);
    expect(controller.isBusy, isTrue);
  });

  test('submit() with blank text does nothing', () {
    final id = controller.submit('   ');
    expect(id, isNull);
    expect(controller.state, AskAiPanelState.idle);
  });

  test('double-tap submit only submits once', () {
    final requests = <String>[];
    bridge.requests.listen((r) => requests.add(r.id));

    final first = controller.submit('hi');
    final second = controller.submit('hi again');

    expect(first, isNotNull);
    expect(second, isNull, reason: 'busy: a request is already in flight');
  });

  test('noteActivity() advances starting to running', () {
    controller.submit('do something');
    expect(controller.state, AskAiPanelState.starting);

    controller.noteActivity();

    expect(controller.state, AskAiPanelState.running);
  });

  test('noteActivity() is a no-op with no active request', () {
    controller.noteActivity();
    expect(controller.state, AskAiPanelState.idle);
  });

  test('setPendingApproval(true) moves running to awaitingApproval, and back '
      'on false', () {
    controller.submit('click something');
    controller.noteActivity();
    expect(controller.state, AskAiPanelState.running);

    controller.setPendingApproval(true);
    expect(controller.state, AskAiPanelState.awaitingApproval);

    controller.setPendingApproval(false);
    expect(controller.state, AskAiPanelState.running);
  });

  test(
    'stop() moves to stopping and cancels exactly once on a double tap',
    () async {
      final cancelled = <String>[];
      bridge.cancellations.listen(cancelled.add);
      final id = controller.submit('hi')!;

      controller.stop();
      controller.stop();
      await pumpEventQueue();

      expect(controller.state, AskAiPanelState.stopping);
      expect(cancelled, [id]);
    },
  );

  test('stop() with no active request does nothing', () {
    controller.stop();
    expect(controller.state, AskAiPanelState.idle);
  });

  test('a cancelled outcome for the active request moves to stopped', () async {
    final id = controller.submit('hi')!;
    controller.stop();

    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: id, ok: false, cancelled: true),
    );
    await pumpEventQueue();

    expect(controller.state, AskAiPanelState.stopped);
    expect(controller.activeRequestId, isNull);
    expect(controller.lastOutcome?.cancelled, isTrue);
  });

  test('an ok outcome moves to completed, then idle after the hold duration, '
      'without losing lastOutcome', () async {
    final id = controller.submit('summarize this')!;

    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: id,
        ok: true,
        answerText: 'The page is about flights.',
        conversationId: 'conv-1',
        assistantMessageId: 'msg-1',
      ),
    );
    await pumpEventQueue();

    expect(controller.state, AskAiPanelState.completed);
    expect(controller.lastOutcome?.answerText, 'The page is about flights.');

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.state, AskAiPanelState.idle);
    // lastOutcome is preserved for the caller (e.g. the result card) even
    // after the transient "completed" flash clears.
    expect(controller.lastOutcome?.answerText, 'The page is about flights.');
  });

  test('a failed (non-cancelled) outcome moves to error', () async {
    final id = controller.submit('hi')!;

    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: id, ok: false, error: 'no_conversation'),
    );
    await pumpEventQueue();

    expect(controller.state, AskAiPanelState.error);
    expect(controller.lastOutcome?.error, 'no_conversation');
  });

  test('an outcome for a different request id is ignored', () async {
    controller.submit('hi');

    bridge.reportOutcome(
      const BrowserAskAiOutcome(requestId: 'not-mine', ok: true),
    );
    await pumpEventQueue();

    expect(controller.state, AskAiPanelState.starting);
  });

  test(
    'dismiss() returns error/stopped to idle, but not other states',
    () async {
      final id = controller.submit('hi')!;
      bridge.reportOutcome(
        BrowserAskAiOutcome(requestId: id, ok: false, error: 'boom'),
      );
      await pumpEventQueue();
      expect(controller.state, AskAiPanelState.error);

      controller.dismiss();

      expect(controller.state, AskAiPanelState.idle);
      expect(controller.lastOutcome, isNull);

      // A no-op from idle.
      controller.dismiss();
      expect(controller.state, AskAiPanelState.idle);
    },
  );

  test(
    'cancelForClose() cancels the active request without changing state',
    () async {
      final cancelled = <String>[];
      bridge.cancellations.listen(cancelled.add);
      final id = controller.submit('hi')!;

      controller.cancelForClose();
      await pumpEventQueue();

      expect(cancelled, [id]);
      expect(controller.state, AskAiPanelState.starting);
    },
  );

  test('cancelForClose() with no active request is a safe no-op', () {
    expect(() => controller.cancelForClose(), returnsNormally);
  });

  test('submitting a new request clears the previous lastOutcome', () async {
    final first = controller.submit('first')!;
    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: first, ok: true, answerText: 'A'),
    );
    await pumpEventQueue();
    expect(controller.lastOutcome?.answerText, 'A');

    controller.submit('second');

    expect(controller.lastOutcome, isNull);
  });

  test('dispose() cancels the outcomes subscription (no late setState-able '
      'callback survives it)', () async {
    final localBridge = BrowserAskAiBridge();
    final localController = AskAiPanelController(bridge: localBridge);
    final id = localController.submit('hi')!;
    localController.dispose();

    // Reporting an outcome after dispose must not throw (no listener should
    // even be attached any more).
    expect(
      () => localBridge.reportOutcome(
        BrowserAskAiOutcome(requestId: id, ok: true, answerText: 'late'),
      ),
      returnsNormally,
    );
    await pumpEventQueue();
    localBridge.dispose();
  });
}
