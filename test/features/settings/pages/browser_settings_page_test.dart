import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/browser_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsProvider> pumpPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Set<String> disabled = const {},
  }) async {
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    for (final id in disabled) {
      await settings.setBrowserActionEnabled(id, false);
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const BrowserSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('lists all 15 actions across 4 groups, enabled by default', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(IosSwitch), findsNWidgets(15));
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Read page'), findsOneWidget);
    expect(find.text('Interaction'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Run code on the page'), findsOneWidget);
    expect(find.text('Click'), findsOneWidget);
    for (final s in tester.widgetList<IosSwitch>(find.byType(IosSwitch))) {
      expect(s.value, isTrue);
    }
    // Every group starts fully enabled.
    expect(find.text('5 of 5 enabled'), findsOneWidget); // Navigation
    expect(find.text('3 of 3 enabled'), findsNWidgets(2)); // Read page + n/a
    expect(find.text('4 of 4 enabled'), findsOneWidget); // Interaction
  });

  testWidgets('turning off eval_js persists, unchecks its switch, and '
      'updates its group count', (tester) async {
    final settings = await pumpPage(tester);

    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Run code on the page'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(IosSwitch),
      ),
    );
    await tester.pumpAndSettle();

    expect(settings.disabledBrowserActions, {'eval_js'});
    final toggled = tester.widget<IosSwitch>(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Run code on the page'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(IosSwitch),
      ),
    );
    expect(toggled.value, isFalse);
    // eval_js lives in the "Advanced" group (3 actions).
    expect(find.text('2 of 3 enabled'), findsOneWidget);
  });

  testWidgets(
    'a previously-disabled action still reads as disabled under the new '
    'grouped layout',
    (tester) async {
      await pumpPage(tester, disabled: {'click', 'submit'});

      final clickSwitch = tester.widget<IosSwitch>(
        find.descendant(
          of: find
              .ancestor(of: find.text('Click'), matching: find.byType(Row))
              .first,
          matching: find.byType(IosSwitch),
        ),
      );
      expect(clickSwitch.value, isFalse);
      // Interaction group: click, type, submit, press_key -- 2 disabled.
      expect(find.text('2 of 4 enabled'), findsOneWidget);
    },
  );

  testWidgets('shows Russian labels under a Russian locale', (tester) async {
    await pumpPage(tester, locale: const Locale('ru'));

    expect(find.text('Выполнить код на странице'), findsOneWidget);
    expect(find.text('Нажать'), findsOneWidget);
    expect(find.text('Навигация'), findsOneWidget);
  });

  testWidgets('reflects trust mode read-only, with no toggle on this page', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.textContaining('Full trust is currently OFF'), findsOneWidget);
    // No switch on this page controls trust -- only the 15 per-action ones.
    expect(find.byType(IosSwitch), findsNWidgets(15));
  });
}
