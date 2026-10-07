import 'dart:io';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/logging/context_logger.dart';
import 'package:Kelivo/core/services/logging/flutter_logger.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';
import 'package:Kelivo/features/settings/pages/log_viewer_page.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/features/settings/pages/settings_search_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/l10n/app_localizations_ru.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';
import 'package:Kelivo/shared/widgets/ios_settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/business_test_harness.dart';

class _LogPathProvider extends PathProviderPlatform {
  _LogPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Future<void> _settlePage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(tester.binding.hasScheduledFrame, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = AppLocalizationsRu();
  late Directory root;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    // Initialize the write queue outside the widget tests' fake clocks.
    await ContextLogger.setEnabled(true);
    await ContextLogger.setEnabled(false);
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('moru-log-settings-');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _LogPathProvider(root.path);
  });

  tearDown(() async {
    await RequestLogger.setEnabled(false);
    await ContextLogger.setEnabled(false);
    await FlutterLogger.setEnabled(false);
    PathProviderPlatform.instance = previousPathProvider;
    await root.delete(recursive: true);
  });

  Future<void> pumpPage(
    WidgetTester tester,
    SettingsProvider settings,
    Widget page, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await _settlePage(tester);
  }

  testWidgets(
    'Logs stays accessible with all three loggers disabled',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setRequestLogEnabled(false);
      await settings.setContextLogEnabled(false);
      await settings.setFlutterLogEnabled(false);

      try {
        await pumpPage(
          tester,
          settings,
          const SettingsPage(),
          size: const Size(390, 4000),
        );
        final logs = find.text(l10n.settingsPageLogs);
        expect(logs, findsOneWidget);
        await tester.tap(logs);
        await _settlePage(tester);
        expect(find.byType(LogViewerPage), findsOneWidget);
        expect(find.byTooltip(l10n.logSettingsTitle), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'settings search finds Logs with all three loggers disabled',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setRequestLogEnabled(false);
      await settings.setContextLogEnabled(false);
      await settings.setFlutterLogEnabled(false);
      try {
        await pumpPage(
          tester,
          settings,
          SettingsSearchPage(onColorMode: () {}),
        );
        await tester.enterText(find.byType(TextField), l10n.settingsPageLogs);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('logs')), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final smallScreen in [false, true]) {
    testWidgets(
      'log switches persist and apply to loggers (small screen: $smallScreen)',
      (tester) async {
        final preferences = createBusinessTestPreferences(
          localInitial: {'flutter_log_enabled_v1': true},
        );
        await preferences.load();
        await preferences.setBool('request_log_enabled_v1', true);
        await preferences.setBool('context_log_enabled_v1', true);
        final settings = SettingsProvider(preferences);
        addTearDown(settings.dispose);
        await settings.loaded;

        try {
          await pumpPage(
            tester,
            settings,
            const LogViewerPage(),
            size: smallScreen ? const Size(320, 568) : const Size(390, 844),
            textScale: smallScreen ? 1.3 : 1,
          );
          await tester.tap(find.byTooltip(l10n.logSettingsTitle));
          await tester.pumpAndSettle();
          expect(find.byType(IosSwitchRow), findsNWidgets(3));

          final titles = [
            l10n.requestLogSettingTitle,
            l10n.contextLogSettingTitle,
            l10n.flutterLogSettingTitle,
          ];
          final subtitles = [
            l10n.requestLogSettingSubtitle,
            l10n.contextLogSettingSubtitle,
            l10n.flutterLogSettingSubtitle,
          ];
          final scrollable = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          );
          for (final enabled in [false, true]) {
            for (var i = 0; i < 3; i++) {
              final row = find.ancestor(
                of: find.text(titles[i]),
                matching: find.byType(IosSwitchRow),
              );
              final toggle = find.descendant(
                of: row,
                matching: find.byType(IosSwitch),
              );
              await tester.ensureVisible(toggle);
              await tester.pumpAndSettle();
              expect(find.text(titles[i]), findsOneWidget);
              expect(find.text(subtitles[i]), findsOneWidget);
              expect(tester.widget<IosSwitch>(toggle).value, !enabled);
              await tester.tap(toggle);
              await tester.pump();
              await tester.runAsync(preferences.flushPendingWrites);
              await tester.pumpAndSettle();

              expect(
                [
                  settings.requestLogEnabled,
                  settings.contextLogEnabled,
                  settings.flutterLogEnabled,
                ][i],
                enabled,
              );
              expect(
                [
                  RequestLogger.enabled,
                  ContextLogger.enabled,
                  FlutterLogger.enabled,
                ][i],
                enabled,
              );
              expect(tester.widget<IosSwitch>(toggle).value, enabled);
            }
            expect(preferences.getBool('request_log_enabled_v1'), enabled);
            expect(preferences.getBool('context_log_enabled_v1'), enabled);
            final local = await SharedPreferences.getInstance();
            expect(local.getBool('flutter_log_enabled_v1'), enabled);
          }

          await tester.scrollUntilVisible(
            find.text(l10n.logSettingsMaxSize),
            200,
            scrollable: scrollable,
          );
          expect(
            find.text(l10n.logSettingsMaxSize).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
