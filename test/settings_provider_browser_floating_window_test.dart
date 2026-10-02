import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';

import 'support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('floating browser is off when no setting was saved', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    expect(settings.browserFloatingWindow, isFalse);
  });

  test(
    'a saved floating-browser opt-in survives provider recreation',
    () async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      var notifications = 0;
      settings.addListener(() => notifications++);
      await settings.setBrowserFloatingWindow(true);
      expect(settings.browserFloatingWindow, isTrue);
      expect(harness.preferences.getBool('browser_floating_window_v1'), isTrue);
      expect(notifications, 1);

      final restored = SettingsProvider(harness.preferences);
      addTearDown(restored.dispose);
      await restored.loaded;
      expect(restored.browserFloatingWindow, isTrue);
      final copied = restored.copyWith();
      addTearDown(copied.dispose);
      expect(copied.browserFloatingWindow, isTrue);
      await restored.setBrowserFloatingWindow(false);
      expect(
        harness.preferences.getBool('browser_floating_window_v1'),
        isFalse,
      );
    },
  );

  test('saving the current floating-browser setting does not notify', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    var notifications = 0;
    settings.addListener(() => notifications++);
    await settings.setBrowserFloatingWindow(false);
    expect(notifications, 0);
  });
}
