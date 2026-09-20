/// Plain-text preview extraction for the browser Ask-AI result card: strips
/// Markdown formatting markers so a clamped preview never shows literal
/// `**bold**` or backticks, while leaving normal prose, link text, and code
/// *content* untouched.
///
/// Code spans (fenced ` ``` ` blocks and inline `` ` `` spans) are masked out
/// before any other rule runs -- the same order `_preprocessFences` in
/// `markdown_with_highlight.dart` already uses for the same "don't let
/// prose rules see code" concern -- so an emphasis marker or a heading `#`
/// that is only ever literal code text is never mistaken for real Markdown
/// syntax. Only the fence/backtick delimiters are dropped; the code's own
/// text is kept, unlike `TtsProvider._stripMarkdown`'s `markdownRemoveCode`
/// (built for reading text aloud, where code is skipped rather than
/// spoken) -- a preview that shows nothing for a code-heavy reply is less
/// useful than one that shows the code text itself.
library;

final RegExp _codeSpanPattern = RegExp(
  r'(^[ \t]*(([`~])\3{2,})[^\n]*\n([\s\S]*?)^[ \t]*\2\3*[ \t]*$)'
  r'|(`([^`\n]+)`)',
  multiLine: true,
);

final RegExp _linkPattern = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final RegExp _blockMarkerPattern = RegExp(
  r'^[ \t]{0,3}(?:#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+|\d+\.[ \t]+)',
  multiLine: true,
);
final RegExp _tableDividerPattern = RegExp(
  r'^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$',
  multiLine: true,
);
final RegExp _tripleEmphasisPattern = RegExp(r'(\*\*\*|___)([^*_\n]+)\1');
final RegExp _doubleEmphasisPattern = RegExp(r'(\*\*|__)([^*_\n]+)\1');
final RegExp _singleEmphasisPattern = RegExp(r'(?<![*_])(\*|_)([^*_\n]+)\1');
final RegExp _strikethroughPattern = RegExp(r'~~([^~\n]+)~~');
final RegExp _placeholderPattern = RegExp('(\\d+)');
final RegExp _horizontalWhitespacePattern = RegExp(r'[ \t]+');

String browserAskAiPreviewPlainText(String source) {
  if (source.trim().isEmpty) return '';

  final codeMap = <String, String>{};
  var codeCount = 0;
  var masked = source.replaceAllMapped(_codeSpanPattern, (m) {
    final content = (m.group(4) ?? m.group(6) ?? '').trim();
    if (content.isEmpty) return '';
    final key = '${codeCount++}';
    codeMap[key] = content;
    return key;
  });

  var s = masked;
  s = s.replaceAllMapped(_linkPattern, (m) => m.group(1) ?? '');
  s = s.replaceAll(_blockMarkerPattern, '');
  s = s.replaceAll(_tableDividerPattern, '');
  s = s.replaceAll('|', ' ');
  s = s.replaceAllMapped(_tripleEmphasisPattern, (m) => m.group(2) ?? '');
  s = s.replaceAllMapped(_doubleEmphasisPattern, (m) => m.group(2) ?? '');
  s = s.replaceAllMapped(_singleEmphasisPattern, (m) => m.group(2) ?? '');
  s = s.replaceAllMapped(_strikethroughPattern, (m) => m.group(1) ?? '');

  s = s.replaceAllMapped(
    _placeholderPattern,
    (m) => codeMap['${m.group(1)}'] ?? '',
  );

  s = s.replaceAll(_horizontalWhitespacePattern, ' ');
  s = s
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
  return s.trim();
}
