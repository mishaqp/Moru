import 'dart:async';

import 'query_focused_extractor.dart';
import 'web_source.dart';

/// Hard cap on the text one browser research snapshot will hold.
///
/// Read tool answers are clamped at 64 KB, but a research source is different: ranking has to
/// see the whole rendered page, or a passage the first window cut off can never be found.
/// 128 KiB doubles the answer ceiling and stays finite: both the visible text and the research
/// corpus are bounded before they cross the JS bridge, and 24 maximum-size snapshots come to
/// 3 MiB, inside the shared cache's own 4 MiB budget.
const int browserResearchMaxChars = 128 * 1024;

/// Wire marker distinguishing a rendered snapshot from an HTTP fetch in a tool envelope.
const String sourceKindBrowser = 'browser';

/// The extract_mode value a Readability read reports.
const String modeReadability = 'readability';

/// Default / bounds for the read answer window.
const int browserReadDefaultMaxChars = 8000;
const int browserReadMinChars = 100;
const int browserReadMaxChars = 64 * 1024;

/// The extract_mode values a browser read accepts.
const Set<String> browserReadModes = {'auto', 'readability', 'raw'};

/// Whether a read covered the whole rendered page or one explicitly scoped subtree.
enum RenderedScope { fullPage, selector }

/// What a browser read produced.
///
/// [text] is the legacy rendered answer. [researchText], when present, is a separately extracted
/// corpus for ranking and source reuse. Keeping them separate matters on mobile pages whose
/// article sections are collapsed with CSS: the visible-text read must still describe what is
/// rendered, while research must be able to reach prose already present in the DOM.
///
/// [researchText] wins for ranking and reuse whenever it is present, whatever its length: it is
/// the only string this layer can vouch for as page prose, so it never competes with [text] on
/// size.
class RenderedPage {
  const RenderedPage({
    this.url,
    this.title,
    required this.text,
    required this.extractMode,
    required this.scope,
    this.readTruncated = false,
    this.researchText,
    this.researchTruncated = false,
    this.researchUnavailable = false,
  });

  final String? url;
  final String? title;
  final String text;
  final String extractMode;
  final RenderedScope scope;
  final bool readTruncated;
  final String? researchText;
  final bool researchTruncated;

  /// True when a semantic pass ran on this page and produced nothing usable.
  ///
  /// The legacy [text] is then explicitly **not** a research source. A visible-text read walks
  /// the rendered tree, so on a page whose rendered text is the shorter one it could hand
  /// ranking and the cache content the engine never rendered (hidden UI, canvas fallbacks).
  /// A reader that never ran a semantic pass leaves this false and [text] remains the corpus.
  final bool researchUnavailable;
}

/// Outcome of reading the live page.
sealed class RenderedRead {
  const RenderedRead();
}

class RenderedReadOk extends RenderedRead {
  const RenderedReadOk(this.page);

  final RenderedPage page;
}

/// The page was reachable but the read failed inside it (bad selector, no article, JS error).
class RenderedReadFailure extends RenderedRead {
  const RenderedReadFailure(this.code, {this.detail, this.recovery});

  final String code;
  final String? detail;
  final String? recovery;
}

/// No browser is bound. The caller must report this, never open one on its own.
class RenderedReadNotOpen extends RenderedRead {
  const RenderedReadNotOpen();
}

/// What the tool asked the page for.
class ReadRequest {
  const ReadRequest({this.selector, this.mode = 'auto'});

  final String? selector;
  final String mode;
}

/// Reads the currently rendered page. The production implementation drives the live WebView;
/// the seam exists so ranking and caching can be tested without a device, and so a test can
/// prove that reuse never reads the page a second time.
typedef RenderedPageReader = Future<RenderedRead> Function(ReadRequest request);

