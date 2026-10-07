import 'package:Kelivo/shared/widgets/streaming_rich_text.dart';
import 'package:Kelivo/shared/widgets/streaming_text_fade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('words of a batch start one after another and finish in time', () {
    double at(int index, int ms, {int count = 3}) =>
        StreamingTextFade.wordOpacity(
          at: Duration.zero,
          now: Duration(milliseconds: ms),
          index: index,
          count: count,
        );
    expect(at(0, 0), 0);
    expect(at(0, 175), closeTo(0.5, 1e-9));
    // The second word starts 40 ms later.
    expect(at(1, 40), 0);
    expect(at(1, 215), closeTo(0.5, 1e-9));
    expect(at(2, 430), 1);
    // A hundred words still arrive within 300 ms + one fade.
    expect(at(99, 650, count: 100), 1);
    expect(at(99, 290, count: 100), 0);
  });

  testWidgets('appended words fade in while streaming only', (tester) async {
    Future<void> show(String text, {bool animate = true}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingRichText(text: Text(text), animateAppends: animate),
        ),
      ),
    );
    int fading() => tester
        .renderObject<RenderStreamingFadeText>(find.byType(StreamingFadeText))
        .fadingBoxes;

    await show('Hello');
    await tester.pump(const Duration(seconds: 1));
    expect(fading(), 0);

    await show('Hello brave new world');
    expect(fading(), greaterThanOrEqualTo(3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fading(), greaterThan(0));
    await tester.pump(const Duration(seconds: 1));
    expect(fading(), 0);

    // A finished reply shows its text at once.
    await show('Hello brave new world, done', animate: false);
    expect(fading(), 0);
  });
}
