import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFontWeights', () {
    test(
      'normalizes medium to regular and heavier weights to medium on Android',
      () {
        expect(AppFontWeights.normalize(FontWeight.w400), FontWeight.w400);
        expect(AppFontWeights.normalize(FontWeight.w500), FontWeight.w400);
        expect(AppFontWeights.normalize(FontWeight.w600), FontWeight.w500);
        expect(AppFontWeights.normalize(FontWeight.bold), FontWeight.w500);
        expect(AppFontWeights.normalize(FontWeight.w700), FontWeight.w500);
        expect(AppFontWeights.normalize(FontWeight.w800), FontWeight.w500);
      },
    );
  });
}
