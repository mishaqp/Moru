import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/browser/browser_research.dart';
import 'package:Kelivo/core/services/browser/web_source.dart';

const _page = RenderedPage(
  url: 'https://example.com/a',
  title: 'Example',
  text: 'VISIBLE-ONLY text that the reader rendered.',
  extractMode: 'readability',
  scope: RenderedScope.fullPage,
  researchText:
      'The Fermat proof passage lives here and is unique in the corpus.',
);

const _unavailable = RenderedPage(
  url: 'https://example.com/b',
  text: 'LEGACY text the engine may never have rendered',
  extractMode: 'raw_fallback',
  scope: RenderedScope.fullPage,
  researchUnavailable: true,
);

const _scoped = RenderedPage(
  url: 'https://example.com/c',
  text: 'SUB TREE',
  extractMode: 'raw',
  scope: RenderedScope.selector,
);

void main() {
  group('BrowserTextSanitizer', () {
    test('drops scripts, form values and comments but keeps prose', () {
      final clean = BrowserTextSanitizer.sanitize(
        '<div>Hello <script>evil()</script>world</div>'
        '<input type="password" value="hunter2">'
        '<!-- comment --><span>tail</span>',
      );
      expect(clean, isNot(contains('evil')));
      expect(clean, isNot(contains('hunter2')));
      expect(clean, isNot(contains('comment')));
      expect(clean, contains('Hello'));
      expect(clean, contains('world'));
      expect(clean, contains('tail'));
      expect(clean, isNot(contains('<')));
      expect(clean, isNot(contains('>')));
    });
  });

  group('read envelope', () {
    test('publishes a source handle for a whole-page read', () {
      final envelope = browserTextEnvelope(
        page: _page,
        maxChars: 8000,
        store: (_) => true,
      );
      expect(envelope['text'], isNotEmpty);
      expect(envelope['extract_mode'], 'readability');
      expect(envelope['url'], 'https://example.com/a');
      expect(envelope['source_kind'], 'browser');
      expect(envelope['source_id'], startsWith('src_'));
    });

    test('ranks the semantic corpus and reports diagnostics', () {
      final envelope = browserTextEnvelope(
        page: _page,
        maxChars: 8000,
        focus: 'Fermat proof',
        store: (_) => true,
      );
      expect(envelope['focused'], isTrue);
      expect(envelope['text'], contains('Fermat proof'));
      expect(envelope.containsKey('next_start_index'), isFalse);
      expect(envelope.containsKey('chunks_total'), isTrue);
      expect(envelope['selection_truncated'], isA<bool>());
    });

    test('refuses focus together with a selector', () {
      expect(
        browserTextEnvelope(
          page: _page,
          maxChars: 8000,
          focus: 'x',
          requestedSelector: 'main',
        )['error'],
        'focus_selector_conflict',
      );
    });

    test('refuses focus when no safe corpus exists', () {
      expect(
        browserTextEnvelope(
          page: _unavailable,
          maxChars: 8000,
          focus: 'x',
        )['error'],
        'research_corpus_unavailable',
      );
      final plain = browserTextEnvelope(page: _unavailable, maxChars: 8000);
      expect(plain.containsKey('source_id'), isFalse);
      expect(plain['text'], isNotNull);
    });

    test('never caches a selector-scoped read', () {
      final envelope = browserTextEnvelope(page: _scoped, maxChars: 8000);
      expect(envelope.containsKey('source_id'), isFalse);
      expect(envelope['text'], 'SUB TREE');
    });

    test('is json encodable', () {
      expect(
        jsonEncode(
          browserTextEnvelope(
            page: _page,
            maxChars: 8000,
            focus: 'Fermat',
            store: (_) => true,
          ),
        ),
        isNotEmpty,
      );
    });
  });

  group('cached source envelope', () {
    final source = WebSource(
      sourceId: WebSourceId.newId(),
      url: 'https://example.com/long',
      mode: WebSourceMode.text,
      title: 'Long',
      text: '${'A' * 3000} Fermat proof is here ${'B' * 3000}',
      origin: WebSourceOrigin.browser,
    );

    test('windows the cached text and offers the next offset', () {
      final first = cachedSourceEnvelope(source: source, maxChars: 500);
      expect(first['cached'], isTrue);
      expect((first['text'] as String).length, 500);
      expect(first['next_start_index'], 500);

      final second = cachedSourceEnvelope(
        source: source,
        maxChars: 500,
        startIndex: 500,
      );
      expect(second['next_start_index'], 1000);
    });

    test('finds a passage deep in the cached text without a network read', () {
      final focused = cachedSourceEnvelope(
        source: source,
        maxChars: 8000,
        focus: 'Fermat proof',
      );
      expect(focused['text'], contains('Fermat proof'));
      expect(focused['original_chars'], source.text.length);
    });

    test('rejects focus together with start_index', () {
      expect(
        cachedSourceEnvelope(
          source: source,
          maxChars: 500,
          focus: 'x',
          startIndex: 500,
        )['error'],
        'focus_start_index_conflict',
      );
    });

    test('unknown source id has a recovery hint', () {
      final envelope = unknownSourceEnvelope('src_dead');
      expect(envelope['error'], 'unknown_source_id');
      expect(envelope['recovery'], isNotNull);
    });
  });

  group('runBrowserRead', () {
    late List<ReadRequest> calls;
    final notOpen = <String, dynamic>{'error': 'browser_not_open'};

    setUp(() => calls = <ReadRequest>[]);

    Future<RenderedRead> reader(ReadRequest request) async {
      calls.add(request);
      return const RenderedReadOk(_page);
    }

    test('dispatches to the page and normalises the mode', () async {
      final envelope = await runBrowserRead(
        args: <String, dynamic>{'max_chars': 500, 'focus': 'Fermat'},
        reader: reader,
        timeoutMs: 5000,
        notOpen: () => notOpen,
      );
      expect(envelope['text'], isNotEmpty);
      expect(calls.single.mode, 'auto');
    });

    test('reports a timeout instead of hanging', () async {
      final envelope = await runBrowserRead(
        args: <String, dynamic>{},
        reader: (request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const RenderedReadOk(_page);
        },
        timeoutMs: 20,
        notOpen: () => notOpen,
      );
      expect(envelope['error'], 'tool_timeout');
    });

    test('rejects a non-object argument payload', () async {
      final envelope = await runBrowserRead(
        args: 'nonsense',
        reader: reader,
        timeoutMs: 5000,
        notOpen: () => notOpen,
      );
      expect(envelope['error'], 'bad_request');
    });

    test('rejects focus + selector before touching the page', () async {
      final envelope = await runBrowserRead(
        args: <String, dynamic>{'selector': 'main', 'focus': 'x'},
        reader: reader,
        timeoutMs: 5000,
        notOpen: () => notOpen,
      );
      expect(envelope['error'], 'focus_selector_conflict');
      expect(calls, isEmpty);
    });

    test('surfaces browser_not_open from the reader seam', () async {
      final envelope = await runBrowserRead(
        args: <String, dynamic>{},
        reader: (request) async => const RenderedReadNotOpen(),
        timeoutMs: 5000,
        notOpen: () => notOpen,
      );
      expect(envelope['error'], 'browser_not_open');
    });
  });
}
