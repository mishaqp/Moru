import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/ios_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

void main() {
  for (final width in [390.0, 720.0, 1280.0]) {
    testWidgets('Android date picker retains its layout at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      DateTime? selected;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showIosDatePicker(
                      context,
                      firstDate: DateTime(2026),
                      lastDate: DateTime(2026, 12, 31),
                      initialDate: DateTime(2026, 10, 15, 18),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), width >= 720 ? findsOneWidget : findsNothing);
      expect(
        find.byType(BottomSheet),
        width < 720 ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      expect(selected, DateTime(2026, 10, 15));
    });
  }
}
