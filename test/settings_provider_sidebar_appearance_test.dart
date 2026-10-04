import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/database/business_settings_router.dart';
import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/chat_folder.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/models/sidebar_shortcut.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/backup/backup_settings_validator.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/chat/chat_background_video.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/business_test_harness.dart';

class _SidebarPaths extends PathProviderPlatform {
  _SidebarPaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform originalPaths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('moru-sidebar-appearance-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SidebarPaths(root.path);
    SandboxPathResolver.debugSetDirs(docsDir: root.path);
  });

  tearDown(() async {
    ChatBackgroundVideo.debugPrepareOverride = null;
    PathProviderPlatform.instance = originalPaths;
    SandboxPathResolver.debugSetDirs();
    await root.delete(recursive: true);
  });

  test('background modes reuse the global chat profiles and custom media', () {
    const chat = ChatAppearanceSettings(
      shared: false,
      light: ChatBackgroundSettings(
        type: ChatBackgroundType.image,
        path: 'light',
      ),
      dark: ChatBackgroundSettings(type: ChatBackgroundType.gif, path: 'dark'),
    );
    const appearance = SidebarAppearanceSettings();
    expect(appearance.backgroundFor(Brightness.light, chat), chat.light);
    expect(appearance.backgroundFor(Brightness.dark, chat), chat.dark);
    const own = ChatBackgroundSettings(type: ChatBackgroundType.gradient);
    final custom = appearance.copyWith(
      backgroundMode: SidebarBackgroundMode.custom,
      customBackground: own,
    );
    expect(custom.backgroundFor(Brightness.light, chat), own);
    expect(custom.backgroundFor(Brightness.dark, chat), own);
    expect(
      appearance
          .copyWith(backgroundMode: SidebarBackgroundMode.theme)
          .backgroundFor(Brightness.dark, chat)
          .type,
      ChatBackgroundType.none,
    );
  });

  test(
    'model preserves safe widths and validates unknown values without a migration',
    () {
      const appearance = SidebarAppearanceSettings();
      expect(appearance.phoneWidthPercent, 80);
      expect(appearance.wideWidthPercent, 30);
      expect(appearance.cardRadius, 14);
      expect(appearance.widthFor(400, wide: false), 320);
      expect(appearance.widthFor(100, wide: false), 95);
      expect(appearance.widthFor(600, wide: true), 240);
      expect(appearance.widthFor(1000, wide: true), 300);
      expect(appearance.widthFor(2000, wide: true), 480);
      expect(appearance.widthFor(0, wide: false), 0);
      final parsed = SidebarAppearanceSettings.fromJson({
        'backgroundMode': 'future',
        'density': 3,
        'grouping': false,
        'phoneWidthPercent': double.nan,
        'wideWidthPercent': double.infinity,
        'cardColor': 'red',
        'showPreview': 'true',
        'dockItems': ['memory', 'unknown', 'memory', 'profile'],
      });
      expect(parsed.backgroundMode, SidebarBackgroundMode.sameAsChat);
      expect(parsed.density, SidebarDensity.normal);
      expect(parsed.grouping, SidebarGrouping.date);
      expect(parsed.phoneWidthPercent, 80);
      expect(parsed.wideWidthPercent, 30);
      expect(parsed.showPreview, isFalse);
      expect(parsed.cardColor, isNull);
      expect(parsed.dockItems, [
        SidebarDockItem.memory,
        SidebarDockItem.profile,
      ]);
      expect(
        () => parsed.dockItems.add(SidebarDockItem.settings),
        throwsUnsupportedError,
      );
      expect(
        parsed
            .copyWith(cardColor: 0xffaabbcc)
            .copyWith(clearCardColor: true)
            .cardColor,
        isNull,
      );
    },
  );

  test(
    'missing sidebar appearance preserves existing sidebar choices',
    () async {
      const shortcut = SidebarShortcut.miniApp('kept-app');
      final harness = await createBusinessTestHarness(
        initial: {
          'sidebar_thumbnails_v1': false,
          'sidebar_shortcuts_v1': [shortcut.encode()],
        },
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;

      expect(settings.sidebarAppearance, const SidebarAppearanceSettings());
      expect(
        settings.sidebarAppearance.backgroundMode,
        SidebarBackgroundMode.sameAsChat,
      );
      expect(settings.sidebarAppearance.grouping, SidebarGrouping.date);
      expect(settings.sidebarAppearance.showTimestamp, isFalse);
      expect(settings.sidebarAppearance.showAssistant, isFalse);
      expect(settings.sidebarAppearance.showModel, isFalse);
      expect(settings.sidebarAppearance.showPreview, isFalse);
      expect(settings.sidebarThumbnails, isFalse);
      expect(settings.sidebarShortcuts, [shortcut]);
      final copy = settings.copyWith();
      addTearDown(copy.dispose);
      expect(copy.sidebarThumbnails, isFalse);
      expect(copy.sidebarShortcuts, [shortcut]);
      expect(
        harness.preferences.containsKey('display_sidebar_appearance_v1'),
        isFalse,
      );
    },
  );

  test(
    'sidebar settings persist, reload, copy and use business backup',
    () async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      const appearance = SidebarAppearanceSettings(
        backgroundMode: SidebarBackgroundMode.custom,
        customBackground: ChatBackgroundSettings(
          type: ChatBackgroundType.gradient,
          gradientAnimated: false,
          focusX: 0.4,
          brightness: 1.2,
        ),
        maskStrength: 0.35,
        blur: 5,
        opacity: 0.6,
        phoneWidthPercent: 85,
        wideWidthPercent: 30,
        density: SidebarDensity.spacious,
        cardRadius: 18,
        cardColor: 0x8899aabb,
        activeCardColor: 0xff223344,
        showTimestamp: true,
        showAssistant: true,
        showModel: true,
        showPreview: true,
        grouping: SidebarGrouping.assistant,
        dockItems: [SidebarDockItem.settings, SidebarDockItem.profile],
      );

      await settings.setSidebarAppearance(appearance);
      final reloaded = SettingsProvider(harness.preferences);
      addTearDown(reloaded.dispose);
      await reloaded.loaded;
      expect(reloaded.sidebarAppearance, appearance);
      final copy = settings.copyWith();
      addTearDown(copy.dispose);
      expect(copy.sidebarAppearance, appearance);
      expect(
        BusinessKeyRegistry.classify('display_sidebar_appearance_v1'),
        BusinessKeyDisposition.preference,
      );
      final export = await DataSync.exportBusinessSettingsFrom(
        harness.repository,
      );
      final exported = jsonDecode(export.settingsJson) as Map<String, dynamic>;
      BackupSettingsValidator.validate(exported);
      expect(
        jsonDecode(exported['display_sidebar_appearance_v1'] as String),
        appearance.toJson(),
      );
    },
  );

  test('explicit false flags and empty dock survive reload', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    await settings.setSidebarAppearance(
      const SidebarAppearanceSettings(
        showTimestamp: true,
        showAssistant: true,
        showModel: true,
        showPreview: true,
      ),
    );
    await settings.setSidebarAppearance(
      const SidebarAppearanceSettings(dockItems: []),
    );
    final reloaded = SettingsProvider(harness.preferences);
    addTearDown(reloaded.dispose);
    await reloaded.loaded;
    expect(reloaded.sidebarAppearance.showTimestamp, isFalse);
    expect(reloaded.sidebarAppearance.showAssistant, isFalse);
    expect(reloaded.sidebarAppearance.showModel, isFalse);
    expect(reloaded.sidebarAppearance.showPreview, isFalse);
    expect(reloaded.sidebarAppearance.dockItems, isEmpty);
  });

  test(
    'invalid persisted JSON falls back without rewriting existing choices',
    () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'display_sidebar_appearance_v1': '{broken',
          'sidebar_thumbnails_v1': false,
        },
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      expect(settings.sidebarAppearance, const SidebarAppearanceSettings());
      expect(settings.sidebarThumbnails, isFalse);
      expect(
        harness.preferences.getString('display_sidebar_appearance_v1'),
        '{broken',
      );
    },
  );

  test('setter waits for loaded and sanitizes numbers and colors', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.setSidebarAppearance(
      const SidebarAppearanceSettings(
        maskStrength: 99,
        blur: -1,
        opacity: 9,
        cardRadius: -9,
        phoneWidthPercent: 1,
        wideWidthPercent: 99,
        cardColor: -1,
        activeCardColor: 0x100000000,
      ),
    );
    final sanitized = settings.sidebarAppearance;
    expect(sanitized.maskStrength, 2);
    expect(sanitized.blur, 0);
    expect(sanitized.opacity, 1);
    expect(sanitized.cardRadius, 0);
    expect(
      sanitized.phoneWidthPercent,
      SidebarAppearanceSettings.minPhoneWidthPercent,
    );
    expect(
      sanitized.wideWidthPercent,
      SidebarAppearanceSettings.maxWideWidthPercent,
    );
    expect(sanitized.cardColor, isNull);
    expect(sanitized.activeCardColor, isNull);
  });

  test(
    'failed persisted change rolls back and leaves retained media intact',
    () async {
      final source = File('${root.path}/picked.png');
      await source.writeAsBytes([2, 4, 6]);
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      expect(
        await settings.importSidebarBackground(
          source.path,
          ChatBackgroundType.image,
        ),
        isTrue,
      );
      final previous = settings.sidebarAppearance;
      final owned = File(
        SandboxPathResolver.fix(previous.customBackground.path!),
      );
      await harness.preferences.runWithRestoreWriteFence(() async {});

      await expectLater(
        settings.setSidebarAppearance(const SidebarAppearanceSettings()),
        throwsStateError,
      );
      expect(settings.sidebarAppearance, previous);
      expect(await owned.exists(), isTrue);
    },
  );

  test(
    'reset changes sidebar appearance and thumbnails while keeping existing pinned shortcuts',
    () async {
      const folder = ChatFolder(id: 'kept', name: 'Keep', icon: 'folder');
      final harness = await createBusinessTestHarness(
        initial: {
          'sidebar_folders_v1': ChatFolder.encodeList([folder]),
          'sidebar_collapsed_sections_v1': ['folder:kept'],
        },
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setSidebarThumbnails(false);
      await settings.setSidebarShortcuts([
        const SidebarShortcut.miniApp('app'),
      ]);
      await settings.setKeepSidebarOpenOnAssistantTap(true);
      await settings.setKeepSidebarOpenOnTopicTap(true);
      await settings.setChatAppearance(
        const ChatAppearanceSettings(
          light: ChatBackgroundSettings(type: ChatBackgroundType.gradient),
        ),
      );
      final chat = settings.chatAppearance;
      await settings.setSidebarAppearance(
        const SidebarAppearanceSettings(
          grouping: SidebarGrouping.none,
          density: SidebarDensity.compact,
          dockItems: [],
        ),
      );

      await settings.resetSidebarAppearance();
      expect(settings.sidebarAppearance, const SidebarAppearanceSettings());
      expect(settings.sidebarThumbnails, isTrue);
      expect(settings.sidebarShortcuts, [const SidebarShortcut.miniApp('app')]);
      expect(settings.sidebarFolders, [folder]);
      expect(settings.sidebarCollapsedSections, {'folder:kept'});
      expect(settings.keepSidebarOpenOnAssistantTap, isTrue);
      expect(settings.keepSidebarOpenOnTopicTap, isTrue);
      expect(settings.chatAppearance, chat);
      expect(
        harness.preferences.getStringList('sidebar_collapsed_sections_v1'),
        ['folder:kept'],
      );
    },
  );

  for (final sidebarFirst in [true, false]) {
    test(
      'owned background retained by ${sidebarFirst ? 'chat' : 'sidebar'} until both release it',
      () async {
        final source = File('${root.path}/picked.png');
        await source.writeAsBytes([1, 3, 5]);
        final harness = await createBusinessTestHarness();
        final settings = SettingsProvider(harness.preferences);
        addTearDown(settings.dispose);
        await settings.loaded;
        expect(
          await settings.importSidebarBackground(
            source.path,
            ChatBackgroundType.image,
          ),
          isTrue,
        );
        final wallpaper = settings.sidebarAppearance.customBackground;
        final owned = File(SandboxPathResolver.fix(wallpaper.path!));
        expect(
          wallpaper.path,
          startsWith('kelivo-file:///images/chat_backgrounds/'),
        );
        expect(await owned.readAsBytes(), [1, 3, 5]);
        await settings.setChatAppearance(
          ChatAppearanceSettings(light: wallpaper, dark: wallpaper),
        );

        if (sidebarFirst) {
          await settings.resetSidebarAppearance();
        } else {
          await settings.setChatAppearance(const ChatAppearanceSettings());
        }
        expect(await owned.exists(), isTrue);
        if (sidebarFirst) {
          await settings.setChatAppearance(const ChatAppearanceSettings());
        } else {
          await settings.resetSidebarAppearance();
        }
        expect(await owned.exists(), isFalse);
        expect(await source.readAsBytes(), [1, 3, 5]);
      },
    );
  }

  test(
    'sidebar video import prepares owned copy and failed replacement retains saved media',
    () async {
      final source = File('${root.path}/picked.mp4');
      await source.writeAsBytes([1, 2, 4]);
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      var prepareCalls = 0;
      ChatBackgroundVideo.debugPrepareOverride =
          (path, {maxWidth, maxHeight}) async {
            prepareCalls++;
            expect(path, contains('/images/chat_backgrounds/'));
            expect(await File(path).readAsBytes(), [1, 2, 4]);
            return '${root.path}/cache/prepared.mp4';
          };
      expect(
        await settings.importSidebarBackground(
          source.path,
          ChatBackgroundType.video,
        ),
        isTrue,
      );
      expect(prepareCalls, 1);
      final saved = settings.sidebarAppearance;
      ChatBackgroundVideo.debugPrepareOverride =
          (path, {maxWidth, maxHeight}) async {
            throw const FormatException('unreadable video');
          };
      expect(
        await settings.importSidebarBackground(
          source.path,
          ChatBackgroundType.video,
        ),
        isFalse,
      );
      expect(settings.sidebarAppearance, saved);
      final owned = Directory('${root.path}/images/chat_backgrounds');
      expect(await owned.list().length, 1);
      expect(await source.exists(), isTrue);
    },
  );
}
