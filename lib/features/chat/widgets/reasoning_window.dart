/// How much of a reasoning text the chat renders, so long reasoning (tens of
/// thousands of characters from DeepSeek or GPT-5) does not re-lay out the
/// whole text on every streamed chunk.
class ReasoningWindow {
  const ReasoningWindow._();

  /// While streaming only the end is shown: it is what the model is on now.
  static const int streamingChars = 8000;

  /// Finished reasoning longer than this is shown as plain, virtualized text
  /// instead of Markdown.
  static const int plainAboveChars = 20000;

  /// A line break this close after the cut starts the tail there, so the
  /// first shown line is whole.
  static const int _lineSnap = 200;

  /// The last [max] characters of [text] and how many were left out.
  static ({String text, int hidden}) tail(
    String text, {
    int max = streamingChars,
  }) {
    if (text.length <= max) return (text: text, hidden: 0);
    var start = text.length - max;
    final newline = text.indexOf('\n', start);
    if (newline != -1 && newline < start + _lineSnap) start = newline + 1;
    return (text: text.substring(start), hidden: start);
  }

  /// "950", "12K": the size shown in the reasoning header.
  static String sizeLabel(int chars) =>
      chars >= 1000 ? '${chars ~/ 1000}K' : '$chars';
}
