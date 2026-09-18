import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/browser/query_focused_extractor.dart';

/// Builds a paragraph long enough to survive the chunker's minimum size, carrying a marker
/// word the ranking can match on.
String paragraph(String marker, {int words = 120}) {
  final buffer = StringBuffer('$marker. ');
  for (var i = 0; i < words; i++) {
    buffer.write('filler$i ');
  }
  return buffer.toString().trim();
}

void main() {
  group('tokenize', () {
    test('splits latin words and numbers', () {
      expect(
        QueryFocusedExtractor.tokenize('Hello, World! 42').join(','),
        'hello,world,42',
      );
    });

    test('keeps cyrillic', () {
      expect(
        QueryFocusedExtractor.tokenize('Привет мир').join(','),
        'привет,мир',
      );
    });

    test('empty input is empty', () {
      expect(QueryFocusedExtractor.tokenize(''), isEmpty);
    });
  });

  group('focus ranking', () {
    final doc = [
      paragraph('ALPHA', words: 200),
      paragraph('BETA', words: 200),
      paragraph('GAMMA', words: 200),
    ].join('\n\n');

    test('selects the passage carrying the query term', () {
      final result = QueryFocusedExtractor.focus(doc, 'beta');
      expect(result.text, contains('BETA'));
      expect(result.text, isNot(contains('ALPHA')));
      expect(result.chunksSelected, 1);
    });

    test('reports document diagnostics', () {
      final result = QueryFocusedExtractor.focus(doc, 'beta');
      expect(result.chunksTotal, greaterThanOrEqualTo(3));
      expect(result.originalChars, doc.length);
      expect(result.returnedChars, lessThan(result.originalChars));
      expect(result.focused, isTrue);
      expect(result.fallbackUsed, isFalse);
    });

    test('falls back to the leading passages when nothing matches', () {
      final result = QueryFocusedExtractor.focus(doc, 'zzzznotthere');
      expect(result.fallbackUsed, isTrue);
      expect(result.text, contains('ALPHA'));
      expect(result.chunksSelected, lessThanOrEqualTo(4));
    });

    test('never exceeds the character budget', () {
      expect(
        QueryFocusedExtractor.focus(
          doc,
          'alpha beta gamma',
          charBudget: 300,
        ).returnedChars,
        lessThanOrEqualTo(300),
      );
      expect(
        QueryFocusedExtractor.focus(
          doc,
          'alpha beta gamma',
          charBudget: 50,
        ).returnedChars,
        lessThanOrEqualTo(50),
      );
    });

    test('empty text and blank query are safe', () {
      expect(QueryFocusedExtractor.focus('', 'x').text, isEmpty);
      expect(
        QueryFocusedExtractor.focus('some text here', '   ').focused,
        isFalse,
      );
    });

    test('drops near-duplicate passages', () {
      final repeated = [
        paragraph('SAME-SECTION', words: 150),
        paragraph('SAME-SECTION', words: 150),
        paragraph('OTHER-SECTION', words: 150),
      ].join('\n\n');
      final occurrences = 'SAME-SECTION'
          .allMatches(QueryFocusedExtractor.focus(repeated, 'section').text)
          .length;
      expect(occurrences, lessThanOrEqualTo(1));
    });

    test('is deterministic', () {
      expect(
        QueryFocusedExtractor.focus(doc, 'gamma').text,
        QueryFocusedExtractor.focus(doc, 'gamma').text,
      );
    });
  });
}
