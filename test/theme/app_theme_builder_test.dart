import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/theme/app_theme_builder.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:Kelivo/theme/theme_factory.dart';

import '../support/business_test_harness.dart';

void main() {
  late SettingsProvider settings;
  late List<AppThemes> built;

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsProvider(createBusinessTestPreferences());
    await tester.pump(const Duration(milliseconds: 300));
    built = [];
    _Screen.builds = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: AppThemeBuilder(
          builder: (context, themes) {
            built.add(themes);
            return MaterialApp(
              theme: themes.light,
              darkTheme: themes.dark,
              themeMode: themes.mode,
              home: const _Screen(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    built.clear();
    _Screen.builds = 0;
  }

  testWidgets('other settings rebuild neither the theme nor the screens', (
    tester,
  ) async {
    await pump(tester);
    await settings.setProviderConfig(
      'Other',
      ProviderConfig(
        id: 'Other',
        enabled: true,
        name: 'Other',
        apiKey: 'k',
        baseUrl: 'https://other.test',
        providerType: ProviderKind.openai,
        models: const ['m'],
      ),
    );
    await tester.pumpAndSettle();
    expect(built, isEmpty);
    expect(_Screen.builds, 0);
  });

  testWidgets('theme settings rebuild the theme', (tester) async {
    await pump(tester);
    final other = ThemePalettes.all
        .firstWhere((p) => p.id != settings.themePaletteId)
        .id;
    await settings.setThemePalette(other);
    await tester.pumpAndSettle();
    expect(built, isNotEmpty);
    expect(
      built.last.light.colorScheme.primary,
      ThemePalettes.byId(other).light.primary,
    );
    expect(_Screen.builds, greaterThan(0));

    built.clear();
    await settings.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(built.single.mode, ThemeMode.dark);

    built.clear();
    await settings.setAppFontSystemFamily('Roboto Slab');
    await tester.pumpAndSettle();
    expect(built.last.fontFamily, 'Roboto Slab');
    expect(built.last.light.textTheme.bodyMedium?.fontFamily, 'Roboto Slab');
  });

  test('themes built twice from the same settings are equal', () {
    final palette = ThemePalettes.all.first;
    expect(
      buildLightThemeForScheme(palette.light),
      buildLightThemeForScheme(palette.light),
    );
    expect(
      buildDarkThemeForScheme(palette.dark),
      buildDarkThemeForScheme(palette.dark),
    );
  });
}

class _Screen extends StatelessWidget {
  const _Screen();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    builds++;
    return const SizedBox();
  }
}
