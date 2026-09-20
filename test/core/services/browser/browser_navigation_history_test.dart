import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserNavigationHistory', () {
    test('back and forward follow committed agent pages', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/b')
        ..push('https://example.com/c');

      expect(history.current, 'https://example.com/c');
      expect(history.backTarget, 'https://example.com/b');
      expect(history.canGoBack, isTrue);
      expect(history.canGoForward, isFalse);

      history.commitBack();
      expect(history.current, 'https://example.com/b');
      expect(history.backTarget, 'https://example.com/a');
      expect(history.forwardTarget, 'https://example.com/c');

      history.commitBack();
      expect(history.current, 'https://example.com/a');
      expect(history.canGoBack, isFalse);
      expect(history.forwardTarget, 'https://example.com/b');

      history.commitForward();
      expect(history.current, 'https://example.com/b');
      history.commitForward();
      expect(history.current, 'https://example.com/c');
      expect(history.canGoForward, isFalse);
    });

    test('new navigation after back discards forward entries', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/b')
        ..push('https://example.com/c');

      history.commitBack();
      expect(history.current, 'https://example.com/b');
      expect(history.canGoForward, isTrue);

      history.push('https://example.com/d');

      expect(history.current, 'https://example.com/d');
      expect(history.canGoForward, isFalse);
      expect(history.backTarget, 'https://example.com/b');
    });

    test('duplicate committed URL does not create another entry', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/a');

      expect(history.current, 'https://example.com/a');
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
    });

    test('clear removes the whole agent history', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/b')
        ..clear();

      expect(history.current, isNull);
      expect(history.backTarget, isNull);
      expect(history.forwardTarget, isNull);
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
    });
  });

  // Scenarios (a)-(d) from AGENTS.md section 8: reconcileCommitted() is the
  // single place every committed navigation on the shared controller (agent
  // action or user-driven) goes through, so the model's own back/forward
  // stay accurate no matter who navigated.
  group('BrowserNavigationHistory.reconcileCommitted', () {
    test('(a) agent opens A then B, then goes back: back lands on A', () {
      final history = BrowserNavigationHistory();
      // "open" and a click-then-navigate both commit through the same
      // central hook in production; simulated directly here.
      history.reconcileCommitted('https://example.com/a');
      history.reconcileCommitted('https://example.com/b');
      expect(history.backTarget, 'https://example.com/a');

      // The agent's back action replays backTarget and then reconciles
      // the resulting committed navigation, exactly like production.
      final target = history.backTarget!;
      history.reconcileCommitted(target);
      expect(history.current, 'https://example.com/a');
    });

    test('(b) user manually navigates past the agent-known page, then the '
        'agent calls back: it still finds a previous page instead of '
        'reporting no_history', () {
      final history = BrowserNavigationHistory();
      history.reconcileCommitted('https://example.com/a');
      // The user types a new address directly; nothing "pushed" this
      // through an agent action, but the committed navigation must still
      // reconcile through the same hook (onPageFinished, in production).
      history.reconcileCommitted('https://example.com/manual-b');

      expect(history.current, 'https://example.com/manual-b');
      expect(history.backTarget, 'https://example.com/a');
      expect(history.canGoBack, isTrue);

      history.reconcileCommitted(history.backTarget!);
      expect(history.current, 'https://example.com/a');
    });

    test('(c) native UI back/forward do not themselves call reconcileCommitted '
        '-- history only updates once the resulting committed navigation is '
        'reconciled, matching what onPageFinished would report', () {
      final history = BrowserNavigationHistory();
      history.reconcileCommitted('https://example.com/a');
      history.reconcileCommitted('https://example.com/b');

      // Simulates the WebView's native goBack() committing back to "a"
      // (the UI never touches `history` directly -- only the resulting
      // onPageFinished("a") does, via reconcileCommitted).
      history.reconcileCommitted('https://example.com/a');

      expect(history.current, 'https://example.com/a');
      expect(history.canGoForward, isTrue);
      expect(history.forwardTarget, 'https://example.com/b');
    });

    test('(d) a redirect (A then immediately B, no navigation action in '
        'between) is reconciled as a new page, not a back/forward match', () {
      final history = BrowserNavigationHistory();
      history.reconcileCommitted('https://example.com/a');
      // Simulates two onPageStarted/onPageFinished pairs firing back to
      // back for a redirect: A committed, then B committed right after,
      // with no back/forward target for B to match.
      history.reconcileCommitted('https://example.com/redirected-b');

      expect(history.current, 'https://example.com/redirected-b');
      expect(history.backTarget, 'https://example.com/a');
      expect(history.canGoForward, isFalse);
    });

    test('reconcileCommitted resets an empty history to the first page', () {
      final history = BrowserNavigationHistory();
      history.reconcileCommitted('https://example.com/first');
      expect(history.current, 'https://example.com/first');
      expect(history.canGoBack, isFalse);
    });

    test('reconcileCommitted ignores an empty url', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a');
      history.reconcileCommitted('');
      expect(history.current, 'https://example.com/a');
    });

    test('reconcileCommitted is idempotent for the same committed url (no '
        'duplicate push when called twice, e.g. once from an explicit call '
        'site and once from onPageFinished)', () {
      final history = BrowserNavigationHistory();
      history.reconcileCommitted('https://example.com/a');
      history.reconcileCommitted('https://example.com/b');
      history.reconcileCommitted('https://example.com/b');

      expect(history.current, 'https://example.com/b');
      expect(history.backTarget, 'https://example.com/a');
      history.reconcileCommitted(history.backTarget!);
      expect(history.current, 'https://example.com/a');
      expect(history.canGoBack, isFalse);
    });

    test(
      'a forward match after commitBack does not truncate the forward entry',
      () {
        final history = BrowserNavigationHistory();
        history.reconcileCommitted('https://example.com/a');
        history.reconcileCommitted('https://example.com/b');
        history.reconcileCommitted('https://example.com/a'); // native back
        expect(history.forwardTarget, 'https://example.com/b');

        history.reconcileCommitted('https://example.com/b'); // native forward
        expect(history.current, 'https://example.com/b');
        expect(history.canGoForward, isFalse);
      },
    );
  });
}
