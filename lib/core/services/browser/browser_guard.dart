import 'dart:math' as math;

/// A page that asks a human to prove it is one, or refuses the browser.
class BrowserChallenge {
  const BrowserChallenge({required this.kind, required this.blocking});

  /// `cloudflare`, `search_engine`, `captcha`, `rate_limited` or
  /// `access_denied`.
  final String kind;

  /// The whole page is the check (an interstitial): clicking or typing
  /// through it would only get the browser flagged. A captcha widget inside
  /// an otherwise normal page (a login form) does not block.
  final bool blocking;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'blocking': blocking,
    'next': switch (kind) {
      'rate_limited' => 'Wait a minute before trying again, and do less.',
      'access_denied' =>
        'The site refuses automated access. Stop retrying and tell the user.',
      _ =>
        'Ask the user to complete the check in the browser themselves, then '
            'observe again. Do not try to solve it.',
    },
  };

  @override
  bool operator ==(Object other) =>
      other is BrowserChallenge &&
      other.kind == kind &&
      other.blocking == blocking;

  @override
  int get hashCode => Object.hash(kind, blocking);
}

/// Anti-bot behaviour of the shared browser, kept apart from the WebView so
/// it can be tested: recognising challenge pages and pacing actions.
class BrowserGuard {
  const BrowserGuard._();

  static final List<RegExp> _searchHosts = [
    RegExp(r'(^|\.)google\.[a-z.]+$'),
    RegExp(r'(^|\.)bing\.com$'),
    RegExp(r'(^|\.)duckduckgo\.com$'),
    RegExp(r'(^|\.)yahoo\.[a-z.]+$'),
    RegExp(r'(^|\.)yandex\.[a-z.]+$'),
    RegExp(r'(^|\.)ya\.ru$'),
    RegExp(r'(^|\.)baidu\.com$'),
    RegExp(r'(^|\.)ecosia\.org$'),
    RegExp(r'(^|\.)search\.brave\.com$'),
  ];

  static String? host(String? url) {
    final parsed = url == null ? null : Uri.tryParse(url.trim());
    final host = parsed?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static bool isSearchHost(String? url) {
    final name = host(url);
    return name != null && _searchHosts.any((p) => p.hasMatch(name));
  }

  /// Classifies what [challengeScript] found on the page, or the page's HTTP
  /// [status]. Page signals are specific markup, not words anywhere in the
  /// text, so an article about captchas is not taken for one.
  static BrowserChallenge? classify({
    int? status,
    String? url,
    Map<String, dynamic>? signals,
  }) {
    final s = signals ?? const <String, dynamic>{};
    if (s['cloudflare'] == true) {
      return const BrowserChallenge(kind: 'cloudflare', blocking: true);
    }
    if (s['unusual_traffic'] == true && isSearchHost(url)) {
      return const BrowserChallenge(kind: 'search_engine', blocking: true);
    }
    if ((s['captcha_frames'] as num? ?? 0) > 0) {
      // A page that is little besides the captcha is the check itself.
      final short = (s['text_length'] as num? ?? 0) < 600;
      return BrowserChallenge(kind: 'captcha', blocking: short);
    }
    return switch (status) {
      429 => const BrowserChallenge(kind: 'rate_limited', blocking: true),
      403 => const BrowserChallenge(kind: 'access_denied', blocking: true),
      _ => null,
    };
  }

  /// Actions that interact with the page and wait while a blocking check is
  /// shown: pressing on a verification page gets the browser flagged.
  static const Set<String> blockedByChallenge = {
    'click',
    'type',
    'submit',
    'press_key',
    'hover',
    'eval_js',
  };

  /// How long to wait before [action] on [url], given the last action on
  /// the same site [sinceLast] ago: sites (search engines most of all) ban
  /// browsers that act faster than a person. [jitter] (0..1) spreads the
  /// pauses so they are not regular.
  static Duration throttle(
    String action,
    String? url, {
    Duration? sinceLast,
    double jitter = 0,
  }) {
    final base = switch (action) {
      'open' => 550,
      'click' => 180,
      'type' => 260,
      'submit' => 260,
      'press_key' => 140,
      _ => 0,
    };
    if (base == 0) return Duration.zero;
    final bonus = !isSearchHost(url)
        ? 0
        : switch (action) {
            'open' => 900,
            'click' => 220,
            'type' || 'submit' => 260,
            'press_key' => 120,
            _ => 0,
          };
    final wanted = base + bonus;
    final elapsed = sinceLast?.inMilliseconds ?? wanted;
    final deficit = math.max(0, wanted - elapsed);
    // A first action on a site waits only the jitter.
    final spread = (math.min(250, wanted ~/ 3) * jitter.clamp(0.0, 1.0))
        .round();
    return Duration(milliseconds: deficit + spread);
  }

  /// Returns the page signals [classify] reads, as JSON.
  static const String challengeScript = r'''
(() => {
  const title = String(document.title || '').toLowerCase();
  const text = document.body ? String(document.body.innerText || '') : '';
  const lower = text.slice(0, 4000).toLowerCase();
  const cloudflare = Boolean(
    document.querySelector('#challenge-form, #cf-challenge-running, .cf-browser-verification, #challenge-stage') ||
    title.includes('just a moment') ||
    title.includes('attention required! | cloudflare')
  );
  let frames = 0;
  for (const frame of document.querySelectorAll('iframe')) {
    const src = String(frame.getAttribute('src') || '');
    if (!/recaptcha\/api2\/anchor|recaptcha\/enterprise\/anchor|hcaptcha\.com\/captcha|challenges\.cloudflare\.com/.test(src)) continue;
    const rect = frame.getBoundingClientRect();
    if (rect.width >= 60 && rect.height >= 40) frames++;
  }
  const unusual = lower.includes('unusual traffic') ||
      lower.includes('automated queries') ||
      lower.includes('are not a robot') ||
      lower.includes('не робот');
  return JSON.stringify({
    cloudflare,
    captcha_frames: frames,
    unusual_traffic: unusual,
    text_length: text.length
  });
})();
''';
}

/// A JavaScript dialog the page opened while the model drove the browser,
/// answered for it so the page does not hang.
class BrowserDialogRecord {
  const BrowserDialogRecord({
    required this.kind,
    required this.message,
    required this.answer,
  });

  /// `alert`, `confirm` or `prompt`.
  final String kind;
  final String message;

  /// What the page got back: `ok`, `accepted`, or the prompt's text.
  final String answer;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'message': message.length > 300 ? '${message.substring(0, 300)}…' : message,
    'answer': answer,
  };
}