/// Last line of defence for what a browser snapshot may contain.
///
/// The page JS extracts text nodes only and removes executable, form and explicitly hidden
/// subtrees before a semantic corpus crosses the bridge. This pass remains the last line of
/// defence: it strips script and style bodies, hidden containers, form controls and their
/// values (an attribute such as `value="..."` disappears with its tag), comments, and any
/// residual markup should a page - or a future JS change - hand us HTML instead of prose.
///
/// It runs on bounded text and each step is a single linear scan.
class BrowserTextSanitizer {
  const BrowserTextSanitizer._();

  /// Void elements whose attributes (a password or hidden `value`) must never survive.
  static final RegExp _dropVoid = RegExp(
    r'<(input|embed|object|param|source|track|base|link|meta)\b[^>]*>',
    caseSensitive: false,
    dotAll: true,
  );

  /// Any remaining tag, so raw markup cannot be stored even if a page hands us some.
  static final RegExp _tag = RegExp(r'<[!a-zA-Z/][^>]{0,1024}>');

  /// Comments, including the conditional-comment shapes older pages still ship.
  static final RegExp _comment = RegExp(r'<!--.*?-->', dotAll: true);

  /// Runs of horizontal whitespace (NBSP and the zero-width family included).
  static final RegExp _hSpace = RegExp(
    '[\u0009\u0020\u00A0\u2000-\u200D\uFEFF]+',
  );

  /// Spaces left dangling before a newline by tag removal.
  static final RegExp _spaceBeforeNewline = RegExp(' +\n');

  /// More than one blank line between paragraphs.
  static final RegExp _blankRun = RegExp(r'\n{3,}');

  /// Elements whose *content* is not page text.
  static final RegExp _dropOpen = RegExp(
    r'<(script|style|noscript|template|iframe|svg|canvas)\b[^>]*>',
    caseSensitive: false,
  );

  /// Containers explicitly marked as not displayed.
  static final RegExp _hiddenOpen = RegExp(
    r"""<([a-zA-Z][\w:-]*)([^>]*(?:\bhidden\b|aria-hidden\s*=\s*["']?true))[^>]*>""",
    caseSensitive: false,
  );

  static String sanitize(String raw) {
    if (raw.isEmpty) return '';

    var out = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    out = out.replaceAll(_comment, ' ');
    out = _dropBlocks(out, _dropOpen, missingCloseSwallowsRest: true);
    // An unclosed hidden container drops only its opening tag: guessing where it ends would
    // throw away the rest of the page.
    out = _dropBlocks(out, _hiddenOpen, missingCloseSwallowsRest: false);
    out = out.replaceAll(_dropVoid, ' ');
    out = out.replaceAll(_tag, ' ');
    // Nothing tag-shaped survives the pass above; these two characters are the last way raw
    // markup could reach the cache, so they go too.
    out = out.replaceAll('<', ' ').replaceAll('>', ' ');
    out = out.replaceAll(_hSpace, ' ');
    out = out.replaceAll(_spaceBeforeNewline, '\n');
    out = out.replaceAll(_blankRun, '\n\n');
    return out.trim();
  }

  /// Remove every `open ... close` element, walking the string once and counting nesting so a
  /// container's real close tag is found rather than the next one of the same name.
  static String _dropBlocks(
    String input,
    RegExp open, {
    required bool missingCloseSwallowsRest,
  }) {
    final builder = StringBuffer();
    var cursor = 0;
    while (cursor < input.length) {
      final match = open.firstMatch(input.substring(cursor));
      if (match == null) break;
      builder.write(input.substring(cursor, cursor + match.start));
      final name = match.group(1)!.toLowerCase();
      final afterOpen = cursor + match.end;
      final afterClose = _findMatchingClose(input, name, afterOpen);
      if (afterClose == null) {
        if (missingCloseSwallowsRest) return builder.toString();
        cursor = afterOpen;
        continue;
      }
      cursor = afterClose;
    }
    builder.write(input.substring(cursor.clamp(0, input.length)));
    return builder.toString();
  }

