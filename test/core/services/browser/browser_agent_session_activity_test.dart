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

  test(
    'page counts retain opaque identity through navigation and resolution',
    () {
      session.pageStarted('https://example.com/first');
      session.pageFinished('https://example.com/first');
      final first = session.recordActivity(action: 'observe');
      session.resolveActivity(first, BrowserActivityOutcome.ok);
      expect(session.activityCountForPage('https://example.com/first'), 1);
      final key = session.recentActivity.single.pageKey!;
      expect(key, isNot(contains('example.com')));
      expect(key, isNot(contains('/first')));

      final opening = session.recordActivity(action: 'open');
      session.pageStarted('https://example.com/second');
      session.pageFinished('https://example.com/second');
      session.resolveActivity(
        opening,
        BrowserActivityOutcome.ok,
        destinationPageKey: session.activityPageKey(
          'https://example.com/second',
          tabId: null,
        ),
        destinationCaptured: true,
      );
      expect(session.activityCountForPage('https://example.com/first'), 1);
      expect(session.activityCountForPage('https://example.com/second'), 1);
      expect(session.recentActivity.first.pageKey, key);
    },
  );

  test('late resolution cannot borrow a newer action destination page', () {
    session.pageStarted('https://example.com/first');
    session.pageFinished('https://example.com/first');
    final older = session.recordActivity(action: 'open');
    session.pageStarted('https://example.com/second');
    session.pageFinished('https://example.com/second');
    final newer = session.recordActivity(action: 'observe');
    session.resolveActivity(newer, BrowserActivityOutcome.ok);
    session.resolveActivity(older, BrowserActivityOutcome.ok);
    expect(session.activityCountForPage('https://example.com/first'), 1);
    expect(session.activityCountForPage('https://example.com/second'), 1);
  });

  test('authentication pages retain no activity page identity', () {
    const url = 'https://auth.openai.com/authorize?code=private&state=secret';
    session.pageStarted(url);
    session.pageFinished(url);
    session.recordActivity(action: 'observe');
    expect(session.recentActivity.single.pageKey, isNull);
    expect(session.activityCountForPage(url), 0);
  });

  test(
    'actions after a redirect use the committed page rather than the started URL',
    () {
      const source = 'https://example.com/redirect';
      const landing = 'https://example.com/home';
      session.pageStarted(source);
      session.pageFinished(landing);
      session.recordActivity(action: 'observe');
      expect(session.activityCountForPage(landing), 1);
      expect(session.activityCountForPage(source), 0);
    },
  );

  test(
    'a redirect to an authentication page retains no public attribution',
    () {
      session.pageStarted('https://example.com/redirect');
      session.pageFinished('https://auth.openai.com/authorize?code=private');
      session.recordActivity(action: 'observe');
      expect(session.recentActivity.single.pageKey, isNull);
      expect(session.activityCountForPage('https://example.com/redirect'), 0);
    },
  );

  test('the current page counter includes actions beyond the bounded log', () {
    const url = 'https://example.com/many';
    session.pageStarted(url);
    session.pageFinished(url);
    for (var i = 0; i < 41; i++) {
      final id = session.recordActivity(action: 'scroll');
      session.resolveActivity(id, BrowserActivityOutcome.ok);
    }
    expect(session.recentActivity, hasLength(30));
    expect(session.activityCountForPage(url), 41);
  });

  test(
    'current activity retains captured destination after manual navigation',
    () {
      const source = 'https://example.com/source';
      const target = 'https://example.com/target';
      const manual = 'https://example.com/manual';
      session.pageStarted(source);
      session.pageFinished(source);
      final id = session.recordActivity(action: 'open');
      final destination = session.activityPageKey(target, tabId: null);
      session.pageStarted(manual);
      session.pageFinished(manual);
      session.resolveActivity(
        id,
        BrowserActivityOutcome.ok,
        destinationPageKey: destination,
        destinationCaptured: true,
      );
      expect(session.activityCountForPage(source), 0);
      expect(session.activityCountForPage(target), 1);
      expect(session.activityCountForPage(manual), 0);
    },
  );

  test('a captured auth destination removes original page attribution', () {
    const source = 'https://example.com/source';
    session.pageStarted(source);
    session.pageFinished(source);
    final id = session.recordActivity(action: 'open');
    session.resolveActivity(
      id,
      BrowserActivityOutcome.ok,
      destinationPageKey: session.activityPageKey(
        'https://auth.openai.com/authorize?code=private',
        tabId: null,
      ),
      destinationCaptured: true,
    );
    expect(session.activityCountForPage(source), 0);
    expect(session.recentActivity.single.pageKey, isNull);
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
