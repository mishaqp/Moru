import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/mini_apps/pages/mini_app_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';
import '../../support/fake_webview_platform.dart';

class _PageController extends FakeWebViewController {
  _PageController(super.params);

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage message) callback,
  ) async {}
}

class _PagePlatform extends FakeWebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _PageController(params);
    FakeWebViewPlatform.lastCreated = controller;
    FakeWebViewPlatform.onCreated?.call(controller);
    return controller;
  }
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniApp app;
  late SettingsProvider settings;
  late AssistantProvider assistants;
  late EnvironmentProvider environment;

  setUp(() async {
    WebViewPlatform.instance = _PagePlatform();
    temp = await Directory.systemTemp.createTemp('mini-app-page-storage-');
    store = MiniAppStore(root: () async => Directory('${temp.path}/installed'));
    final source = Directory('${temp.path}/source')..createSync();
    File(
      '${source.path}/moru-app.json',
    ).writeAsStringSync(jsonEncode({'id': 'game', 'name': 'Game'}));
    File('${source.path}/index.html').writeAsStringSync('<p>Game</p>');
    app = (await store.install(source)).app;
    final settingsPreferences = createBusinessTestPreferences();
    final assistantPreferences = createBusinessTestPreferences();
    final environmentPreferences = createBusinessTestPreferences();
    settings = SettingsProvider(settingsPreferences);
    assistants = AssistantProvider(preferences: assistantPreferences);
    environment = EnvironmentProvider(preferences: environmentPreferences);
    await Future.wait([settings.loaded, assistants.loaded, environment.loaded]);
  });

  tearDown(() async {
    FakeWebViewPlatform.onCreated = null;
    settings.dispose();
    assistants.dispose();
    environment.dispose();
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: assistants),
        ChangeNotifierProvider.value(value: environment),
        ChangeNotifierProvider(create: (_) => WorkspaceRuntimeProvider()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MiniAppPage(app: app, store: store),
      ),
    ),
  );

  Future<void> tick(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }

  Future<void> remove(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tick(tester);
  }

  testWidgets('startup waits for the navigation delegate before loading', (
    tester,
  ) async {
    final ready = Completer<void>();
    FakeWebViewPlatform.onCreated = (controller) {
      controller.onSetNavigationDelegate = () => ready.future;
    };
    await pump(tester);
    final controller = FakeWebViewPlatform.lastCreated!;
    // Complete the store/server IO while the native delegate is still pending.
    for (var i = 0; i < 10; i++) {
      await tick(tester);
    }
    expect(controller.loadedUrls, isEmpty);
    ready.complete();
    for (var i = 0; i < 100 && controller.loadedUrls.isEmpty; i++) {
      await tick(tester);
    }
    expect(controller.loadedUrls.single, startsWith('https://moru-miniapp-'));
    expect(controller.delegatesSet, 1);
    expect(tester.takeException(), isNull);
    await remove(tester);
  });

  testWidgets('failed startup is logged without loading app code', (
    tester,
  ) async {
    FakeWebViewPlatform.onCreated = (controller) {
      controller.onSetNavigationDelegate = () async {
        throw StateError('Storage interceptor setup failed');
      };
    };
    await pump(tester);
    for (var i = 0; i < 10; i++) {
      await tick(tester);
    }
    expect(FakeWebViewPlatform.lastCreated!.loadedUrls, isEmpty);
    // The store queue belongs to the fake clock, so keep pumping instead of
    // awaiting that queue from runAsync until its atomic write completes.
    final journal = File('${app.directory}/errors.json');
    for (var i = 0; i < 100 && !journal.existsSync(); i++) {
      await tick(tester);
    }
    final errors = jsonDecode(journal.readAsStringSync()) as List;
    expect(
      (errors.single as Map)['message'],
      contains('Storage interceptor setup failed'),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await remove(tester);
  });
}