  /// Index just past the close tag matching the opener that ends at [from], or null.
  static int? _findMatchingClose(String input, String name, int from) {
    final pattern = RegExp('</?$name(?=[\\s/>])', caseSensitive: false);
    var depth = 1;
    var index = from;
    while (index < input.length) {
      final match = pattern.firstMatch(input.substring(index));
      if (match == null) return null;
      final absoluteStart = index + match.start;
      final isClose = input[absoluteStart + 1] == '/';
      final gt = input.indexOf('>', index + match.end);
      if (gt < 0) return null;
      final after = gt + 1;
      if (isClose) {
        depth--;
        if (depth == 0) return after;
      } else if (input[after - 2] != '/') {
        depth++;
      }
      index = after;
    }
    return null;
  }
}

/// Reproduce the whitespace collapse the raw read has always applied to its answer.
String collapseRenderedWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Store a rendered page in the shared source cache.
///
/// Only sanitised research text and non-sensitive metadata go in: a browser may sit on an
/// authenticated page, so cookies, storage, DOM, form values and credentials stay in the
/// WebView. Returns the new handle, or null when there is nothing worth keeping (empty text)
/// or the read was scoped to a selector - a subtree is not the page and must not masquerade as
/// one.
String? storeBrowserSource(
  RenderedPage page,
  String text,
  bool corpusTruncated, {
  int? nowMillis,
  bool Function(WebSource source)? store,
}) {
  if (page.scope != RenderedScope.fullPage) return null;
  final body = text.trim();
  if (body.isEmpty) return null;

  final source = WebSource(
    sourceId: WebSourceId.newId(),
    url: page.url ?? '',
    status: null,
    mode: page.extractMode == modeReadability
        ? WebSourceMode.article
        : WebSourceMode.text,
    title: page.title,
    text: body,
    bodyTruncated: corpusTruncated,
    storedAtMillis: nowMillis ?? DateTime.now().millisecondsSinceEpoch,
    origin: WebSourceOrigin.browser,
  );
  final accepted = store?.call(source) ?? browserSourceCache.put(source);
  return accepted ? source.sourceId : null;
}

/// Envelope for a browser read.
///
///  * no [focus]: the legacy envelope (`text` / `truncated` / `extract_mode`), plus `url`,
///    `title` and a `source_id` when the read covered the whole page.
///  * [focus]: the whole rendered corpus goes through [QueryFocusedExtractor] and the answer
///    carries the stage diagnostics, so a rendered page and a fetched page are ranked by one
///    implementation.
Map<String, dynamic> browserTextEnvelope({
  required RenderedPage page,
  required int maxChars,
  String? focus,
  String? requestedSelector,
  bool? readTruncated,
  int? nowMillis,
  bool Function(WebSource source)? store,
}) {
  if (focus != null && requestedSelector != null) {
    return focusSelectorConflictEnvelope();
  }

  final truncatedFlag = readTruncated ?? page.readTruncated;

  // The corpus this layer is willing to vouch for. A page the reader marked unavailable has
  // none by construction - its legacy text may be longer, and that is exactly what we refuse.
  final researchText = page.researchText;
  final hasResearch = researchText != null && researchText.trim().isNotEmpty;
  final semanticText = hasResearch ? researchText : page.text;
  final corpusTruncated = hasResearch ? page.researchTruncated : truncatedFlag;
  final rawCorpus = page.researchUnavailable
      ? null
      : BrowserTextSanitizer.sanitize(semanticText);
  final researchCorpus = (rawCorpus != null && rawCorpus.trim().isNotEmpty)
      ? rawCorpus
      : null;

  final sourceId = researchCorpus == null
      ? null
      : storeBrowserSource(
          page,
          researchCorpus,
          corpusTruncated,
          nowMillis: nowMillis,
          store: store,
        );

  if (focus != null) {
    final corpus = researchCorpus;
    if (corpus == null) return researchCorpusUnavailableEnvelope();
    final budget = maxChars < QueryFocusedExtractor.focusCharBudget
        ? maxChars
        : QueryFocusedExtractor.focusCharBudget;
    final focused = QueryFocusedExtractor.focus(
      corpus,
      focus,
      charBudget: budget,
    );
    return <String, dynamic>{
      'focused': true,
      'focus': focus,
      if (page.url != null) 'url': page.url,
      if (page.title != null) 'title': page.title,
      'text': focused.text,
      'chunks_total': focused.chunksTotal,
      'chunks_selected': focused.chunksSelected,
      'original_chars': focused.originalChars,
      'returned_chars': focused.returnedChars,
      'selection_truncated': focused.returnedChars < focused.originalChars,
      if (focused.fallbackUsed) 'focus_fallback': true,
      // A ranked selection is not a window: "truncated" reports the bounded source corpus.
      'truncated': corpusTruncated,
      'extract_mode': page.extractMode,
      if (sourceId != null) ...{
        'source_id': sourceId,
        'source_kind': sourceKindBrowser,
      },
    };
  }

  final responseText = collapseRenderedWhitespace(page.text);
  final clipped = responseText.length <= maxChars
      ? responseText
      : responseText.substring(0, maxChars);
  return <String, dynamic>{
    'text': clipped,
    'truncated': truncatedFlag || clipped.length < responseText.length,
    'extract_mode': page.extractMode,
    if (page.scope == RenderedScope.fullPage) ...{
      if (page.url != null) 'url': page.url,
      if (page.title != null) 'title': page.title,
      if (sourceId != null) ...{
        'source_id': sourceId,
        'source_kind': sourceKindBrowser,
      },
    },
  };
}

