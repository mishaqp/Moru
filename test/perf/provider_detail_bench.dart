import '../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/provider/pages/provider_detail_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

// Explicit benchmark; timings are observations, not regression assertions.
void main() {
  testWidgets('provider detail: unrelated setting change with 300 models', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(createBusinessTestPreferences());
    await tester.pump(const Duration(milliseconds: 300));
    await settings.setProviderConfig(
      'Bench',
      ProviderConfig(
        id: 'Bench',
        enabled: true,
        name: 'Bench',
        apiKey: 'k',
        baseUrl: 'https://example.test',
        providerType: ProviderKind.openai,
        models: [for (var i = 0; i < 300; i++) 'gpt-4o-mini-$i'],
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
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
          home: const ProviderDetailPage(
            keyName: 'Bench',
            displayName: 'Bench',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();

    var elements = 0;
    void visit(Element e) {
      elements++;
      e.visitChildren(visit);
    }

    tester.binding.rootElement!.visitChildren(visit);

    final samples = <int>[];
    for (var i = 0; i < 40; i++) {
      // Another provider changes, e.g. its balance or key.
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
      // Only the rebuild and layout that follow the change.
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      if (i >= 5) samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print(
      'PROVIDER_DETAIL elements=$elements '
      'medianUs=${samples[samples.length ~/ 2]} '
      'p95Us=${samples[(samples.length * .95).floor()]}',
    );
  });
}
