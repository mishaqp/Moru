import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/settings/widgets/sidebar_appearance_preview.dart';
import 'package:Kelivo/features/settings/pages/appearance_settings_page.dart';
import 'package:Kelivo/features/settings/pages/display_settings_page.dart';
import 'package:Kelivo/features/settings/search/settings_search_index.dart';
import 'package:Kelivo/features/settings/widgets/settings_search_target.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/l10n/app_localizations_en.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../support/business_test_harness.dart';

class _AppearancePaths extends PathProviderPlatform {
  _AppearancePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAppearance(
    WidgetTester tester,
    SettingsProvider settings, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    String? targetLabel,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: SettingsSearchTarget(
            label: targetLabel,
            child: const AppearanceSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<SettingsProvider> createSettings() async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    addTearDown(settings.dispose);
    return settings;
  }

  testWidgets('Display opens Appearance with a live preview and two tabs', (
    tester,
  ) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DisplaySettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Chat window'), findsOneWidget);
    expect(find.text('Sidebar'), findsOneWidget);
    expect(find.text('This is a user message'), findsOneWidget);
    expect(find.text('Same for light and dark'), findsOneWidget);
  });

  testWidgets(
    'Sidebar has a live panel preview and does not alter the chat background',
    (tester) async {
      final settings = await createSettings();
      await pumpAppearance(tester, settings);
      final before = settings.chatAppearance;
      await tester.tap(find.text('Sidebar'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(SidebarAppearancePreview), findsOneWidget);
      expect(
        find.byKey(const ValueKey('appearanceSidebarPreviewCurrentCard')),
        findsOneWidget,
      );
      expect(find.text('Sidebar background'), findsOneWidget);
      expect(find.text('Same as chat'), findsOneWidget);
      expect(settings.chatAppearance, before);
      expect(find.byKey(const ValueKey('appearanceSource.none')), findsNothing);
    },
  );

  testWidgets('filter draft previews live and persists only at drag end', (
    tester,
  ) async {
    final settings = await createSettings();
    await pumpAppearance(tester, settings);
    final slider = tester.widget<SfSlider>(
      find.byKey(const ValueKey('appearanceBrightness')),
    );
    slider.onChanged!(.45);
    await tester.pump();
    expect(settings.chatAppearance.light.brightness, 1);
    expect(
      tester
          .widget<ChatBackground>(find.byType(ChatBackground))
          .configuration
          .brightness,
      .45,
    );
    slider.onChangeEnd!(.45);
    await tester.pump();
    expect(settings.chatAppearance.light.brightness, .45);
    expect(settings.chatAppearance.dark.brightness, .45);
  });

  testWidgets('separate dark adjustment preserves the light background', (
    tester,
  ) async {
    final settings = await createSettings();
    await pumpAppearance(tester, settings);
    final shared = find.byKey(const ValueKey('appearanceShared'));
    await tester.ensureVisible(shared);
    await tester.tap(shared);
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.chatAppearance.shared, isFalse);

    final dark = find.text('Dark');
    await tester.ensureVisible(dark);
    await tester.tap(dark);
    await tester.pump(const Duration(milliseconds: 250));
    final slider = tester.widget<SfSlider>(
      find.byKey(const ValueKey('appearanceSaturation')),
    );
    slider.onChanged!(.3);
    await tester.pump();
    slider.onChangeEnd!(.3);
    await tester.pump();
    expect(settings.chatAppearance.dark.saturation, .3);
    expect(settings.chatAppearance.light.saturation, 1);
  });

  testWidgets('video fit choices exclude Tile', (tester) async {
    final settings = await createSettings();
    await settings.setChatAppearance(
      const ChatAppearanceSettings(
        light: ChatBackgroundSettings(type: ChatBackgroundType.video),
      ),
    );
    await pumpAppearance(tester, settings);
    final fit = find.byKey(const ValueKey('appearanceFit'));
    await tester.ensureVisible(fit);
    await tester.tap(fit);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Contain'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);
    expect(find.text('Tile'), findsNothing);
  });

