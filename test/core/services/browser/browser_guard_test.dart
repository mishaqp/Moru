import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/browser/browser_guard.dart';

void main() {
  test('challenge pages are told apart from pages that mention them', () {
    expect(
      BrowserGuard.classify(signals: {'cloudflare': true}),
      const BrowserChallenge(kind: 'cloudflare', blocking: true),
    );
    expect(
      BrowserGuard.classify(
        url: 'https://www.google.com/sorry/index',
        signals: {'unusual_traffic': true},
      ),
      const BrowserChallenge(kind: 'search_engine', blocking: true),
    );
    // The same words on an ordinary site are an article, not a check.
    expect(
      BrowserGuard.classify(
        url: 'https://example.com/blog',
        signals: {'unusual_traffic': true, 'text_length': 9000},
      ),
      isNull,
    );
    // A captcha that is the whole page blocks; one in a login form not.
    expect(
      BrowserGuard.classify(signals: {'captcha_frames': 1, 'text_length': 80}),
      const BrowserChallenge(kind: 'captcha', blocking: true),
    );
    expect(
      BrowserGuard.classify(
        signals: {'captcha_frames': 1, 'text_length': 4000},
      ),
      const BrowserChallenge(kind: 'captcha', blocking: false),
    );
    expect(BrowserGuard.classify(status: 429)?.kind, 'rate_limited');
    expect(BrowserGuard.classify(status: 403)?.kind, 'access_denied');
    expect(BrowserGuard.classify(status: 404, signals: const {}), isNull);
    expect(
      const BrowserChallenge(kind: 'captcha', blocking: true).toJson()['next'],
      contains('Ask the user'),
    );
  });

  test('actions are paced per site, search engines slower', () {
    Duration pace(
      String action,
      String url, {
      int? sinceMs,
      double jitter = 0,
    }) => BrowserGuard.throttle(
      action,
      url,
      sinceLast: sinceMs == null ? null : Duration(milliseconds: sinceMs),
      jitter: jitter,
    );
    // The first action on a site does not wait.
    expect(pace('open', 'https://example.com'), Duration.zero);
    expect(
      pace('open', 'https://example.com', sinceMs: 100),
      const Duration(milliseconds: 450),
    );
    expect(
      pace('open', 'https://www.google.com/search?q=x', sinceMs: 100),
      const Duration(milliseconds: 1350),
    );
    expect(pace('click', 'https://yandex.ru', sinceMs: 1000), Duration.zero);
    // Reading never waits; jitter adds at most a third of the pause.
    expect(pace('observe', 'https://example.com', sinceMs: 0), Duration.zero);
    expect(
      pace('click', 'https://example.com', sinceMs: 180, jitter: 1),
      const Duration(milliseconds: 60),
    );
    expect(BrowserGuard.isSearchHost('https://duckduckgo.com/?q=a'), isTrue);
    expect(BrowserGuard.isSearchHost('https://mygoogle.example'), isFalse);
    expect(BrowserGuard.host('https://www.Example.com/a'), 'example.com');
  });

  test('answered dialogs are reported shortly', () {
    final record = BrowserDialogRecord(
      kind: 'confirm',
      message: 'x' * 400,
      answer: 'accepted',
    ).toJson();
    expect(record['kind'], 'confirm');
    expect((record['message'] as String).length, 301);
    expect(record['answer'], 'accepted');
  });
}
