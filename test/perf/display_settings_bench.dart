import '../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/display_settings_page.dart';
import 'package:Kelivo/features/settings/pages/message_style_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

// Explicit benchmark; timings are observations, not regression assertions.
void main() {
  for (final entry in <String, Widget>{
    'display': const DisplaySettingsPage(),
    'chatItems': const ChatItemDisplaySettingsPage(),
    'rendering': const RenderingSettingsPage(),
    'behavior': const BehaviorStartupSettingsPage(),
    'messageStyle': const MessageStyleSettingsPage(),
  }.entries) {
    testWidgets('${entry.key}: an unrelated settings change', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider(createBusinessTestPreferences());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider(
              create: (_) => AssistantProvider(
                preferences: createBusinessTestPreferences(),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: entry.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final samples = <int>[];
      for (var i = 0; i < 40; i++) {
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
        final sw = Stopwatch()..start();
        await tester.pump();
        sw.stop();
        if (i >= 5) samples.add(sw.elapsedMicroseconds);
      }
      samples.sort();
      // ignore: avoid_print
      print(
        'SETTINGS_PAGE ${entry.key} '
        'medianUs=${samples[samples.length ~/ 2]} '
        'p95Us=${samples[(samples.length * .95).floor()]}',
      );
    });
  }
}
