import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/provider/pages/provider_detail_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

void main() {
  Future<SettingsProvider> pumpModelsTab(
    WidgetTester tester,
    List<String> models, {
    Map<String, dynamic> overrides = const {},
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(createBusinessTestPreferences());
    await tester.pump(const Duration(milliseconds: 300));
    await settings.setProviderConfig(
      'P',
      ProviderConfig(
        id: 'P',
        enabled: true,
        name: 'P',
        apiKey: 'k',
        baseUrl: 'https://example.test',
        providerType: ProviderKind.openai,
        models: models,
        modelOverrides: overrides,
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
          home: const ProviderDetailPage(keyName: 'P', displayName: 'P'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    return settings;
  }

  Iterable<ReorderableDelayedDragStartListener> dragListeners(
    WidgetTester tester,
  ) => tester.widgetList<ReorderableDelayedDragStartListener>(
    find.byType(ReorderableDelayedDragStartListener),
  );

  final searchField = find.widgetWithText(TextField, 'Search models');

  testWidgets('short model lists have no search field', (tester) async {
    await pumpModelsTab(tester, ['a', 'b', 'c']);
    expect(searchField, findsNothing);
  });

  testWidgets('search filters by id and custom name, and stops reordering', (
    tester,
  ) async {
    final settings = await pumpModelsTab(
      tester,
      [for (var i = 0; i < 10; i++) 'model-$i', 'gpt-4o'],
      overrides: {
        'model-3': {'name': 'Vision Pro'},
      },
    );
    expect(searchField, findsOneWidget);
    expect(dragListeners(tester).every((l) => l.enabled), isTrue);

    await tester.enterText(searchField, 'GPT');
    await tester.pumpAndSettle();
    expect(find.text('gpt-4o'), findsOneWidget);
    expect(find.text('model-0'), findsNothing);
    expect(dragListeners(tester), hasLength(1));
    expect(dragListeners(tester).single.enabled, isFalse);

    await tester.enterText(searchField, 'vision');
    await tester.pumpAndSettle();
    expect(find.text('Vision Pro'), findsOneWidget);
    expect(dragListeners(tester), hasLength(1));

    // Filtering never touches the saved order.
    expect(settings.getProviderConfig('P').models.first, 'model-0');

    await tester.tap(find.byTooltip('Search models'));
    await tester.pumpAndSettle();
    expect(dragListeners(tester).length, greaterThan(1));
    expect(dragListeners(tester).every((l) => l.enabled), isTrue);
  });

  testWidgets('long press and drag still reorders models', (tester) async {
    final settings = await pumpModelsTab(tester, ['a-model', 'b-model']);
    final first = tester.getCenter(find.text('a-model'));
    final second = tester.getCenter(find.text('b-model'));
    final gesture = await tester.startGesture(first);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    final step = (second.dy - first.dy) * 1.5 / 10;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, step));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(settings.getProviderConfig('P').models, ['b-model', 'a-model']);
  });
}
