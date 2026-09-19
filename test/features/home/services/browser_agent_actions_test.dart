import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_agent_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('byId finds a known action and returns null for an unknown one', () {
    expect(BrowserAgentActions.byId('open')?.labelEn, 'Open URL');
    expect(BrowserAgentActions.byId('not_a_real_action'), isNull);
  });

  test('browserActivityLabel uses the action label with no detail', () {
    expect(
      browserActivityLabel(const BrowserActivity(action: 'observe'), ru: false),
      'Observe page',
    );
    expect(
      browserActivityLabel(const BrowserActivity(action: 'observe'), ru: true),
      'Осмотреть страницу',
    );
  });

  test('browserActivityLabel appends the detail when present', () {
    expect(
      browserActivityLabel(
        const BrowserActivity(action: 'open', detail: 'https://example.com'),
        ru: false,
      ),
      'Open URL: https://example.com',
    );
  });

  test('browserActivityLabel ignores an empty detail string', () {
    expect(
      browserActivityLabel(
        const BrowserActivity(action: 'click', detail: ''),
        ru: false,
      ),
      'Click',
    );
  });

  test(
    'browserActivityLabel falls back to the raw action id when unrecognized',
    () {
      expect(
        browserActivityLabel(
          const BrowserActivity(action: 'mystery_action'),
          ru: false,
        ),
        'mystery_action',
      );
    },
  );
}
