import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android updates preserve retired preferences and keyboard choice',
    () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'display_desktop_message_nav_buttons_mode_v1': 'hover',
          'desktop_send_shortcut_v1': 'ctrlEnter',
        },
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;

      expect(settings.desktopSendShortcut, DesktopSendShortcut.ctrlEnter);
      await settings.setMobileMessageNavButtonsMode(
        MobileMessageNavButtonsMode.always,
      );

      expect(
        harness.preferences.getString(
          'display_desktop_message_nav_buttons_mode_v1',
        ),
        'hover',
      );
      expect(
        harness.preferences.getString('desktop_send_shortcut_v1'),
        'ctrlEnter',
      );
      expect(settings.desktopSendShortcut, DesktopSendShortcut.ctrlEnter);
    },
  );
}
