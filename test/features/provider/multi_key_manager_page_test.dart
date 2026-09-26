import '../../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/api_keys.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/provider/pages/multi_key_manager_page.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Future<SettingsProvider> _pumpPage(
  WidgetTester tester, {
  List<ApiKeyConfig> keys = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider(createBusinessTestPreferences());
  await tester.pump(const Duration(milliseconds: 300));
  await settings.setProviderConfig(
    'Keys',
    ProviderConfig(
      id: 'Keys',
      enabled: true,
      name: 'Keys',
      apiKey: '',
      baseUrl: 'https://example.test',
      providerType: ProviderKind.openai,
      models: const [],
      apiKeys: keys,
    ),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiKeyManagerPage(
          providerKey: 'Keys',
          providerDisplayName: 'Keys',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

List<ApiKeyConfig> _keys(SettingsProvider settings) =>
    settings.getProviderConfig('Keys').apiKeys ?? const [];

void main() {
  testWidgets('add sheet adds each new key once', (tester) async {
    final settings = await _pumpPage(
      tester,
      keys: [ApiKeyConfig.create('old')],
    );

    await tester.tap(find.byIcon(Lucide.Plus));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'k1, k2 k1\nold');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(_keys(settings).map((k) => k.key), ['old', 'k1', 'k2']);
    expect(settings.getProviderConfig('Keys').multiKeyEnabled, isTrue);
    // The snackbars (import count, then "add a model first") time out.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('strategy sheet saves the chosen strategy', (tester) async {
    final settings = await _pumpPage(tester);

    await tester.tap(find.text('Round Robin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Random'));
    await tester.pumpAndSettle();

    expect(
      settings.getProviderConfig('Keys').keyManagement?.strategy,
      LoadBalanceStrategy.random,
    );
    expect(find.text('Random'), findsOneWidget);
  });

  testWidgets('edit sheet saves alias, key and priority', (tester) async {
    final settings = await _pumpPage(
      tester,
      keys: [ApiKeyConfig.create('first'), ApiKeyConfig.create('second')],
    );

    await tester.tap(find.byIcon(Lucide.Pencil).first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Main');
    await tester.enterText(fields.at(1), 'renamed');
    await tester.enterText(fields.at(2), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final first = _keys(settings).first;
    expect(first.name, 'Main');
    expect(first.key, 'renamed');
    expect(first.priority, 3);
  });

  testWidgets('edit sheet refuses a key that already exists', (tester) async {
    final settings = await _pumpPage(
      tester,
      keys: [ApiKeyConfig.create('first'), ApiKeyConfig.create('second')],
    );

    await tester.tap(find.byIcon(Lucide.Pencil).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'second');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_keys(settings).map((k) => k.key), ['first', 'second']);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
