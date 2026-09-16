import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installations use Russian before and after async load', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    expect(settings.appLocaleForMaterialApp, const Locale('ru'));
    expect(settings.isFollowingSystemLocale, isFalse);
    await settings.loaded;
    expect(settings.appLocaleForMaterialApp, const Locale('ru'));
    expect(harness.preferences.get('app_locale_v1'), 'ru');
  });

  test('Russian round-trips through persisted preferences', () async {
    final harness = await createBusinessTestHarness(
      initial: const {'app_locale_v1': 'en_US'},
    );
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await settings.setAppLocale(const Locale('ru', 'RU'));
    expect(harness.preferences.get('app_locale_v1'), 'ru');
    final reopened = SettingsProvider(harness.preferences);
    expect(reopened.appLocaleForMaterialApp, const Locale('ru'));
    await reopened.loaded;
    expect(reopened.appLocaleForMaterialApp, const Locale('ru'));
  });

  test('English and explicit follow-system survive initialization', () async {
    for (final tag in ['en_US', 'zh_CN', 'zh_Hant', 'system']) {
      final harness = await createBusinessTestHarness(
        initial: {'app_locale_v1': tag},
      );
      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      expect(harness.preferences.get('app_locale_v1'), tag);
      expect(settings.isFollowingSystemLocale, tag == 'system');
      if (tag == 'en_US') {
        expect(settings.appLocaleForMaterialApp, const Locale('en', 'US'));
      }
    }
  });

  test('switching Russian to English or system remains functional', () async {
    final harness = await createBusinessTestHarness(
      initial: const {'app_locale_v1': 'ru'},
    );
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await settings.setAppLocale(const Locale('en', 'US'));
    expect(settings.appLocaleForMaterialApp, const Locale('en', 'US'));
    await settings.setAppLocaleFollowSystem();
    expect(settings.appLocaleForMaterialApp, isNull);
    expect(harness.preferences.get('app_locale_v1'), 'system');
  });
}
