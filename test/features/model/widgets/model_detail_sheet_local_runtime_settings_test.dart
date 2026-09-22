import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/local/local_model_library.dart';
import 'package:Kelivo/features/model/widgets/model_detail_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsProvider> settingsWithInstalledModel(
    WidgetTester tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await settings.setProviderConfig(
      kLocalModelProviderKey,
      ProviderConfig(
        id: kLocalModelProviderKey,
        enabled: true,
        name: 'Local models',
        apiKey: '',
        baseUrl: '',
        providerType: ProviderKind.local,
        models: const ['litert-test-model'],
        modelOverrides: {
          'litert-test-model': <String, dynamic>{
            'apiModelId': 'litert-test-model',
            'name': 'Test model',
            'type': 'chat',
            'input': ['text'],
            'output': ['text'],
            'abilities': ['reasoning'],
            'localModelPath': '/models/test.litertlm',
            'localBackend': 'cpu',
            'localMaxNumTokens': 4096,
            'localTemperature': 1.0,
            'localTopK': 64,
            'localTopP': 0.95,
            'localThinking': true,
            'localThinkingBudget': -1,
            'localVision': false,
            'localAudio': false,
            'localTools': false,
            'localKeepLoaded': false,
            'localSizeBytes': 1024,
            'localSourceLabel': 'test.litertlm',
            'localInstalledAtMillis': 1758000000000,
            'localSha256': 'test-sha256',
          },
        },
      ),
    );
    return settings;
  }

  Future<void> openSettingsSheet(
    WidgetTester tester,
    SettingsProvider settings,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-local-model-settings'),
                onPressed: () => showModelDetailSheet(
                  context,
                  providerKey: kLocalModelProviderKey,
                  modelId: 'litert-test-model',
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-local-model-settings')));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.modelDetailSheetAdvancedTab));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'local runtime settings save while retaining the installed file identity',
    (tester) async {
      final settings = await settingsWithInstalledModel(tester);
      await openSettingsSheet(tester, settings);

      final contextField = find.byKey(const ValueKey('local-runtime-context'));
      expect(contextField, findsOneWidget);
      expect(
        find.byKey(const ValueKey('local-runtime-backend')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-runtime-thinking-budget')),
        findsOneWidget,
      );

      await tester.ensureVisible(contextField);
      await tester.enterText(contextField, '8192');
      final temperatureField = find.byKey(
        const ValueKey('local-runtime-temperature'),
      );
      await tester.ensureVisible(temperatureField);
      await tester.enterText(temperatureField, '0.4');
      final topKField = find.byKey(const ValueKey('local-runtime-top-k'));
      await tester.ensureVisible(topKField);
      await tester.enterText(topKField, '32');
      final topPField = find.byKey(const ValueKey('local-runtime-top-p'));
      await tester.ensureVisible(topPField);
      await tester.enterText(topPField, '0.8');
      final thinkingBudgetField = find.byKey(
        const ValueKey('local-runtime-thinking-budget'),
      );
      await tester.ensureVisible(thinkingBudgetField);
      await tester.enterText(thinkingBudgetField, '256');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      final backend = find.byKey(const ValueKey('local-runtime-backend'));
      await tester.ensureVisible(backend);
      await tester.tap(
        find.descendant(of: backend, matching: find.text('GPU')),
      );
      final audioSwitch = find.byKey(
        const ValueKey('local-runtime-audio-switch'),
      );
      await tester.ensureVisible(audioSwitch);
      await tester.tap(audioSwitch);
      final keepLoadedSwitch = find.byKey(
        const ValueKey('local-runtime-keep-loaded-switch'),
      );
      await tester.ensureVisible(keepLoadedSwitch);
      await tester.tap(keepLoadedSwitch);
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.modelDetailSheetConfirmButton));
      await tester.pumpAndSettle();

      final saved =
          settings
                  .getProviderConfig(kLocalModelProviderKey)
                  .modelOverrides['litert-test-model']
              as Map<String, dynamic>;
      expect(saved['localBackend'], 'gpu');
      expect(saved['localMaxNumTokens'], 8192);
      expect(saved['localTemperature'], 0.4);
      expect(saved['localTopK'], 32);
      expect(saved['localTopP'], 0.8);
      expect(saved['localThinkingBudget'], 256);
      expect(saved['localAudio'], isTrue);
      expect(saved['localKeepLoaded'], isTrue);
      expect(saved['localThinking'], isTrue);
      expect(saved['localModelPath'], '/models/test.litertlm');
      expect(saved['localSha256'], 'test-sha256');
      expect(saved['localSizeBytes'], 1024);
      expect(saved['localSourceLabel'], 'test.litertlm');
      expect(saved['localInstalledAtMillis'], 1758000000000);
    },
  );

  testWidgets('invalid local runtime values do not save the model', (
    tester,
  ) async {
    final settings = await settingsWithInstalledModel(tester);
    await openSettingsSheet(tester, settings);

    final temperatureField = find.byKey(
      const ValueKey('local-runtime-temperature'),
    );
    expect(temperatureField, findsOneWidget);
    await tester.ensureVisible(temperatureField);
    await tester.enterText(temperatureField, 'NaN');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.modelDetailSheetConfirmButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.modelDetailSheetEditModel), findsOneWidget);
    final saved =
        settings
                .getProviderConfig(kLocalModelProviderKey)
                .modelOverrides['litert-test-model']
            as Map<String, dynamic>;
    expect(saved['localTemperature'], 1.0);
  });
}
