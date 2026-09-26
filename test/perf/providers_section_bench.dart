import '../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/model/pages/default_model_page.dart';
import 'package:Kelivo/features/model/widgets/model_select_sheet.dart';
import 'package:Kelivo/features/provider/pages/providers_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

// Explicit benchmark; timings are observations, not regression assertions.

Future<SettingsProvider> _settings(
  WidgetTester tester, {
  required int providers,
  required int models,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider(createBusinessTestPreferences());
  await tester.pump(const Duration(milliseconds: 300));
  for (var p = 0; p < providers; p++) {
    await settings.setProviderConfig(
      'Bench$p',
      ProviderConfig(
        id: 'Bench$p',
        enabled: true,
        name: 'Bench $p',
        apiKey: 'k',
        baseUrl: 'https://example.test',
        providerType: ProviderKind.openai,
        models: [for (var i = 0; i < models; i++) 'gpt-4o-mini-$p-$i'],
      ),
    );
  }
  await settings.setCurrentModel('Bench0', 'gpt-4o-mini-0-0');
  return settings;
}

Widget _app(SettingsProvider settings, Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ChangeNotifierProvider<AssistantProvider>(
      create: (_) =>
          AssistantProvider(preferences: createBusinessTestPreferences()),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Future<void> _unrelatedChanges(
  WidgetTester tester,
  SettingsProvider settings,
  String label,
) async {
  final samples = <int>[];
  for (var i = 0; i < 40; i++) {
    await settings.setTtsAutoPlayAssistantReplies(i.isEven);
    final sw = Stopwatch()..start();
    await tester.pump();
    sw.stop();
    if (i >= 5) samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  // ignore: avoid_print
  print(
    '$label medianUs=${samples[samples.length ~/ 2]} '
    'p95Us=${samples[(samples.length * .95).floor()]}',
  );
}

void main() {
  setUp(() {});

  testWidgets('providers list: unrelated setting change', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final settings = await _settings(tester, providers: 20, models: 20);
    await tester.pumpWidget(_app(settings, const ProvidersPage()));
    await tester.pumpAndSettle();
    await _unrelatedChanges(tester, settings, 'PROVIDERS_LIST');
  });

  testWidgets('providers list under another screen: key typed in detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final settings = await _settings(tester, providers: 20, models: 20);
    await tester.pumpWidget(_app(settings, const ProvidersPage()));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ProvidersPage))).push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('x'))),
    );
    await tester.pumpAndSettle();
    final samples = <int>[];
    for (var i = 0; i < 40; i++) {
      final cfg = settings.getProviderConfig('Bench3');
      await settings.setProviderConfig('Bench3', cfg.copyWith(apiKey: 'k$i'));
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      if (i >= 5) samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print(
      'PROVIDERS_LIST_COVERED medianUs=${samples[samples.length ~/ 2]} '
      'p95Us=${samples[(samples.length * .95).floor()]}',
    );
  });

  testWidgets('default models: unrelated setting change', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final settings = await _settings(tester, providers: 5, models: 20);
    await tester.pumpWidget(_app(settings, const DefaultModelPage()));
    await tester.pumpAndSettle();
    await _unrelatedChanges(tester, settings, 'DEFAULT_MODELS');
  });

  testWidgets('model selector: open with 10 x 100 models', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final settings = await _settings(tester, providers: 10, models: 100);
    await tester.pumpWidget(
      _app(
        settings,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModelSelector(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    final opens = <int>[];
    final frames = <int>[];
    for (var round = 0; round < 6; round++) {
      await tester.tap(find.text('open'));
      final sw = Stopwatch()..start();
      var count = 0;
      await tester.pump();
      while (find.textContaining('gpt-4o-mini-0-0').evaluate().isEmpty &&
          count < 200) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 16));
        count++;
      }
      sw.stop();
      if (round > 0) {
        opens.add(sw.elapsedMicroseconds);
        frames.add(count);
      }
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('open'))).pop();
      await tester.pumpAndSettle();
    }
    opens.sort();
    // ignore: avoid_print
    print(
      'MODEL_SELECTOR_OPEN medianUs=${opens[opens.length ~/ 2]} '
      'frames=$frames',
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final search = find.byType(TextField).first;
    final samples = <int>[];
    for (var i = 0; i < 20; i++) {
      await tester.enterText(search, i.isEven ? 'mini-3-4' : 'mini-7');
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      if (i >= 4) samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print(
      'MODEL_SELECTOR_SEARCH medianUs=${samples[samples.length ~/ 2]} '
      'p95Us=${samples[(samples.length * .95).floor()]}',
    );
  });
}
