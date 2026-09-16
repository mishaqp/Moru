"""Temporary preparation step; all tests remain enabled."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
assert (root / 'lib/l10n/app_ru.arb').is_file(), 'Initial catalog must already be committed'
finalizer = Path(__file__).with_name('finalize.py')
s = finalizer.read_text()
s = s.replace('import runpy\n', '')
s = s.replace("runpy.run_path(str(Path(__file__).with_name('apply.py')))\n", '')
finalizer.write_text(s)

p = root / 'test/features/settings/search/settings_search_widgets_test.dart'
s = p.read_text()
old = '    double textScale = 1,\n  }) async {'
new = "    double textScale = 1,\n    Locale locale = const Locale('en', 'US'),\n  }) async {"
assert s.count(old) == 1
s = s.replace(old, new, 1)
old = '    await settings.loaded;\n    addTearDown(settings.dispose);'
new = '    await settings.loaded;\n    await settings.setAppLocale(locale);\n    addTearDown(settings.dispose);'
assert s.count(old) == 1
s = s.replace(old, new, 1)
anchor = "  testWidgets('search is hidden initially, pulls into view, and scrolls away', ("
assert s.count(anchor) == 1
regression = '''  testWidgets('Russian Android search opens the language setting and preserves its query', (tester) async {
    await pump(
      tester,
      const SettingsSearchPage(onColorMode: _noop),
      platform: TargetPlatform.android,
      locale: const Locale('ru'),
    );
    const query = 'Язык приложения';
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('displaySettingsPageLanguageTitle'));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.text(query).hitTestable(), findsOneWidget);
    expect(find.text('Русский').hitTestable(), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, query);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

'''
s = s.replace(anchor, regression + anchor, 1)
p.write_text(s)

print('Preserved initial formatted localization; English assumptions are explicit and Russian Android search has its own regression.')
