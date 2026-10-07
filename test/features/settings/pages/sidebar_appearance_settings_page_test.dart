import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/models/sidebar_shortcut.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/sidebar_omni_parts.dart';
import 'package:Kelivo/features/settings/pages/appearance_settings_page.dart';
import 'package:Kelivo/features/settings/search/settings_search_index.dart';
import 'package:Kelivo/features/settings/search/settings_search_navigation.dart';
import 'package:Kelivo/features/settings/widgets/sidebar_appearance_preview.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../support/business_test_harness.dart';

void main() {
  Future<SettingsProvider> settings() async {
    final harness = await createBusinessTestHarness();
    final result = SettingsProvider(harness.preferences);
    await result.loaded;
    addTearDown(result.dispose);
    return result;
  }

  Future<void> pump(
    WidgetTester tester,
    SettingsProvider settings, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    Widget? home,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home ?? const AppearanceSettingsPage(initialTab: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SidebarAppearancePreview preview(WidgetTester tester) => tester
      .widget<SidebarAppearancePreview>(find.byType(SidebarAppearancePreview));

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void expectInsideClip(Rect content, Rect clip, String label) {
    // getRect includes the FittedBox paint transform, so these bounds check
    // what the preview actually displays rather than the unscaled layout.
    const roundingTolerance = .001;
    expect(content.isEmpty, isFalse, reason: label);
    expect(
      content.left,
      greaterThanOrEqualTo(clip.left - roundingTolerance),
      reason: '$label left edge',
    );
    expect(
      content.top,
      greaterThanOrEqualTo(clip.top - roundingTolerance),
      reason: '$label top edge',
    );
    expect(
      content.right,
      lessThanOrEqualTo(clip.right + roundingTolerance),
      reason: '$label right edge',
    );
    expect(
      content.bottom,
      lessThanOrEqualTo(clip.bottom + roundingTolerance),
      reason: '$label bottom edge',
    );
  }

  testWidgets(
    'sidebar preview follows the actual dark theme after editing the light chat',
    (tester) async {
      final prefs = await settings();
      const dark = ChatBackgroundSettings(
        type: ChatBackgroundType.gradient,
        gradientAnimated: false,
        brightness: .4,
      );
      const chat = ChatAppearanceSettings(shared: false, dark: dark);
      await prefs.setChatAppearance(chat);
      await pump(
        tester,
        prefs,
        brightness: Brightness.dark,
        home: const AppearanceSettingsPage(),
      );
      await tester.ensureVisible(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sidebar'));
      await tester.pumpAndSettle();
      expect(preview(tester).theme.brightness, Brightness.dark);
      expect(preview(tester).backgroundConfiguration, dark);
      expect(prefs.chatAppearance, chat);
    },
  );

  testWidgets(
    'sidebar edits keep the real preview visible and save at drag end',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await settings();
      await pump(tester, prefs);
      final beforeChat = prefs.chatAppearance;
      final sliderFinder = find.byKey(
        const ValueKey('appearanceSidebarPhoneWidth'),
      );
      await tester.ensureVisible(sliderFinder);
      await tester.pumpAndSettle();
      final oldWidth = tester
          .getSize(find.byKey(const ValueKey('appearanceSidebarPreviewPanel')))
          .width;
      final slider = tester.widget<SfSlider>(sliderFinder);
      final rect = tester.getRect(sliderFinder);
      final fraction =
          ((slider.value as double) - slider.min) / (slider.max - slider.min);
      final gesture = await tester.startGesture(
        Offset(rect.left + 16 + (rect.width - 32) * fraction, rect.center.dy),
      );
      await gesture.moveBy(const Offset(32, 0));
      await tester.pump();
      expect(prefs.sidebarAppearance.phoneWidthPercent, 80);
      expect(preview(tester).appearance.phoneWidthPercent, greaterThan(80));
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('appearanceSidebarPreviewPanel')),
            )
            .width,
        greaterThan(oldWidth),
      );
      expect(
        find.byKey(const ValueKey('appearanceSidebarPreview')).hitTestable(),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(prefs.sidebarAppearance.phoneWidthPercent, greaterThan(80));
      expect(prefs.chatAppearance, beforeChat);
    },
  );

  testWidgets(
    'sidebar sources, metadata, density and grouping update shared cards',
    (tester) async {
      final prefs = await settings();
      await pump(tester, prefs);
      final chat = prefs.chatAppearance;
      await tap(tester, 'appearanceSidebarMode.custom');
      await tap(tester, 'appearanceSidebarSource.gradient');
      expect(
        preview(tester).backgroundConfiguration.type,
        ChatBackgroundType.gradient,
      );
      expect(prefs.chatAppearance, chat);
      await tap(tester, 'appearanceSidebarMode.theme');
      expect(
        preview(tester).backgroundConfiguration.type,
        ChatBackgroundType.none,
      );
      await tap(tester, 'appearanceSidebarDensity.compact');
      for (final key in ['Timestamp', 'Assistant', 'Model', 'LastPreview']) {
        await tap(tester, 'appearanceSidebar$key');
      }
      await tap(tester, 'appearanceSidebarGrouping.assistant');
      final card = tester.widget<SidebarConversationCard>(
        find.byKey(const ValueKey('appearanceSidebarPreviewCurrentCard')),
      );
      expect(card.appearance.showTimestamp, isTrue);
      expect(card.appearance.showAssistant, isTrue);
      expect(card.appearance.showModel, isTrue);
      expect(card.appearance.showPreview, isTrue);
      expect(card.appearance.density, SidebarDensity.compact);
      expect(card.appearance.grouping, SidebarGrouping.assistant);
      await tap(tester, 'appearanceSidebarThumbnails');
      expect(prefs.sidebarThumbnails, isFalse);
      expect(preview(tester).showThumbnails, isFalse);
    },
  );

  testWidgets('dock switches and drag handles persist their order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await settings();
    await pump(tester, prefs);
    await tap(tester, 'appearanceSidebarDock.memory');
    expect(
      prefs.sidebarAppearance.dockItems,
      isNot(contains(SidebarDockItem.memory)),
    );
    final first = find.byKey(const ValueKey('appearanceSidebarDock.profile'));
    final second = find.byKey(const ValueKey('appearanceSidebarDock.settings'));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    final handle = find.descendant(
      of: first,
      matching: find.byType(ReorderableDragStartListener),
    );
    final start = tester.getCenter(handle);
    final end = tester.getCenter(second);
    final gesture = await tester.startGesture(start);
    for (double delta = 8; delta <= end.dy - start.dy + 5; delta += 8) {
      await gesture.moveTo(start + Offset(0, delta));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(prefs.sidebarAppearance.dockItems.take(2), [
      SidebarDockItem.settings,
      SidebarDockItem.profile,
    ]);
  });

  testWidgets(
    'pinned shortcut order changes and sidebar reset preserves targets and chat',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await settings();
      const first = SidebarShortcut.webPage(
        'https://first.example',
        'First page',
      );
      const second = SidebarShortcut.webPage(
        'https://second.example',
        'Second page',
      );
      await prefs.setSidebarShortcuts([first, second]);
      await prefs.setSidebarAppearance(
        const SidebarAppearanceSettings(showModel: true, cardRadius: 24),
      );
      await prefs.setSidebarThumbnails(false);
      await prefs.setChatAppearance(
        const ChatAppearanceSettings(
          light: ChatBackgroundSettings(brightness: .4),
        ),
      );
      final chat = prefs.chatAppearance;
      await pump(tester, prefs);
      final row = find.byKey(
        ValueKey('appearanceSidebarShortcut.${first.encode()}'),
      );
      final nextRow = find.byKey(
        ValueKey('appearanceSidebarShortcut.${second.encode()}'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final handle = find.descendant(
        of: row,
        matching: find.byType(ReorderableDragStartListener),
      );
      final start = tester.getCenter(handle);
      final end = tester.getCenter(nextRow);
      final gesture = await tester.startGesture(start);
      for (double delta = 8; delta <= end.dy - start.dy + 5; delta += 8) {
        await gesture.moveTo(start + Offset(0, delta));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(prefs.sidebarShortcuts, [second, first]);
      await tester.tap(find.byKey(const ValueKey('appearanceReset')));
      await tester.pumpAndSettle();
      expect(prefs.sidebarAppearance, const SidebarAppearanceSettings());
      expect(prefs.sidebarThumbnails, isTrue);
      expect(prefs.sidebarShortcuts, [second, first]);
      expect(prefs.chatAppearance, chat);
    },
  );

  testWidgets(
    'a failed sidebar reset keeps the saved draft and shows an error',
    (tester) async {
      final harness = await createBusinessTestHarness();
      final prefs = _FailingResetSettings(harness.preferences);
      await prefs.loaded;
      addTearDown(prefs.dispose);
      const saved = SidebarAppearanceSettings(showModel: true, cardRadius: 24);
      await prefs.setSidebarAppearance(saved);
      await pump(tester, prefs);
      await tester.tap(find.byKey(const ValueKey('appearanceReset')));
      await tester.pumpAndSettle();
      expect(preview(tester).appearance, saved);
      expect(
        find.text('Could not save appearance. Try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sidebar search opens its tab and reveals the requested control',
    (tester) async {
      final prefs = await settings();
      final item = SettingsSearchIndex(
        AppLocalizationsEn(),
      ).search('Message timestamp').first;
      expect(item.id, 'appearanceSidebarTimestamp');
      await pump(
        tester,
        prefs,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openMobileSettingsSearchResult(context, item),
              child: const Text('Open result'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();
      expect(find.byType(SidebarAppearancePreview), findsOneWidget);
      expect(
        find.byKey(const ValueKey('appearanceSidebarTimestamp')).hitTestable(),
        findsOneWidget,
      );
      final thumbnail = SettingsSearchIndex(
        AppLocalizationsEn(),
      ).search('Image previews in the chat list').first;
      expect(thumbnail.destination, SettingsSearchDestination.appearance);
      expect(thumbnail.id, 'displaySettingsPageSidebarThumbnailsTitle');
    },
  );

  for (final size in [
    const Size(780, 360),
    const Size(360, 780),
    const Size(360, 600),
  ]) {
    for (final pinned in [false, true]) {
      for (final density in SidebarDensity.values) {
        testWidgets(
          'preview fully displays current date-grouped card at 1.3 in '
          '$size, ${density.name}, pinned=$pinned',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final prefs = await settings();
            await prefs.setSidebarAppearance(
              SidebarAppearanceSettings(
                density: density,
                grouping: SidebarGrouping.date,
                showTimestamp: true,
                showAssistant: true,
                showModel: true,
                showPreview: true,
              ),
            );
            if (pinned) {
              await prefs.setSidebarShortcuts(const [
                SidebarShortcut.webPage('https://first.example', 'First page'),
                SidebarShortcut.webPage(
                  'https://second.example',
                  'Second page',
                ),
              ]);
            }
            await pump(
              tester,
              prefs,
              textScale: 1.3,
              locale: const Locale('ru'),
            );
            final card = find.byKey(
              const ValueKey('appearanceSidebarPreviewCurrentCard'),
            );
            expect(
              tester.widget<SidebarConversationCard>(card).isCurrent,
              isTrue,
            );
            final scene = tester.getRect(
              find.byKey(
                const ValueKey('appearanceSidebarPreviewCardViewport'),
              ),
            );
            final panel = tester.getRect(
              find.byKey(const ValueKey('appearanceSidebarPreviewPanel')),
            );
            final previewClip = tester.getRect(
              find.byType(SidebarAppearancePreview),
            );
            expectInsideClip(scene, panel, 'card viewport');
            expectInsideClip(panel, previewClip, 'sidebar panel');
            expectInsideClip(tester.getRect(card), scene, 'current card');
            final l = AppLocalizations.of(tester.element(card))!;
            final timestamp = MaterialLocalizations.of(
              tester.element(card),
            ).formatTimeOfDay(const TimeOfDay(hour: 10, minute: 42));
            final texts = find.descendant(
              of: card,
              matching: find.byType(Text),
            );
            expect(
              tester.widgetList<Text>(texts).map((text) => text.data),
              unorderedEquals([
                l.appearanceSidebarPreviewTitle,
                l.appearanceSidebarPreviewMessage,
                timestamp,
                l.settingsPageAssistant,
                l.appearanceSidebarPreviewModel,
              ]),
            );
            for (final text in texts.evaluate()) {
              expectInsideClip(
                tester.getRect(find.byWidget(text.widget)),
                scene,
                (text.widget as Text).data!,
              );
            }
            expectInsideClip(
              tester.getRect(
                find.byKey(const ValueKey('appearanceSidebarPreviewThumbnail')),
              ),
              scene,
              'thumbnail',
            );
            expectInsideClip(
              tester.getRect(find.byType(SidebarDockCapsule)),
              panel,
              'dock',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final size in [
    const Size(360, 780),
    const Size(780, 360),
    const Size(1024, 768),
  ]) {
    testWidgets('Russian sidebar controls remain usable at 1.3 in $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await settings();
      await prefs.setGlassTheme(true);
      await pump(
        tester,
        prefs,
        locale: const Locale('ru'),
        textScale: 1.3,
        brightness: Brightness.dark,
      );
      final opacity = find.byKey(const ValueKey('appearanceSidebarOpacity'));
      await tester.ensureVisible(opacity);
      await tester.pumpAndSettle();
      final rect = tester.getRect(opacity);
      final gesture = await tester.startGesture(
        Offset(rect.right - 16, rect.center.dy),
      );
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(prefs.sidebarAppearance.opacity, lessThan(1));
      expect(
        find.byKey(const ValueKey('appearanceSidebarPreview')).hitTestable(),
        findsOneWidget,
      );
      await tap(tester, 'appearanceSidebarTimestamp');
      expect(prefs.sidebarAppearance.showTimestamp, isTrue);
      await tester.ensureVisible(
        find.byKey(const ValueKey('appearanceSidebarShortcutPicker')),
      );
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(const ValueKey('appearanceSidebarShortcutPicker'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

class _FailingResetSettings extends SettingsProvider {
  _FailingResetSettings(super.preferences);

  @override
  Future<void> resetSidebarAppearance() async =>
      throw StateError('write rejected');
}
