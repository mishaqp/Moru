import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/sidebar_shortcut.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/browser/browser_library.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/widgets/sidebar_bottom_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

void main() {
  group('SidebarShortcut', () {
    test('survives a round trip and skips damaged entries', () {
      const app = SidebarShortcut.miniApp('naruto');
      const page = SidebarShortcut.webPage('https://kimi.com/', 'Kimi Web');
      expect(SidebarShortcut.decode(app.encode()), app);
      final decoded = SidebarShortcut.decode(page.encode())!;
      expect(decoded, page);
      expect(decoded.title, 'Kimi Web');
      expect(SidebarShortcut.decode('{'), isNull);
      expect(SidebarShortcut.decode('{"kind":"x","target":"a"}'), isNull);
      expect(SidebarShortcut.decode('{"kind":"app","target":""}'), isNull);
    });

    test('the setting keeps its order and outlives the provider', () async {
      final prefs = createBusinessTestPreferences();
      final settings = SettingsProvider(prefs);
      await settings.loaded;
      const a = SidebarShortcut.webPage('https://a.example/', 'A');
      const b = SidebarShortcut.miniApp('b');
      await settings.setSidebarShortcuts([b, a, b]);
      expect(settings.sidebarShortcuts, [b, a]);

      final reopened = SettingsProvider(prefs);
      await reopened.loaded;
      expect(reopened.sidebarShortcuts, [b, a]);
      settings.dispose();
      reopened.dispose();
    });
  });

  group('SidebarBottomBar', () {
    late Directory temp;
    late MiniAppStore apps;
    late BrowserLibrary library;
    late SettingsProvider settings;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('sidebar-bottom-');
      apps = MiniAppStore(root: () async => Directory(p.join(temp.path, 'i')));
      library = BrowserLibrary(
        directory: () async => Directory(p.join(temp.path, 'b')),
      );
      settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;
    });
    tearDown(() async {
      settings.dispose();
      await temp.delete(recursive: true);
    });

    Future<void> installApp(String id, String name) async {
      final dir = Directory(p.join(temp.path, 'src-$id'));
      await dir.create(recursive: true);
      await File(
        p.join(dir.path, MiniAppStore.manifestFile),
      ).writeAsString(jsonEncode({'id': id, 'name': name}));
      await File(
        p.join(dir.path, 'index.html'),
      ).writeAsString('<html><body></body></html>');
      await apps.install(dir);
    }

    var avatarTaps = 0;

    Future<void> pump(WidgetTester tester, {double width = 340}) async {
      avatarTaps = 0;
      // Loaded outside the fake clock: the bar's own load() then finds them
      // ready instead of waiting on file I/O the test clock never runs.
      await tester.runAsync(() async {
        await apps.load();
        await library.load();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: width,
                  child: SidebarBottomBar(
                    glass: false,
                    avatar: const SizedBox.square(
                      key: ValueKey('avatar'),
                      dimension: 36,
                    ),
                    onAvatarTap: () => avatarTaps++,
                    miniApps: apps,
                    browserLibrary: library,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the dock holds the avatar and the main screens', (
      tester,
    ) async {
      await pump(tester);
      for (final label in ['My Apps', 'Settings', 'Memory']) {
        expect(
          find.descendant(
            of: find.byKey(SidebarBottomBar.dockKey),
            matching: find.byTooltip(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      await tester.tap(find.byKey(const ValueKey('avatar')));
      expect(avatarTaps, 1);
      // Nothing to pin yet: no shortcut row at all.
      expect(find.byKey(SidebarBottomBar.shortcutsKey), findsNothing);
    });

    testWidgets('the dock fits a narrow phone', (tester) async {
      // 82% of a 360 dp screen, minus nothing: an overflow fails the test.
      await pump(tester, width: 295);
      expect(tester.takeException(), isNull);
      expect(find.byKey(SidebarBottomBar.dockKey), findsOneWidget);
    });

    testWidgets('a mini app and a bookmark are pinned from the picker, '
        'shown as cards and removed with a long press', (tester) async {
      await tester.runAsync(() async {
        await installApp('naruto', 'Naruto');
        await library.toggleBookmark('https://kimi.com/', 'Kimi Web');
      });
      await pump(tester);

      // Nothing pinned: no row, and no add button in the sidebar either.
      expect(find.byKey(SidebarBottomBar.shortcutsKey), findsNothing);

      // Settings open the picker. The stores were loaded outside the fake
      // clock, so their futures finish outside it too.
      final context = tester.element(find.byType(SidebarBottomBar));
      await tester.runAsync(() async {
        unawaited(
          showSidebarShortcutPicker(
            context,
            miniApps: apps,
            browserLibrary: library,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Sidebar shortcuts'), findsOneWidget);
      await tester.tap(find.text('Naruto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kimi Web'));
      await tester.pumpAndSettle();
      expect(settings.sidebarShortcuts, const [
        SidebarShortcut.miniApp('naruto'),
        SidebarShortcut.webPage('https://kimi.com/', 'Kimi Web'),
      ]);
      expect(settings.sidebarShortcuts.last.title, 'Kimi Web');
      Navigator.of(tester.element(find.text('Sidebar shortcuts'))).pop();
      await tester.pumpAndSettle();

      const app = SidebarShortcut.miniApp('naruto');
      const page = SidebarShortcut.webPage('https://kimi.com/', '');
      expect(find.byKey(SidebarBottomBar.shortcutKey(app)), findsOneWidget);
      expect(find.byKey(SidebarBottomBar.shortcutKey(page)), findsOneWidget);
      // Two big cards share one row.
      final first = tester.getRect(
        find.byKey(SidebarBottomBar.shortcutKey(app)),
      );
      final second = tester.getRect(
        find.byKey(SidebarBottomBar.shortcutKey(page)),
      );
      expect(first.top, second.top);
      expect(first.width, second.width);
      expect(first.height, greaterThanOrEqualTo(56));

      await tester.longPress(find.byKey(SidebarBottomBar.shortcutKey(app)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from sidebar'));
      await tester.pumpAndSettle();
      expect(settings.sidebarShortcuts, const [page]);
      expect(find.byKey(SidebarBottomBar.shortcutKey(app)), findsNothing);
    });

    testWidgets('a deleted mini app drops out of the row', (tester) async {
      await tester.runAsync(() async {
        await installApp('naruto', 'Naruto');
        await settings.setSidebarShortcuts(const [
          SidebarShortcut.miniApp('naruto'),
        ]);
      });
      await pump(tester);
      const app = SidebarShortcut.miniApp('naruto');
      expect(find.byKey(SidebarBottomBar.shortcutKey(app)), findsOneWidget);

      await tester.runAsync(() => apps.delete('naruto'));
      await tester.pumpAndSettle();
      expect(find.byKey(SidebarBottomBar.shortcutKey(app)), findsNothing);
      expect(find.byKey(SidebarBottomBar.shortcutsKey), findsNothing);
    });
  });
}
