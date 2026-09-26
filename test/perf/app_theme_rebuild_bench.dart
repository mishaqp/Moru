import '../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/theme/app_theme_builder.dart';

// Explicit benchmark; timings are observations, not regression assertions.
void main() {
  testWidgets('root theme: an unrelated settings change', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(createBusinessTestPreferences());
    await tester.pump(const Duration(milliseconds: 300));
    var themeBuilds = 0;
    _ThemedScreen.builds = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: AppThemeBuilder(
          builder: (context, themes) {
            themeBuilds++;
            return MaterialApp(
              theme: themes.light,
              darkTheme: themes.dark,
              themeMode: themes.mode,
              home: const _ThemedScreen(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    themeBuilds = 0;
    _ThemedScreen.builds = 0;

    final samples = <int>[];
    var frames = 0;
    for (var i = 0; i < 40; i++) {
      // E.g. a model switch, a tool toggle or a provider's balance.
      await settings.setProviderConfig(
        'Other',
        ProviderConfig(
          id: 'Other',
          enabled: i.isEven,
          name: 'Other',
          apiKey: 'k$i',
          baseUrl: 'https://other.test',
          providerType: ProviderKind.openai,
          models: const ['m'],
        ),
      );
      // Until the theme animation, if any, has finished.
      final sw = Stopwatch()..start();
      frames += await tester.pumpAndSettle();
      sw.stop();
      if (i >= 5) samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print(
      'APP_THEME changes=40 frames=$frames themeBuilds=$themeBuilds '
      'screenRebuilds=${_ThemedScreen.builds} '
      'medianUs=${samples[samples.length ~/ 2]} '
      'p95Us=${samples[(samples.length * .95).floor()]}',
    );
  });
}

/// Stands in for every screen that reads theme colours; const like HomePage.
class _ThemedScreen extends StatelessWidget {
  const _ThemedScreen();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    builds++;
    return const SizedBox();
  }
}
