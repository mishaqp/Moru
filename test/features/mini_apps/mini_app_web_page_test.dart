import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/keep_alive.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/mini_app_web_host.dart';
import 'package:Kelivo/features/mini_apps/pages/mini_app_web_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';

void main() {
  late Directory temp;
  late SettingsProvider settings;
  late MiniAppWebHost host;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-web-page-');
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    host = MiniAppWebHost(
      store: MiniAppStore(root: () async => Directory(p.join(temp.path, 'i'))),
      keepAlive: ProcessKeepAlive(
        channel: const MethodChannel('test.keep_alive.page'),
      ),
      localAddresses: () async => const [],
    );
  });
  tearDown(() async {
    host.dispose();
    settings.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MiniAppWebPage(host: host),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a password is made up on first open and an invalid port is '
      'refused without starting', (tester) async {
    await pump(tester);
    expect(settings.miniAppWebPasswordEnabled, isTrue);
    expect(settings.miniAppWebPassword, hasLength(8));
    expect(find.text('Web server'), findsOneWidget);
    expect(find.text('Only this phone'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('mini-app-web-port')),
      '80',
    );
    await tester.tap(find.byKey(const ValueKey('mini-app-web-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('The port must be from 1024 to 65535.'), findsOneWidget);
    expect(host.running, isFalse);

    // Without a password the field goes away.
    await tester.tap(find.text('Require a password'));
    await tester.pumpAndSettle();
    expect(settings.miniAppWebPasswordEnabled, isFalse);
    expect(find.byKey(const ValueKey('mini-app-web-password')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
