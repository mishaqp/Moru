import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = BrowserAgentSession.instance;

  setUp(() {
    session.currentActivity.value = null;
    session.recentActivityNotifier.value = const [];
  });

  test('recordActivity updates both the current value and the log', () {
    session.recordActivity(action: 'open', detail: 'https://example.com');

    expect(session.currentActivity.value?.action, 'open');
    expect(session.currentActivity.value?.detail, 'https://example.com');
    expect(session.recentActivity, hasLength(1));
    expect(session.recentActivity.single.action, 'open');
  });

  test('recordActivity returns a unique id per call, even for repeats', () {
    final first = session.recordActivity(action: 'click');
    final second = session.recordActivity(action: 'click');

    expect(first, isNot(second));
  });

  test('recentActivity keeps insertion order, oldest first', () {
    session.recordActivity(action: 'open');
    session.recordActivity(action: 'observe');
    session.recordActivity(action: 'click');

    expect(session.recentActivity.map((a) => a.action), [
      'open',
      'observe',
      'click',
    ]);
    expect(session.currentActivity.value?.action, 'click');
  });

  test('recentActivity is capped so it cannot grow without bound', () {
    for (var i = 0; i < 40; i++) {
      session.recordActivity(action: 'scroll', detail: '$i');
    }

    expect(session.recentActivity.length, 30);
    expect(session.recentActivity.first.detail, '10');
    expect(session.recentActivity.last.detail, '39');
  });

  test('a fresh activity starts as running with a startedAt time', () {
    final before = DateTime.now();
    session.recordActivity(action: 'click');

    expect(
      session.currentActivity.value?.outcome,
      BrowserActivityOutcome.running,
    );
    expect(
      session.currentActivity.value!.startedAt.isBefore(
        before.add(const Duration(seconds: 1)),
      ),
      isTrue,
    );
    expect(session.currentActivity.value?.finishedAt, isNull);
    expect(session.currentActivity.value?.duration, isNull);
  });

  test(
    'resolveActivity resolves the call it was given, by id, and records a duration',
    () {
      final id = session.recordActivity(action: 'click');

      session.resolveActivity(id, BrowserActivityOutcome.ok);

      expect(session.currentActivity.value?.outcome, BrowserActivityOutcome.ok);
      expect(session.recentActivity.single.outcome, BrowserActivityOutcome.ok);
      expect(session.recentActivity.single.finishedAt, isNotNull);
      expect(session.recentActivity.single.duration, isNotNull);
    },
  );

  test('resolveActivity(failed) resolves to failed', () {
    final id = session.recordActivity(action: 'click');

    session.resolveActivity(id, BrowserActivityOutcome.failed);

    expect(
      session.currentActivity.value?.outcome,
      BrowserActivityOutcome.failed,
    );
    expect(
      session.recentActivity.single.outcome,
      BrowserActivityOutcome.failed,
    );
  });

  test('resolveActivity(notFound) is distinct from ok and failed', () {
    final id = session.recordActivity(action: 'wait_for', detail: '.button');

    session.resolveActivity(id, BrowserActivityOutcome.notFound);

    expect(
      session.currentActivity.value?.outcome,
      BrowserActivityOutcome.notFound,
    );
  });

  test(
    'resolveActivity resolves the exact call by id, not just whichever is last',
    () {
      final firstId = session.recordActivity(action: 'open');
      final secondId = session.recordActivity(action: 'click');

      // Resolve the older call after a newer one has already started —
      // this is the scenario "action A finishes after B has started" from
      // the task: A's own outcome must land on A, not on whichever call is
      // currently last (which used to always win under the old API).
      session.resolveActivity(firstId, BrowserActivityOutcome.ok);

      expect(session.recentActivity[0].id, firstId);
      expect(session.recentActivity[0].outcome, BrowserActivityOutcome.ok);
      expect(session.recentActivity[1].id, secondId);
      expect(session.recentActivity[1].outcome, BrowserActivityOutcome.running);
    },
  );

  test('resolveActivity never overwrites an already-resolved entry', () {
    final id = session.recordActivity(action: 'click');
    session.resolveActivity(id, BrowserActivityOutcome.ok);

    // A duplicate or late-arriving resolution for the same call must not
    // downgrade an already-terminal outcome.
    session.resolveActivity(id, BrowserActivityOutcome.failed);

    expect(session.recentActivity.single.outcome, BrowserActivityOutcome.ok);
  });

  test('resolveActivity is a no-op for an unknown id', () {
    session.recordActivity(action: 'click');

    expect(
      () =>
          session.resolveActivity('does-not-exist', BrowserActivityOutcome.ok),
      returnsNormally,
    );
    expect(
      session.recentActivity.single.outcome,
      BrowserActivityOutcome.running,
    );
  });

  test('a late resolution for an id from a session that has since been cleared '
      'is a no-op and cannot affect a new session\'s activity', () {
    final staleId = session.recordActivity(action: 'click');
    // Simulates what `unregister()` does to the log when the browser
    // closes: clearing it invalidates every id from that session.
    session.recentActivityNotifier.value = const [];
    session.currentActivity.value = null;

    // A new session starts and records its own activity.
    final freshId = session.recordActivity(action: 'open');

    // The stale call's late result must not touch the new session's entry.
    session.resolveActivity(staleId, BrowserActivityOutcome.ok);

    expect(session.recentActivity.single.id, freshId);
    expect(
      session.recentActivity.single.outcome,
      BrowserActivityOutcome.running,
    );
  });

  test(
    'setOwnerConversationId records and overwrites the owning conversation',
    () {
      expect(session.ownerConversationId, isNull);
      session.setOwnerConversationId('conv-a');
      expect(session.ownerConversationId, 'conv-a');
      session.setOwnerConversationId('conv-b');
      expect(session.ownerConversationId, 'conv-b');
      session.setOwnerConversationId(null);
      expect(session.ownerConversationId, isNull);
    },
  );
}