/// `focus` ranks the whole page, so it cannot be combined with a selector-scoped read.
Map<String, dynamic> focusSelectorConflictEnvelope() => <String, dynamic>{
  'error': 'focus_selector_conflict',
  'detail':
      'focus ranks the whole rendered page, so it cannot be combined with a selector-scoped read.',
  'recovery':
      'Drop selector to rank the page, or drop focus and keep the selector for a targeted read.',
};

/// `focus` with no corpus it can trust.
///
/// The semantic pass ran and produced nothing usable, so the only text available is the legacy
/// answer - which may contain content the engine never rendered. Rather than ranking that, or
/// writing it to the shared cache as a trusted `source_id`, the read is refused explicitly.
Map<String, dynamic> researchCorpusUnavailableEnvelope() => <String, dynamic>{
  'error': 'research_corpus_unavailable',
  'detail':
      'The page did not yield a safe semantic research corpus, so focus cannot rank it.',
  'recovery':
      'Read the page without focus, or scope the read with a selector, then retry focus on a page whose prose is in the DOM.',
};

/// The entire browser text path, minus the WebView: argument handling, reader dispatch, the
/// tool timeout and the envelope. It lives here, free of Flutter types, so the behaviour can be
/// tested without a device; the tool is a thin wrapper that supplies the WebView-backed reader
/// and the not-open envelope.
Future<Map<String, dynamic>> runBrowserRead({
  required Object? args,
  required RenderedPageReader reader,
  required int timeoutMs,
  int defaultMaxChars = browserReadDefaultMaxChars,
  required Map<String, dynamic> Function() notOpen,
  int? nowMillis,
  bool Function(WebSource source)? store,
}) async {
  if (args is! Map) {
    return <String, dynamic>{
      'error': 'bad_request',
      'detail': 'browser read expects an object of arguments.',
    };
  }

  final rawSelector = args['selector'];
  final explicitSelector =
      rawSelector is String && rawSelector.trim().isNotEmpty
      ? rawSelector.trim()
      : null;

  final rawMax = args['max_chars'];
  final requestedMax = rawMax is num
      ? rawMax.toInt()
      : (rawMax is String
            ? int.tryParse(rawMax) ?? defaultMaxChars
            : defaultMaxChars);
  final maxChars = requestedMax.clamp(browserReadMinChars, browserReadMaxChars);

  final rawMode = args['extract_mode'];
  final modeCandidate = rawMode is String ? rawMode.toLowerCase() : null;
  final mode =
      (modeCandidate != null && browserReadModes.contains(modeCandidate))
      ? modeCandidate
      : 'auto';

  final rawFocus = args['focus'];
  final focus = rawFocus is String && rawFocus.trim().isNotEmpty
      ? rawFocus.trim()
      : null;

  if (focus != null && explicitSelector != null) {
    return focusSelectorConflictEnvelope();
  }

  final RenderedRead read;
  try {
    read = await reader(
      ReadRequest(selector: explicitSelector, mode: mode),
    ).timeout(Duration(milliseconds: timeoutMs));
  } on TimeoutException {
    return <String, dynamic>{
      'error': 'tool_timeout',
      'tool': 'browser read',
      'recovery':
          'The browser action exceeded its ${timeoutMs}ms budget. Retry, or simplify the selector.',
    };
  }

  switch (read) {
    case RenderedReadNotOpen():
      return notOpen();
    case RenderedReadFailure(:final code, :final detail, :final recovery):
      return <String, dynamic>{
        'error': code,
        if (detail != null) 'detail': detail,
        if (recovery != null) 'recovery': recovery,
      };
    case RenderedReadOk(:final page):
      return browserTextEnvelope(
        page: page,
        maxChars: maxChars,
        focus: focus,
        requestedSelector: explicitSelector,
        nowMillis: nowMillis,
        store: store,
      );
  }
}

