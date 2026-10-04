import 'dart:io';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/assistant/pages/assistant_settings_edit_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/acp_test_manager.dart';
import '../../support/business_test_harness.dart';

void main() {
  setUpAll(() async {
    final bytes = await File(
      'dependencies/gpt_markdown/lib/fonts/JetBrainsMono-Regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'AssistantBackgroundTest',
    )..addFont(Future.value(bytes.buffer.asByteData()))).load();
  });

  for (final layout in [
    (
      label: 'portrait image',
      size: const Size(400, 900),
      brightness: Brightness.light,
      scale: 1.0,
      gradient: false,
    ),
    (
      label: 'landscape gradient',
      size: const Size(900, 400),
      brightness: Brightness.dark,
      scale: 1.3,
      gradient: true,
    ),
    (
      label: 'wide gradient',
      size: const Size(1000, 800),
      brightness: Brightness.light,
      scale: 1.3,
      gradient: true,
    ),
  ]) {
    testWidgets(
      'basic settings retire background controls and preserve saved values on ${layout.label}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final state = (await tester.runAsync(() async {
          final preferences = createBusinessTestPreferences();
          final assistants = AssistantProvider(preferences: preferences);
          final settings = SettingsProvider(createBusinessTestPreferences());
          await assistants.loaded;
          final id = await assistants.addAssistant(name: 'Legacy assistant');
          await assistants.updateAssistant(
            assistants
                .getById(id)!
                .copyWith(
                  background: '/legacy/background.jpg',
                  useGradientBackground: layout.gradient,
                  gradientBackgroundAnimated: false,
                  gradientBackgroundPhase: 7,
                  gradientBackgroundOffsetX: 0.4,
                  gradientBackgroundOffsetY: -0.6,
                  temperature: 0.8,
                  topP: 0.7,
                  maxTokens: 2048,
                  thinkingBudget: 1024,
                  chatModelProvider: 'openai',
                  chatModelId: 'legacy-model',
                ),
          );
          await settings.loaded;
          return (
            preferences: preferences,
            assistants: assistants,
            settings: settings,
            id: id,
          );
        }))!;
        final preferences = state.preferences;
        final assistants = state.assistants;
        final settings = state.settings;
        final id = state.id;
        final original = assistants.getById(id)!.toJson();
        addTearDown(assistants.dispose);
        addTearDown(settings.dispose);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: assistants),
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider(
                create: (_) => createTestAcpAgentManager(),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              theme: ThemeData(
                brightness: layout.brightness,
                fontFamily: 'AssistantBackgroundTest',
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openAssistantBasicSettings(context, assistantId: id),
                    child: const Text('Open settings'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();

        final list = find.byType(ListView).last;
        await tester.drag(list, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(find.text('Chat Background'), findsNothing);
        expect(find.text('Gradient background'), findsNothing);
        expect(find.text('Static mode'), findsNothing);
        expect(find.text('Choose Image'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.drag(list, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.enterText(
            find.byType(TextField).first,
            'Renamed assistant',
          );
          await preferences.flushPendingWrites();
        });
        await tester.pumpAndSettle();
        expect(assistants.getById(id)!.toJson(), {
          ...original,
          'name': 'Renamed assistant',
        });

        final reloaded = (await tester.runAsync(() async {
          final provider = AssistantProvider(preferences: preferences);
          await provider.loaded;
          return provider;
        }))!;
        addTearDown(reloaded.dispose);
        expect(reloaded.getById(id)!.toJson(), {
          ...original,
          'name': 'Renamed assistant',
        });
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
