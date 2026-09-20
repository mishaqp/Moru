import 'package:Kelivo/shared/widgets/browser_ask_ai_preview_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips bold and italic markers, keeps the text', () {
    expect(
      browserAskAiPreviewPlainText('**жирный текст** и *курсив*'),
      'жирный текст и курсив',
    );
  });

  test('strips inline code backticks but keeps the code text', () {
    expect(
      browserAskAiPreviewPlainText('Use `foo()` to start'),
      'Use foo() to start',
    );
  });

  test('keeps fenced code content, drops the fence markers', () {
    const source = 'Before\n```dart\nprint("**not bold**");\n```\nAfter';
    final result = browserAskAiPreviewPlainText(source);
    expect(result, contains('print("**not bold**")'));
    expect(result, isNot(contains('```')));
  });

  test('shows link text, drops the URL', () {
    expect(
      browserAskAiPreviewPlainText('See [the docs](https://example.com/x)'),
      'See the docs',
    );
  });

  test('does not mangle a long bare URL', () {
    const url = 'https://example.com/a/b/c?x=1&y=2';
    expect(browserAskAiPreviewPlainText(url), url);
  });

  test('strips heading, list and blockquote markers', () {
    const source = '# Title\n- item one\n- item two\n> a quote';
    final result = browserAskAiPreviewPlainText(source);
    expect(result, 'Title\nitem one\nitem two\na quote');
  });

  test('strips strikethrough markers', () {
    expect(browserAskAiPreviewPlainText('~~old~~ new'), 'old new');
  });

  test('does not corrupt plain multiplication-looking text', () {
    expect(browserAskAiPreviewPlainText('3 * 4 = 12'), '3 * 4 = 12');
  });

  test('collapses blank lines between paragraphs to a single break', () {
    expect(
      browserAskAiPreviewPlainText('First paragraph.\n\n\nSecond paragraph.'),
      'First paragraph.\nSecond paragraph.',
    );
  });

  test('leaves RAW JSON / technical text untouched aside from whitespace', () {
    const source = 'RAW: {"ok": true, "detail": "full trust required"}';
    expect(browserAskAiPreviewPlainText(source), source);
  });

  test('empty or whitespace-only input returns empty string', () {
    expect(browserAskAiPreviewPlainText(''), '');
    expect(browserAskAiPreviewPlainText('   \n  '), '');
  });
}
