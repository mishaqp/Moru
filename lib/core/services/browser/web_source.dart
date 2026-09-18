import 'dart:convert';
import 'dart:math';

/// Generator for the opaque handle a browser read hands back for a page it has read.
///
/// The identifier is *not* derived from the URL: it is fresh randomness, so it cannot be
/// reversed into an address, two reads of the same page get different handles, and the
/// hostname never appears in the value. 16 random bytes (128 bits) make an accidental
/// collision negligible.
///
/// Port of RikkaHub's `WebSourceId`.
class WebSourceId {
  const WebSourceId._();

  static const String prefix = 'src_';

  /// Random bytes behind one identifier.
  static const int randomBytes = 16;

  /// Total length of a well-formed identifier.
  static const int length = 4 + randomBytes * 2; // 'src_' + hex

  static const String _hex = '0123456789abcdef';

  static final Random _secure = Random.secure();

  /// A fresh identifier, unrelated to any URL.
  ///
  /// [random] exists as a seam for tests that need reproducible values; production callers
  /// never pass it.
  static String newId({Random? random}) {
    final source = random ?? _secure;
    final bytes = List<int>.generate(randomBytes, (_) => source.nextInt(256));
    final buffer = StringBuffer(prefix);
    for (final value in bytes) {
      buffer.write(_hex[(value >> 4) & 0x0F]);
      buffer.write(_hex[value & 0x0F]);
    }
    return buffer.toString();
  }

  /// True when [value] has the shape [newId] produces: the prefix plus lowercase hex.
  static bool isWellFormed(String value) {
    if (value.length != length) return false;
    if (!value.startsWith(prefix)) return false;
    for (final unit in value.substring(prefix.length).codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isLowerHex = unit >= 0x61 && unit <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }

  /// A deterministic generator for tests and tooling that need stable identifiers.
  static String Function() deterministic(int seed) {
    final random = Random(seed);
    return () => newId(random: random);
  }
}

/// Where a cached page came from. A browser snapshot is not an HTTP response, so the two must
/// be distinguishable in the envelope instead of a browser page pretending to have a status
/// code.
enum WebSourceOrigin {
  /// Fetched over HTTP by the fetch/MCP tooling.
  http('http'),

  /// Read out of the live rendered page by a browser tool.
  browser('browser');

  const WebSourceOrigin(this.wireName);

  final String wireName;
}

/// How a cached page's text was produced.
enum WebSourceMode {
  article('article'),
  text('text'),
  links('links'),
  metadata('metadata'),
  raw('raw');

  const WebSourceMode(this.wireName);

  final String wireName;
}

/// One cached page: the cleaned text plus the metadata derived from the same source.
///
/// This type intentionally has no field for request headers, response headers, cookies,
/// credentials or a POST body, so a cache entry physically cannot leak them. A browser
/// snapshot stores only rendered text - never DOM, script, style or form state.
class WebSource {
  const WebSource({
    required this.sourceId,
    required this.url,
    required this.mode,
    this.status,
    this.title,
    this.siteName,
    this.description,
    this.language,
    this.text = '',
    this.bodyTruncated = false,
    this.storedAtMillis = 0,
    this.origin = WebSourceOrigin.http,
  });

  final String sourceId;
  final String url;

