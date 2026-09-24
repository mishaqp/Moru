import 'package:Kelivo/core/providers/settings_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/world_book.dart';
import 'package:Kelivo/core/providers/world_book_provider.dart';
import 'package:Kelivo/features/world_book/pages/world_book_page.dart';
import 'package:Kelivo/features/world_book/widgets/world_book_entry_widgets.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_form_text_field.dart';
import 'package:Kelivo/shared/widgets/ios_switch.dart';
import 'package:Kelivo/theme/theme_factory.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final harnesses = Expando<BusinessTestHarness>();
  final screenshotDir = Platform.environment['KELIVO_WORLD_BOOK_SCREENSHOTS'];
  setUpAll(() async {
    if (screenshotDir == null) return;
    final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    final bytes = await font.readAsBytes();
    await (FontLoader(
      'WorldBookPreview',
    )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  Future<WorldBookProvider> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Size? size,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    final harness = await tester.runAsync(() => createBusinessTestHarness());
    final provider = WorldBookProvider(preferences: harness!.preferences);
    harnesses[provider] = harness;
    late SettingsProvider settings;
    await tester.runAsync(() async {
      settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      await provider.initialize();
      await provider.addBook(
        const WorldBook(
          id: 'book',
          name: 'Story world',
          description: 'Characters and setting',
          entries: [
            WorldBookEntry(
              id: 'alpha',
              name: 'Alpha',
              content: 'A',
              keywords: ['dragon'],
              sticky: 3,
              cooldown: 2,
              position: WorldBookInjectionPosition.beforeSystemPrompt,
            ),
            WorldBookEntry(
              id: 'beta',
              name: 'Beta',
              content: 'B',
              constantActive: true,
              position: WorldBookInjectionPosition.atDepth,
            ),
            WorldBookEntry(
              id: 'gamma',
              name: 'Gamma',
              content: 'C',
              enabled: false,
              constantActive: true,
              position: WorldBookInjectionPosition.bottomOfChat,
            ),
          ],
        ),
      );
    });
    tester.view.physicalSize = size ?? const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme =
        (brightness == Brightness.light
                ? buildLightTheme(null)
                : buildDarkTheme(null))
            .copyWith(platform: TargetPlatform.iOS);
    if (screenshotDir != null) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'WorldBookPreview'),
        primaryTextTheme: theme.primaryTextTheme.apply(
          fontFamily: 'WorldBookPreview',
        ),
      );
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: RepaintBoundary(
          key: const ValueKey('world-book-screenshot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const WorldBookPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (screenshotDir == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('world-book-screenshot')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(screenshotDir).create(recursive: true);
      await File(
        '$screenshotDir/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  const platform = 'mobile';
  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      '$platform ${locale.languageCode} keeps labels and counts aligned at narrow widths',
      (tester) async {
        final provider = await mount(
          tester,
          locale: locale,
          size: const Size(320, 850),
          textScale: 1.4,
        );
        await tester.runAsync(
          () => provider.updateBook(
            provider.books.single.copyWith(
              name: 'A world with a long name 很长的世界书名称',
              entries: [
                provider.books.single.entries.first.copyWith(
                  name: 'A very long entry title 很长的条目名称',
                ),
                ...provider.books.single.entries.skip(1),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final title in find.byType(WorldBookEntryTitle).evaluate()) {
          final row = find.byWidget(title.widget);
          final label = find
              .descendant(of: row, matching: find.byType(Text))
              .first;
          final badge = find.descendant(
            of: row,
            matching: find.byType(WorldBookPositionBadge),
          );
          expect(
            tester.getCenter(label).dy,
            closeTo(tester.getCenter(badge).dy, 1),
          );
          expect(
            tester.getRect(label).right,
            lessThan(tester.getRect(badge).left),
          );
        }
        final l10n = AppLocalizations.of(tester.element(find.text('2/3')))!;
        expect(
          tester.getCenter(find.text('2/3')).dy,
          closeTo(
            tester.getCenter(find.byTooltip(l10n.worldBookAddEntry)).dy,
            1,
          ),
        );
        expect(tester.takeException(), isNull);
        await screenshot(tester, '$platform-${locale.languageCode}-narrow');
      },
    );
  }
  testWidgets(
    '$platform moves entries down exactly one place and persists enabled state',
    (tester) async {
      final provider = await mount(tester);
      expect(find.text('2/3'), findsOneWidget);
      expect(find.byType(WorldBookPositionBadge), findsNWidgets(3));
      final positions = tester
          .widgetList<WorldBookPositionBadge>(
            find.byType(WorldBookPositionBadge),
          )
          .map((w) => w.position)
          .toSet();
      expect(positions, hasLength(3));
      final handles = find.byType(ReorderableDragStartListener);
      final first = tester.getCenter(handles.at(0));
      final second = tester.getCenter(handles.at(1));
      final gesture = await tester.startGesture(first);
      await tester.pump();
      final distance = second.dy - first.dy + 20;
      for (double dy = 8; dy <= distance; dy += 8) {
        await gesture.moveTo(first + Offset(0, dy));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(provider.books.single.entries.map((e) => e.id), [
        'beta',
        'alpha',
        'gamma',
      ]);
      await tester.tap(find.byType(IosSwitch).first);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.runAsync(() => provider.loadAll());
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
      expect(provider.books.single.entries.first.enabled, isFalse);
      expect(provider.books.single.entries.map((e) => e.id), [
        'beta',
        'alpha',
        'gamma',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '$platform ${brightness.name} editor saves timing values without layout errors',
      (tester) async {
        final provider = await mount(tester, brightness: brightness);
        await screenshot(tester, '$platform-${brightness.name}-list');
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        final timed = find.byType(WorldBookTimedEffectsFields);
        await tester.ensureVisible(timed);
        await tester.pumpAndSettle();
        for (final pair in [
          ('Sticky (messages)', '5'),
          ('Cooldown (messages)', '4'),
          ('Delay (messages)', '3'),
        ]) {
          final field = find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is IosFormTextField && w.label == pair.$1,
            ),
            matching: find.byType(TextField),
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, pair.$2);
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await screenshot(tester, '$platform-${brightness.name}-editor');
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
        await tester.runAsync(() => provider.loadAll());
        await tester.pumpAndSettle();
        final entry = provider.books.single.entries.first;
        expect((entry.sticky, entry.cooldown, entry.delay), (5, 4, 3));
        expect(entry.position, WorldBookInjectionPosition.beforeSystemPrompt);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
