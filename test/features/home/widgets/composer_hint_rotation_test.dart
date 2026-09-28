import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/widgets/composer_hint_rotation.dart';

void main() {
  test('the plain hint stays for the first focus, then tips rotate', () {
    final hints = ComposerHintRotation(3);
    expect(hints.focused(screenReader: false), isFalse);
    expect(hints.index, 0);
    expect([
      for (var i = 0; i < 4; i++) (hints..focused(screenReader: false)).index,
    ], [1, 2, 0, 1]);

    hints.reset();
    expect(hints.index, 0);
    expect(hints.focused(screenReader: false), isFalse);
    expect(hints.index, 0);
  });

  test('with a screen reader the hint never changes', () {
    final hints = ComposerHintRotation(3)..focused(screenReader: true);
    expect(hints.focused(screenReader: true), isFalse);
    expect(hints.index, 0);
    expect(ComposerHintRotation(1).focused(screenReader: false), isFalse);
  });
}
