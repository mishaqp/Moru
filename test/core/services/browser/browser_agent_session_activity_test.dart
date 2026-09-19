import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = BrowserAgentSession.instance;

  setUp(() {
    session.currentActivity.value = null;
    session.recentActivity.clear();
  });

  test('recordActivity updates both the current value and the log', () {
    session.recordActivity(
      const BrowserActivity(action: 'open', detail: 'https://example.com'),
    );

    expect(session.currentActivity.value?.action, 'open');
    expect(session.currentActivity.value?.detail, 'https://example.com');
    expect(session.recentActivity, hasLength(1));
    expect(session.recentActivity.single.action, 'open');
  });

  test('recentActivity keeps insertion order, oldest first', () {
    session.recordActivity(const BrowserActivity(action: 'open'));
    session.recordActivity(const BrowserActivity(action: 'observe'));
    session.recordActivity(const BrowserActivity(action: 'click'));

    expect(session.recentActivity.map((a) => a.action), [
      'open',
      'observe',
      'click',
    ]);
    expect(session.currentActivity.value?.action, 'click');
  });

  test('recentActivity is capped so it cannot grow without bound', () {
    for (var i = 0; i < 40; i++) {
      session.recordActivity(BrowserActivity(action: 'scroll', detail: '$i'));
    }

    expect(session.recentActivity.length, 30);
    expect(session.recentActivity.first.detail, '10');
    expect(session.recentActivity.last.detail, '39');
  });
}
