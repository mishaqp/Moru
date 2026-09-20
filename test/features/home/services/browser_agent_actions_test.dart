import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_agent_actions.dart';
import 'package:flutter_test/flutter_test.dart';

final _startedAt = DateTime(2024, 1, 1);

void main() {
  test('byId finds a known action and returns null for an unknown one', () {
    expect(BrowserAgentActions.byId('open')?.labelEn, 'Open URL');
    expect(BrowserAgentActions.byId('not_a_real_action'), isNull);
  });

  test('browserActivityLabel uses the action label with no detail', () {
    expect(
      browserActivityLabel(
        BrowserActivity(id: 'a1', action: 'observe', startedAt: _startedAt),
        ru: false,
      ),
      'Observe page',
    );
    expect(
      browserActivityLabel(
        BrowserActivity(id: 'a1', action: 'observe', startedAt: _startedAt),
        ru: true,
      ),
      'Осмотреть страницу',
    );
  });

  test('browserActivityLabel appends the detail when present', () {
    expect(
      browserActivityLabel(
        BrowserActivity(
          id: 'a1',
          action: 'open',
          detail: 'https://example.com',
          startedAt: _startedAt,
        ),
        ru: false,
      ),
      'Open URL: https://example.com',
    );
  });

  test('browserActivityLabel ignores an empty detail string', () {
    expect(
      browserActivityLabel(
        BrowserActivity(
          id: 'a1',
          action: 'click',
          detail: '',
          startedAt: _startedAt,
        ),
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
          BrowserActivity(
            id: 'a1',
            action: 'mystery_action',
            startedAt: _startedAt,
          ),
          ru: false,
        ),
        'mystery_action',
      );
    },
  );

  test('browserActivityLabel marks a failed call distinctly', () {
    expect(
      browserActivityLabel(
        BrowserActivity(
          id: 'a1',
          action: 'click',
          startedAt: _startedAt,
          outcome: BrowserActivityOutcome.failed,
        ),
        ru: false,
      ),
      'Click — failed',
    );
    expect(
      browserActivityLabel(
        BrowserActivity(
          id: 'a1',
          action: 'click',
          startedAt: _startedAt,
          outcome: BrowserActivityOutcome.failed,
        ),
        ru: true,
      ),
      'Нажать — не удалось',
    );
  });

  test('browserActivityLabel marks wait_for that found nothing as notFound, '
      'distinct from failed', () {
    expect(
      browserActivityLabel(
        BrowserActivity(
          id: 'a1',
          action: 'wait_for',
          detail: '.button',
          startedAt: _startedAt,
          outcome: BrowserActivityOutcome.notFound,
        ),
        ru: false,
      ),
      'Wait for something to appear on the page: .button — not found',
    );
    expect(
      browserActivityLabel(
        BrowserActivity(
          id: 'a1',
          action: 'wait_for',
          detail: '.button',
          startedAt: _startedAt,
          outcome: BrowserActivityOutcome.notFound,
        ),
        ru: true,
      ),
      'Дождаться элемента на странице: .button — не найдено',
    );
  });

  test('eval_js has plain-language wording, not technical jargon', () {
    final action = BrowserAgentActions.byId('eval_js')!;
    expect(action.labelEn, 'Run code on the page');
    expect(action.labelRu, 'Выполнить код на странице');
    expect(action.descriptionEn, contains('read or change anything'));
  });
}
