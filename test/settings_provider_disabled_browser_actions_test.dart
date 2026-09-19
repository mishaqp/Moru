import "support/business_test_harness.dart";
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider disabled browser actions', () {
    test('every action starts enabled', () async {
      final harness = await createBusinessTestHarness(initial: {});
      final settings = SettingsProvider(harness.preferences);

      await settings.loaded;

      expect(settings.disabledBrowserActions, isEmpty);
    });

    test('loads a persisted disabled set', () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'browser_disabled_actions_v1': ['eval_js', 'click'],
        },
      );
      final settings = SettingsProvider(harness.preferences);

      await settings.loaded;

      expect(settings.disabledBrowserActions, {'eval_js', 'click'});
    });

    test(
      'disabling then re-enabling an action persists both changes',
      () async {
        final harness = await createBusinessTestHarness(initial: {});
        final settings = SettingsProvider(harness.preferences);
        await settings.loaded;

        await settings.setBrowserActionEnabled('eval_js', false);
        expect(settings.disabledBrowserActions, {'eval_js'});
        expect(
          harness.preferences.getStringList('browser_disabled_actions_v1'),
          ['eval_js'],
        );

        await settings.setBrowserActionEnabled('eval_js', true);
        expect(settings.disabledBrowserActions, isEmpty);
        expect(
          harness.preferences.getStringList('browser_disabled_actions_v1'),
          isEmpty,
        );
      },
    );

    test('re-disabling an already-disabled action does not notify', () async {
      final harness = await createBusinessTestHarness(initial: {});
      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      await settings.setBrowserActionEnabled('click', false);

      var notified = false;
      settings.addListener(() => notified = true);
      await settings.setBrowserActionEnabled('click', false);

      expect(notified, isFalse);
    });
  });
}
