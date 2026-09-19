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
  }) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;

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

  testWidgets('lists all 15 actions enabled by default', (tester) async {
    await pumpPage(tester);

    expect(find.byType(IosSwitch), findsNWidgets(15));
    expect(find.text('Run JavaScript'), findsOneWidget);
    expect(find.text('Click'), findsOneWidget);
    for (final s in tester.widgetList<IosSwitch>(find.byType(IosSwitch))) {
      expect(s.value, isTrue);
    }
  });

  testWidgets('turning off eval_js persists and unchecks its switch', (
    tester,
  ) async {
    final settings = await pumpPage(tester);

    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Run JavaScript'),
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
              of: find.text('Run JavaScript'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(IosSwitch),
      ),
    );
    expect(toggled.value, isFalse);
  });

  testWidgets('shows Russian labels under a Russian locale', (tester) async {
    await pumpPage(tester, locale: const Locale('ru'));

    expect(find.text('Выполнить JavaScript'), findsOneWidget);
    expect(find.text('Нажать'), findsOneWidget);
  });
}
