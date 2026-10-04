import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/core/database/business_repository.dart';
import 'package:Kelivo/core/models/backup.dart';
import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final type in [
    ChatBackgroundType.image,
    ChatBackgroundType.gif,
    ChatBackgroundType.video,
  ]) {
    test(
      '${type.name} sidebar media and all preferences restore on another app root',
      () async {
        final parent = await Directory.systemTemp.createTemp(
          'moru_sidebar_backup_',
        );
        final previousPaths = PathProviderPlatform.instance;
        File? archiveFile;
        AppDatabase? sourceDatabase;
        AppDatabase? targetDatabase;
        SettingsProvider? sourceSettings;
        SettingsProvider? targetSettings;
        try {
          final source = Directory('${parent.path}/source')..createSync();
          PathProviderPlatform.instance = _Paths(source.path);
          await SandboxPathResolver.init();
          PackageInfo.setMockInitialValues(
            appName: 'Moru',
            packageName: 'Kelivo',
            version: '0.1.47',
            buildNumber: '48',
            buildSignature: 'test',
          );
          sourceDatabase = AppDatabase.open(
            file: File('${source.path}/business.sqlite'),
          );
          final sourceRepository = BusinessRepository(sourceDatabase);
          final preferences = BusinessPreferences(sourceRepository);
          sourceSettings = SettingsProvider(preferences);
          await sourceSettings.loaded;
          final extension = switch (type) {
            ChatBackgroundType.gif => 'gif',
            ChatBackgroundType.video => 'mp4',
            _ => 'png',
          };
          final relative = 'images/chat_backgrounds/wallpaper.$extension';
          final wallpaper = File('${source.path}/$relative');
          await wallpaper.parent.create(recursive: true);
          final bytes = <int>[0, 1, 2, 127, 255];
          await wallpaper.writeAsBytes(bytes);
          final background = ChatBackgroundSettings(
            type: type,
            path: 'kelivo-file:///$relative',
            fit: ChatBackgroundFit.contain,
            focusX: 0.4,
            focusY: -0.3,
            maskStrength: 0.65,
            blur: 7,
            brightness: 1.2,
            saturation: 0.8,
          );
          final appearance = SidebarAppearanceSettings(
            backgroundMode: SidebarBackgroundMode.custom,
            customBackground: background,
            maskStrength: 0.4,
            blur: 4,
            opacity: 0.75,
            phoneWidthPercent: 85,
            wideWidthPercent: 35,
            density: SidebarDensity.compact,
            cardRadius: 20,
            cardColor: 0x77aabbcc,
            activeCardColor: 0x99ccbbaa,
            showTimestamp: true,
            showAssistant: true,
            showModel: true,
            showPreview: true,
            grouping: SidebarGrouping.assistant,
            dockItems: [SidebarDockItem.memory, SidebarDockItem.settings],
          );
          await sourceSettings.setSidebarAppearance(appearance);
          archiveFile =
              await DataSync(
                chatService: ChatService(),
                businessRepository: sourceRepository,
                businessPreferences: preferences,
              ).prepareBackupFile(
                const WebDavConfig(includeChats: false, includeFiles: true),
              );
          final archive = ZipDecoder().decodeBytes(
            await archiveFile.readAsBytes(),
          );
          expect(archive.findFile(relative)!.readBytes(), bytes);
          final exported =
              jsonDecode(
                    utf8.decode(
                      archive.findFile('settings.json')!.readBytes()!,
                    ),
                  )
                  as Map;
          expect(
            jsonDecode(exported['display_sidebar_appearance_v1'] as String),
            appearance.toJson(),
          );
          archive.clearSync();
          // A missing original source must not be needed after the backup is made.
          await wallpaper.delete();
          sourceSettings.dispose();
          sourceSettings = null;
          await sourceDatabase.close();
          sourceDatabase = null;

          final target = Directory('${parent.path}/target')..createSync();
          PathProviderPlatform.instance = _Paths(target.path);
          await SandboxPathResolver.init();
          targetDatabase = AppDatabase.open(
            file: File('${target.path}/business.sqlite'),
          );
          final targetRepository = BusinessRepository(targetDatabase);
          await DataSync(
            chatService: ChatService(),
            businessRepository: targetRepository,
          ).restoreFromLocalFile(
            archiveFile,
            const WebDavConfig(includeChats: false, includeFiles: true),
          );
          targetSettings = SettingsProvider(
            BusinessPreferences(targetRepository),
          );
          await targetSettings.loaded;
          expect(targetSettings.sidebarAppearance, appearance);
          final restoredPath = SandboxPathResolver.fix(
            targetSettings.sidebarAppearance.customBackground.path!,
          );
          expect(restoredPath, '${target.path}/$relative');
          expect(await File(restoredPath).readAsBytes(), bytes);
        } finally {
          sourceSettings?.dispose();
          targetSettings?.dispose();
          await sourceDatabase?.close();
          await targetDatabase?.close();
          await DataSync.cleanupTemporaryBackupFile(archiveFile);
          PathProviderPlatform.instance = previousPaths;
          SandboxPathResolver.debugSetDirs();
          await parent.delete(recursive: true);
        }
      },
    );
  }
}
