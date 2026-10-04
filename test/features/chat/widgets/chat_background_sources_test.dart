import 'dart:typed_data';

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(() => image.toByteData());
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('gradient renders, moves and applies live color effects', (
    tester,
  ) async {
    final key = GlobalKey();
    var background = const ChatBackgroundSettings(
      type: ChatBackgroundType.gradient,
      gradientAnimated: false,
      maskStrength: 0,
    );
    Widget app() => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Center(
        child: SizedBox(
          width: 120,
          height: 160,
          child: RepaintBoundary(
            key: key,
            child: ChatBackground(configuration: background),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    final original = await _pixels(tester, key);
    expect(original.where((byte) => byte != 0), isNotEmpty);
    background = background.copyWith(gradientOffsetX: .8, gradientOffsetY: -.5);
    await tester.pumpWidget(app());
    expect(await _pixels(tester, key), isNot(orderedEquals(original)));
    background = background.copyWith(saturation: 0, brightness: .5);
    await tester.pumpWidget(app());
    final grey = await _pixels(tester, key);
    for (var pixel = 0; pixel < grey.length; pixel += 4) {
      expect((grey[pixel] - grey[pixel + 1]).abs(), lessThanOrEqualTo(1));
      expect((grey[pixel + 1] - grey[pixel + 2]).abs(), lessThanOrEqualTo(1));
      expect(grey[pixel + 3], 255);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
