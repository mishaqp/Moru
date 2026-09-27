import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/pages/mini_apps_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  late DateTime clock;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-apps-page-');
    clock = DateTime(2026, 9, 1, 10);
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
      // Each publish a minute later, so versions have distinct times.
      now: () => clock = clock.add(const Duration(minutes: 1)),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Future<void> install(
    String id,
    String name,
    String description, {
    String html = '<p>x</p>',
  }) async {
    final dir = Directory(p.join(temp.path, 'src', id))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({'id': id, 'name': name, 'description': description}),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync(html);
    await store.install(dir);
  }

  /// Lets real file IO run until [done], delivering its results.
  Future<void> ioUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester) async {
    // Real file IO only finishes outside the fake clock, so read the apps
    // before the page asks for them.
    await tester.runAsync(store.load);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MiniAppsPage(store: store),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('without apps the page explains how to make one', (tester) async {
    await pump(tester);
    expect(find.textContaining('No apps yet'), findsOneWidget);
    expect(find.byTooltip('Import'), findsOneWidget);
  });

  testWidgets('the app menu offers sharing', (tester) async {
    await tester.runAsync(() => install('water', 'Water', ''));
    await pump(tester);
    await tester.longPress(find.byKey(const ValueKey('mini-app-water')));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('apps are listed and can be deleted from their menu', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await install('water', 'Water', 'Track water');
      await install('notes', 'Notes', '');
    });
    await pump(tester);

    expect(find.text('Water'), findsOneWidget);
    expect(find.text('Track water'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    // The letter icon stands in for apps without an SVG.
    expect(find.text('W'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('mini-app-water')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Water”?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    // The deletion is real file IO: let it run, then deliver its result.
    for (var i = 0; i < 100 && store.byId('water') != null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(store.byId('water'), isNull);
    expect(find.text('Water'), findsNothing);
    expect(find.text('Notes'), findsOneWidget);
  });

  testWidgets('the error log shows, copies and clears the journal', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await install('water', 'Water', '');
      await store.logError('water', 'console: x is not defined');
    });
    await pump(tester);

    await tester.longPress(find.byKey(const ValueKey('mini-app-water')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error log'));
    await ioUntil(
      tester,
      () => find.text('console: x is not defined').evaluate().isNotEmpty,
    );
    expect(find.text('Copy all'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await ioUntil(
      tester,
      () => find.text('No errors recorded.').evaluate().isNotEmpty,
    );
    // The journal file is gone. (Awaiting the store here would wait on a
    // future of the test's fake zone.)
    final journal = File(p.join(store.byId('water')!.directory, 'errors.json'));
    expect(await tester.runAsync(journal.exists), isFalse);
  });

  testWidgets('versions roll the app back to earlier code', (tester) async {
    await tester.runAsync(() async {
      await install('water', 'Water', '', html: '<p>v1</p>');
      await install('water', 'Water', '', html: '<p>v2</p>');
    });
    await pump(tester);

    await tester.longPress(find.byKey(const ValueKey('mini-app-water')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Versions'));
    await ioUntil(
      tester,
      () => find.text('Roll back “Water”').evaluate().isNotEmpty,
    );
    expect(find.textContaining('last 5 versions'), findsOneWidget);

    final first = (await tester.runAsync(
      () => store.versions('water'),
    ))!.single.updatedAt;
    await tester.tap(find.textContaining('2026'));
    await ioUntil(tester, () => store.byId('water')!.updatedAt == first);
    expect(find.text('Roll back “Water”'), findsNothing);
    // Let the confirmation snack bar time out.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final entry = File(store.byId('water')!.entryPath);
    expect(await tester.runAsync(entry.readAsString), contains('v1'));
  });
}