/// Envelope for a `source_id` call answered out of the cache: no request, no second read.
Map<String, dynamic> cachedSourceEnvelope({
  required WebSource source,
  required int maxChars,
  String? focus,
  int? startIndex,
}) {
  if (focus != null && startIndex != null && startIndex > 0) {
    return <String, dynamic>{
      'error': 'focus_start_index_conflict',
      'source_id': source.sourceId,
      'detail':
          'focus ranks and selects the most relevant passages itself, so it cannot be combined with start_index.',
      'recovery':
          'Drop start_index when using focus, or drop focus and page through the text with start_index.',
    };
  }

  if (focus != null) {
    final budget = maxChars < QueryFocusedExtractor.focusCharBudget
        ? maxChars
        : QueryFocusedExtractor.focusCharBudget;
    final focused = QueryFocusedExtractor.focus(
      source.text,
      focus,
      charBudget: budget,
    );
    return <String, dynamic>{
      'cached': true,
      'source_id': source.sourceId,
      'source_kind': source.origin.wireName,
      'url': source.url,
      if (source.title != null) 'title': source.title,
      'extract_mode': source.mode.wireName,
      'focused': true,
      'focus': focus,
      'text': focused.text,
      'chunks_total': focused.chunksTotal,
      'chunks_selected': focused.chunksSelected,
      'original_chars': focused.originalChars,
      'returned_chars': focused.returnedChars,
      'selection_truncated': focused.returnedChars < focused.originalChars,
      if (focused.fallbackUsed) 'focus_fallback': true,
      'truncated': source.bodyTruncated,
    };
  }

  final offset = (startIndex != null && startIndex > 0) ? startIndex : 0;
  final end = (offset + maxChars) < source.text.length
      ? offset + maxChars
      : source.text.length;
  final window = offset >= source.text.length
      ? ''
      : source.text.substring(offset, end);
  final nextStart = end < source.text.length ? end : null;

  return <String, dynamic>{
    'cached': true,
    'source_id': source.sourceId,
    'source_kind': source.origin.wireName,
    'url': source.url,
    if (source.title != null) 'title': source.title,
    'extract_mode': source.mode.wireName,
    'text': window,
    'truncated': nextStart != null,
    if (nextStart != null) 'next_start_index': nextStart,
  };
}

/// The source_id is unknown, evicted or past its TTL.
Map<String, dynamic> unknownSourceEnvelope(
  String sourceId,
) => <String, dynamic>{
  'error': 'unknown_source_id',
  'source_id': sourceId,
  'detail':
      'No cached page with this source_id: it was never read, or it left the cache.',
  'recovery': 'Read the page again and reuse the new source_id.',
};
