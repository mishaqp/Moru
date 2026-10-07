import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Text appended while a reply streams fades in word by word instead of
/// appearing a chunk at a time. Only the painting changes: the text is laid
/// out once, and the fade masks the new words' boxes for a moment.
class StreamingTextFade {
  StreamingTextFade(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  /// How long one word takes to appear.
  static const Duration wordFade = Duration(milliseconds: 350);

  /// The words of one batch start this far apart at most, and together
  /// within [batchSpread], so a large batch does not trail behind.
  static const Duration maxWordDelay = Duration(milliseconds: 40);
  static const Duration batchSpread = Duration(milliseconds: 300);

  final _batches = <StreamingFadeBatch>[];
  late final Ticker _ticker;

  // Frame time, carried over the ticker's restarts (each starts from zero).
  Duration _base = Duration.zero;
  Duration _tickerElapsed = Duration.zero;
  Duration get _now => _base + _tickerElapsed;

  /// Repaints the fading text on every frame of a fade.
  final ValueNotifier<Duration> now = ValueNotifier(Duration.zero);

  List<StreamingFadeBatch> get batches => _batches;

  /// Text [from]..[to] (offsets in the whole paragraph) just arrived.
  void appended(int from, int to) {
    if (to <= from) return;
    _batches.add(StreamingFadeBatch(from, to, _now));
    now.value = _now;
    if (!_ticker.isActive) _ticker.start();
  }

  /// Text was replaced or removed: nothing still fading is valid.
  void clear() {
    _batches.clear();
    _stop();
    now.value = _now;
  }

  void _tick(Duration elapsed) {
    _tickerElapsed = elapsed;
    final current = _now;
    _batches.removeWhere(
      (batch) => current - batch.at > batchSpread + wordFade,
    );
    now.value = current;
    if (_batches.isEmpty) _stop();
  }

  void _stop() {
    if (!_ticker.isActive) return;
    _ticker.stop();
    _base += _tickerElapsed;
    _tickerElapsed = Duration.zero;
  }

  void dispose() {
    _ticker.dispose();
    now.dispose();
  }

  /// Opacity of a word, the [index]th of [count] in a batch that arrived at
  /// [at], at time [now].
  static double wordOpacity({
    required Duration at,
    required Duration now,
    required int index,
    required int count,
  }) {
    final stepUs = count <= 1
        ? 0
        : math.min(
            maxWordDelay.inMicroseconds,
            batchSpread.inMicroseconds ~/ (count - 1),
          );
    final started = now - at - Duration(microseconds: stepUs * index);
    return (started.inMicroseconds / wordFade.inMicroseconds).clamp(0.0, 1.0);
  }
}

class StreamingFadeBatch {
  const StreamingFadeBatch(this.start, this.end, this.at);
  final int start;
  final int end;
  final Duration at;
}

/// Paints [child] (a paragraph that starts at [start] in the whole text)
/// with the words of the fading batches masked by their opacity.
class StreamingFadeText extends SingleChildRenderObjectWidget {
  const StreamingFadeText({
    super.key,
    required this.fade,
    required this.start,
    required super.child,
  });

  final StreamingTextFade fade;
  final int start;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderStreamingFadeText(fade, start);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderStreamingFadeText renderObject,
  ) {
    renderObject
      ..fade = fade
      ..start = start;
  }
}

/// Masks the fading words of the paragraph under it.
class RenderStreamingFadeText extends RenderProxyBox {
  RenderStreamingFadeText(this._fade, this._start);

  StreamingTextFade _fade;
  int _start;

  set fade(StreamingTextFade value) {
    if (identical(value, _fade)) return;
    if (attached) _fade.now.removeListener(markNeedsPaint);
    _fade = value;
    if (attached) _fade.now.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set start(int value) {
    if (value == _start) return;
    _start = value;
    markNeedsPaint();
  }

  InlineSpan? _plainSource;
  String _plain = '';

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fade.now.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _fade.now.removeListener(markNeedsPaint);
    super.detach();
  }

  RenderParagraph? _paragraph() {
    RenderParagraph? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderParagraph) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    final child = this.child;
    if (child != null) visit(child);
    return found;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final paragraph = child == null ? null : _paragraph();
    final masks = paragraph == null
        ? const <(Rect, double)>[]
        : _masks(paragraph);
    // A child with its own layer would not paint into the masked layer.
    if (child == null || masks.isEmpty || child.isRepaintBoundary) {
      super.paint(context, offset);
      return;
    }
    final origin =
        offset +
        MatrixUtils.transformPoint(
          paragraph!.getTransformTo(this),
          Offset.zero,
        );
    context.canvas.saveLayer((offset & size).inflate(8), Paint());
    context.paintChild(child, offset);
    for (final (rect, opacity) in masks) {
      context.canvas.drawRect(
        rect.shift(origin),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }
    context.canvas.restore();
  }

  /// Boxes painted see-through or partly so right now.
  @visibleForTesting
  int get fadingBoxes {
    final paragraph = _paragraph();
    return paragraph == null ? 0 : _masks(paragraph).length;
  }

  /// Boxes of the words still fading, with their opacity.
  List<(Rect, double)> _masks(RenderParagraph paragraph) {
    final batches = _fade.batches;
    if (batches.isEmpty) return const [];
    if (!identical(_plainSource, paragraph.text)) {
      _plainSource = paragraph.text;
      _plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
    }
    final end = _start + _plain.length;
    final now = _fade.now.value;
    final masks = <(Rect, double)>[];
    for (final batch in batches) {
      final from = math.max(batch.start, _start);
      final to = math.min(batch.end, end);
      if (from >= to) continue;
      final words = _words(batch.start, batch.end, from, to);
      for (var i = 0; i < words.length; i++) {
        final (wordStart, wordEnd, index, count) = words[i];
        final opacity = StreamingTextFade.wordOpacity(
          at: batch.at,
          now: now,
          index: index,
          count: count,
        );
        if (opacity >= 1) continue;
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: wordStart - _start,
            extentOffset: wordEnd - _start,
          ),
        )) {
          masks.add((box.toRect(), opacity));
        }
      }
    }
    return masks;
  }

  /// The words of a batch [batchStart]..[batchEnd] that lie in [from]..[to]
  /// of this paragraph, as (start, end, index in batch, words in batch).
  List<(int, int, int, int)> _words(
    int batchStart,
    int batchEnd,
    int from,
    int to,
  ) {
    // Only this paragraph's part of the batch is readable here; words are
    // counted over it, which is the whole batch unless it spans paragraphs.
    final text = _plain;
    final spans = <(int, int)>[];
    var i = from;
    while (i < to) {
      while (i < to && _isSpace(text.codeUnitAt(i - _start))) {
        i++;
      }
      if (i >= to) break;
      final wordStart = i;
      while (i < to && !_isSpace(text.codeUnitAt(i - _start))) {
        i++;
      }
      spans.add((wordStart, i));
    }
    return [
      for (var k = 0; k < spans.length; k++)
        (spans[k].$1, spans[k].$2, k, spans.length),
    ];
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x0a || unit == 0x09 || unit == 0x0d;
}
