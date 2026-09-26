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

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-apps-page-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Future<void> install(String id, String name, String description) async {
    final dir = Directory(p.join(temp.path, 'src', id))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({'id': id, 'name': name, 'description': description}),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync('<p>x</p>');
    await store.install(dir);
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
}
