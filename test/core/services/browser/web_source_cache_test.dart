import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/browser/web_source.dart';

/// Fixed "now" the cache tests run at, so a stored timestamp is never accidentally decades old
/// relative to the real clock.
const int _now = 1000;

WebSource source(
  String id,
  String text, {
  int storedAtMillis = _now,
  WebSourceOrigin origin = WebSourceOrigin.browser,
}) => WebSource(
  sourceId: id,
  url: 'https://example.com/$id',
  mode: WebSourceMode.text,
  text: text,
  storedAtMillis: storedAtMillis,
  origin: origin,
);

/// Cache whose clock the test drives, so TTL behaviour is deterministic.
BoundedWebSourceCache cacheAt(
  int Function() clock, {
  int maxEntries = 3,
  int maxBytes = 4096,
  int ttlMillis = 1000,
}) => BoundedWebSourceCache(
  maxEntries: maxEntries,
  maxBytes: maxBytes,
  ttlMillis: ttlMillis,
  clock: clock,
);

void main() {
  group('WebSourceId', () {
    test('has the documented shape', () {
      final id = WebSourceId.newId();
      expect(id.length, 36);
      expect(id.startsWith('src_'), isTrue);
      expect(WebSourceId.isWellFormed(id), isTrue);
    });

    test('is random, not url derived and never repeats', () {
      expect(WebSourceId.newId(), isNot(WebSourceId.newId()));
      expect(WebSourceId.isWellFormed('src_XYZ'), isFalse);
      expect(WebSourceId.isWellFormed('nope'), isFalse);
    });

    test('deterministic generator is stable and advancing', () {
      final sequence = WebSourceId.deterministic(42);
      final first = sequence();
      expect(sequence(), isNot(first));
      expect(WebSourceId.deterministic(42)(), first);
      expect(WebSourceId.isWellFormed(first), isTrue);
    });
  });

  group('BoundedWebSourceCache entries', () {
    test('evicts the least recently used entry', () {
      final cache = cacheAt(() => _now);
      cache.put(source('a', 'alpha'));
      cache.put(source('b', 'bravo'));
      cache.put(source('c', 'charlie'));
      expect(cache.size(), 3);

      cache.put(source('d', 'delta'));
      expect(cache.get('a'), isNull);
      expect(cache.get('d'), isNotNull);

      // Touching 'b' keeps it ahead of 'c' in recency.
      cache.get('b');
      cache.put(source('e', 'echo'));
      expect(cache.get('b'), isNotNull);
      expect(cache.get('c'), isNull);
    });

    test('expires entries after the ttl', () {
      var now = _now;
      final cache = cacheAt(() => now);
      cache.put(source('a', 'alpha'));
      expect(cache.get('a'), isNotNull);

      now = _now + 3000;
      expect(cache.get('a'), isNull);
      expect(cache.size(), 0);
    });

    test('refuses an entry larger than the budget', () {
      final cache = cacheAt(() => _now, maxEntries: 8, maxBytes: 64);
      expect(cache.put(source('big', 'x' * 500)), isFalse);
      expect(cache.size(), 0);
    });

    test('enforces the byte budget by dropping the oldest', () {
      final cache = cacheAt(() => _now, maxEntries: 8, maxBytes: 400);
      cache.put(source('one', 'y' * 200));
      cache.put(source('two', 'z' * 200));
      cache.put(source('three', 'w' * 200));
      expect(cache.bytes(), lessThanOrEqualTo(400));
      expect(cache.get('one'), isNull);
      expect(cache.get('three'), isNotNull);
    });

    test('clear empties everything', () {
      final cache = cacheAt(() => _now);
      cache.put(source('a', 'alpha'));
      cache.clear();
      expect(cache.size(), 0);
      expect(cache.bytes(), 0);
    });

    test('the shared process cache is boundedly sized', () {
      expect(browserSourceCache.maxEntries, 24);
      expect(browserSourceCache.maxBytes, 4 * 1024 * 1024);
      expect(browserSourceCache.ttlMillis, 45 * 60 * 1000);
    });
  });
}
