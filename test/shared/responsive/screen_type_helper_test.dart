import 'package:Kelivo/shared/responsive/breakpoints.dart';
import 'package:Kelivo/shared/responsive/screen_type_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (width, type, wide) in [
    (390.0, ScreenType.mobile, false),
    (899.0, ScreenType.mobile, false),
    (900.0, ScreenType.tablet, false),
    (1199.0, ScreenType.tablet, false),
    (1200.0, ScreenType.desktop, true),
    (1599.0, ScreenType.desktop, true),
    (1600.0, ScreenType.wide, true),
  ]) {
    testWidgets('Android width $width retains its layout class', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Builder(
              builder: (context) {
                expect(ResponsiveHelper.screenType(context), type);
                expect(ResponsiveHelper.isWide(context), wide);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });
  }
}