  /// Null for a [WebSourceOrigin.browser] source: a rendered page has no HTTP status of its
  /// own, and inventing a 200 would make the envelope lie about where the text came from.
  final int? status;
  final WebSourceMode mode;
  final String? title;
  final String? siteName;
  final String? description;
  final String? language;
  final String text;
  final bool bodyTruncated;
  final int storedAtMillis;
  final WebSourceOrigin origin;
}

/// Bounded, expiring, in-memory store of cleaned pages, shared by the browser tools so a later
/// `source_id` call can answer without touching the page again.
///
/// Policy (all four are enforced together):
///  * at most [maxEntries] entries;
///  * at most [maxBytes] of stored text and metadata, measured in UTF-8 bytes;
///  * every entry expires [ttlMillis] after it was stored;
///  * eviction is least-recently-used, so re-reading a source keeps it alive.
///
/// Nothing is written to disk, so a snapshot of an authenticated page dies with the process.
class BoundedWebSourceCache {
  BoundedWebSourceCache({
    this.maxEntries = defaultMaxEntries,
    this.maxBytes = defaultMaxBytes,
    this.ttlMillis = defaultTtlMillis,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Sources kept at once. Small enough that a phone never notices the memory.
  static const int defaultMaxEntries = 24;

  /// Total budget for stored text and metadata.
  static const int defaultMaxBytes = 4 * 1024 * 1024;

  /// How long a source stays usable after it was read.
  static const int defaultTtlMillis = 45 * 60 * 1000;

  final int maxEntries;
  final int maxBytes;
  final int ttlMillis;
  final int Function() _clock;

  /// Insertion order; `_order` holds ids least- to most-recently used after every touch.
  final Map<String, WebSource> _entries = <String, WebSource>{};
  final Map<String, int> _sizes = <String, int>{};
  final List<String> _order = <String>[];
  int _bytes = 0;

  /// Store [source], evicting as needed. Returns false when the entry alone exceeds
  /// [maxBytes] - the caller keeps serving it, it just is not kept.
  bool put(WebSource source) {
    _purgeExpired();
    final size = _sizeOf(source);
    if (size > maxBytes) return false;

    final previous = _entries.remove(source.sourceId);
    if (previous != null) {
      _bytes -= _sizes.remove(source.sourceId) ?? 0;
      _order.remove(source.sourceId);
    }
    _entries[source.sourceId] = source;
    _sizes[source.sourceId] = size;
    _order.add(source.sourceId);
    _bytes += size;
    _trim();
    return true;
  }

  /// The live entry for [sourceId], refreshing its recency, or null when absent or expired.
  WebSource? get(String sourceId) {
    final entry = _entries[sourceId];
    if (entry == null) return null;
    if (_isExpired(entry)) {
      _entries.remove(sourceId);
      _bytes -= _sizes.remove(sourceId) ?? 0;
      _order.remove(sourceId);
      return null;
    }
    _order.remove(sourceId);
    _order.add(sourceId);
    return entry;
  }

  bool contains(String sourceId) => get(sourceId) != null;

  void remove(String sourceId) {
    if (_entries.remove(sourceId) != null) {
      _bytes -= _sizes.remove(sourceId) ?? 0;
      _order.remove(sourceId);
    }
  }

  void clear() {
    _entries.clear();
    _sizes.clear();
    _order.clear();
    _bytes = 0;
  }

  /// Live entry count, expired entries excluded.
  int size() {
    _purgeExpired();
    return _entries.length;
  }

  /// Bytes currently held, expired entries excluded.
  int bytes() {
    _purgeExpired();
    return _bytes;
  }

  void _trim() {
    while (_entries.length > maxEntries || _bytes > maxBytes) {
      if (_order.isEmpty) break;
      final eldest = _order.first;
      _order.removeAt(0);
      _entries.remove(eldest);
      _bytes -= _sizes.remove(eldest) ?? 0;
    }
  }

  void _purgeExpired() {
    if (_entries.isEmpty) return;
    final now = _clock();
    final dead = <String>[];
    for (final entry in _entries.entries) {
      if (_isExpired(entry.value, now)) dead.add(entry.key);
    }
    for (final id in dead) {
      _entries.remove(id);
      _bytes -= _sizes.remove(id) ?? 0;
      _order.remove(id);
    }
  }

  bool _isExpired(WebSource source, [int? now]) =>
      (now ?? _clock()) - source.storedAtMillis > ttlMillis;

  static int _sizeOf(WebSource source) =>
      _utf8Bytes(source.sourceId) +
      _utf8Bytes(source.url) +
      _utf8Bytes(source.text) +
      _utf8Bytes(source.title) +
      _utf8Bytes(source.siteName) +
      _utf8Bytes(source.description) +
      _utf8Bytes(source.language);

  static int _utf8Bytes(String? value) =>
      (value == null || value.isEmpty) ? 0 : utf8.encode(value).length;
}

/// The cache the browser tools share for the lifetime of the process, so an `observe`/`read`
/// can hand out a `source_id` that a later `extract` reuses without re-rendering the page.
final BoundedWebSourceCache browserSourceCache = BoundedWebSourceCache();
