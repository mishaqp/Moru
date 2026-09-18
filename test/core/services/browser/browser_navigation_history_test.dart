import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserNavigationHistory', () {
    test('back and forward follow committed agent pages', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/b')
        ..push('https://example.com/c');

      expect(history.current, 'https://example.com/c');
      expect(history.backTarget, 'https://example.com/b');
      expect(history.canGoBack, isTrue);
      expect(history.canGoForward, isFalse);

      history.commitBack();
      expect(history.current, 'https://example.com/b');
      expect(history.backTarget, 'https://example.com/a');
      expect(history.forwardTarget, 'https://example.com/c');

      history.commitBack();
      expect(history.current, 'https://example.com/a');
      expect(history.canGoBack, isFalse);
      expect(history.forwardTarget, 'https://example.com/b');

      history.commitForward();
      expect(history.current, 'https://example.com/b');
      history.commitForward();
      expect(history.current, 'https://example.com/c');
      expect(history.canGoForward, isFalse);
    });

    test('new navigation after back discards forward entries', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/b')
        ..push('https://example.com/c');

      history.commitBack();
      expect(history.current, 'https://example.com/b');
      expect(history.canGoForward, isTrue);

      history.push('https://example.com/d');

      expect(history.current, 'https://example.com/d');
      expect(history.canGoForward, isFalse);
      expect(history.backTarget, 'https://example.com/b');
    });

    test('duplicate committed URL does not create another entry', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/a');

      expect(history.current, 'https://example.com/a');
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
    });

    test('clear removes the whole agent history', () {
      final history = BrowserNavigationHistory()
        ..reset('https://example.com/a')
        ..push('https://example.com/b')
        ..clear();

      expect(history.current, isNull);
      expect(history.backTarget, isNull);
      expect(history.forwardTarget, isNull);
      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
    });
  });
}
