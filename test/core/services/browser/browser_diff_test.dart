import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/browser/browser_diff.dart';

void main() {
  group('BrowserDiffHelper', () {
    test('identical text reports unchanged', () {
      expect(
        BrowserDiffHelper.computeDiff('a\nb', 'a\nb')['unchanged'],
        isTrue,
      );
    });

    test('reports added and removed lines', () {
      final diff = BrowserDiffHelper.computeDiff(
        'head\nold line\nfoot',
        'head\nnew line\nfoot',
      );
      expect(diff['added'], 'new line');
      expect(diff['removed'], 'old line');
      expect(diff['truncated'], isFalse);
    });

    test('caps each side and flags truncation', () {
      final diff = BrowserDiffHelper.computeDiff('', 'x' * 5000);
      expect(
        (diff['added'] as String).length,
        BrowserDiffHelper.maxCharsPerSide,
      );
      expect(diff['truncated'], isTrue);
    });

    test('whitespace-only movement counts as unchanged', () {
      expect(
        BrowserDiffHelper.computeDiff('a\n\n b', 'a\n b\n')['unchanged'],
        isTrue,
      );
    });
  });
}