  testWidgets('sharing toggle roundtrip retains both profiles and dark media', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('appearance-toggle-'),
    ))!;
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _AppearancePaths(root.path);
    SandboxPathResolver.debugSetDirs(docsDir: root.path);
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      SandboxPathResolver.debugSetDirs();
      await root.delete(recursive: true);
    });
    final darkFile = File(
      '${root.path}/images/chat_backgrounds/chat_background_dark.gif',
    );
    await tester.runAsync(() async {
      await darkFile.parent.create(recursive: true);
      await darkFile.writeAsBytes(
        base64Decode(
          'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
        ),
      );
    });
    final settings = await createSettings();
    const split = ChatAppearanceSettings(
      shared: false,
      light: ChatBackgroundSettings(brightness: .7),
      dark: ChatBackgroundSettings(
        type: ChatBackgroundType.gif,
        path: 'kelivo-file:///images/chat_backgrounds/chat_background_dark.gif',
        saturation: .2,
      ),
    );
    await settings.setChatAppearance(split);
    await pumpAppearance(tester, settings);
    final shared = find.byKey(const ValueKey('appearanceShared'));
    await tester.ensureVisible(shared);
    await tester.tap(shared);
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.chatAppearance.light, split.light);
    expect(settings.chatAppearance.dark, split.dark);
    expect(await tester.runAsync(darkFile.exists), isTrue);
    await tester.tap(shared);
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.chatAppearance, split);
    expect(await tester.runAsync(darkFile.exists), isTrue);
  });

  testWidgets('cover moves with the finger and images can tile', (
    tester,
  ) async {
    final settings = await createSettings();
    await settings.setChatAppearance(
      const ChatAppearanceSettings(
        light: ChatBackgroundSettings(type: ChatBackgroundType.image),
      ),
    );
    await pumpAppearance(tester, settings);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('appearancePreview'))),
    );
    await gesture.moveBy(const Offset(48, 0));
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(settings.chatAppearance.light.focusX, lessThan(0));
    expect(settings.chatAppearance.light.focusY, lessThan(0));
    expect(settings.chatAppearance.light, settings.chatAppearance.dark);

    final fit = find.byKey(const ValueKey('appearanceFit'));
    await tester.ensureVisible(fit);
    await tester.tap(fit);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Tile'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(settings.chatAppearance.light.fit, ChatBackgroundFit.tile);
  });

  testWidgets('contain moves with the finger using positive alignment', (
    tester,
  ) async {
    final settings = await createSettings();
    await settings.setChatAppearance(
      const ChatAppearanceSettings(
        light: ChatBackgroundSettings(
          type: ChatBackgroundType.image,
          fit: ChatBackgroundFit.contain,
        ),
      ),
    );
    await pumpAppearance(tester, settings);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('appearancePreview'))),
    );
    await gesture.moveBy(const Offset(48, 0));
    await gesture.moveBy(const Offset(40, 20));
    await gesture.up();
    await tester.pump();
    expect(settings.chatAppearance.light.focusX, greaterThan(0));
    expect(settings.chatAppearance.light.focusY, greaterThan(0));
  });

  test('appearance and former overlay-opacity searches use Appearance', () {
    final index = SettingsSearchIndex(AppLocalizationsEn());
    expect(
      index.search('Appearance').first.destination,
      SettingsSearchDestination.appearance,
    );
    expect(
      index.search('Chat Background Overlay Opacity').first.destination,
      SettingsSearchDestination.appearance,
    );
    expect(
      index.search('video').map((item) => item.destination),
      contains(SettingsSearchDestination.appearance),
    );
  });

  testWidgets('search reveals the moved overlay-opacity control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await createSettings();
    const label = 'Chat Background Overlay Opacity';
    await pumpAppearance(tester, settings, targetLabel: label);
    final rect = tester.getRect(find.text(label));
    expect(rect.top, greaterThan(0));
    expect(rect.bottom, lessThan(780));
  });

  testWidgets('reset clears appearance and preserves message style', (
    tester,
  ) async {
    final settings = await createSettings();
    await settings.setChatMessageBackgroundStyle(
      ChatMessageBackgroundStyle.solid,
    );
    await settings.setChatAppearance(
      const ChatAppearanceSettings(
        shared: false,
        light: ChatBackgroundSettings(brightness: .4),
        dark: ChatBackgroundSettings(saturation: .2),
      ),
    );
    await pumpAppearance(tester, settings);
    await tester.tap(find.byKey(const ValueKey('appearanceReset')));
    await tester.pump();
    expect(settings.chatAppearance, const ChatAppearanceSettings());
    expect(
      settings.chatMessageBackgroundStyle,
      ChatMessageBackgroundStyle.solid,
    );
  });

  for (final size in [
    const Size(360, 780),
    const Size(780, 360),
    const Size(1024, 768),
  ]) {
    testWidgets('Russian appearance fits at 1.3 text scale in $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = await createSettings();
      await pumpAppearance(
        tester,
        settings,
        locale: const Locale('ru'),
        textScale: 1.3,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('appearanceSaturation')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
