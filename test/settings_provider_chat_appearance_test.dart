import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:Kelivo/core/database/business_settings_router.dart';
import 'package:Kelivo/core/models/backup.dart';
import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/backup/backup_settings_validator.dart';
import 'package:Kelivo/core/services/backup/data_sync.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/business_test_harness.dart';

class _AppearancePathProvider extends PathProviderPlatform {
  _AppearancePathProvider(this.root);

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

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appData;
  late PathProviderPlatform originalPathProvider;

  setUp(() async {
    appData = await Directory.systemTemp.createTemp('chat-appearance-');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _AppearancePathProvider(appData.path);
    SandboxPathResolver.debugSetDirs(docsDir: appData.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.chat_background_video'),
          (call) async {
            final arguments = call.arguments as Map;
            final source = File(arguments['sourcePath'] as String);
            expect(source.path, contains('/images/chat_backgrounds/'));
            expect(await source.exists(), isTrue);
            return '${appData.path}/cache/prepared.mp4';
          },
        );
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    SandboxPathResolver.debugSetDirs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.chat_background_video'),
          null,
        );
    await appData.delete(recursive: true);
  });

  test(
    'unset global appearance uses one shared background and legacy mask',
    () async {
      final harness = await createBusinessTestHarness(
        initial: {'display_chat_background_mask_strength_v1': 0.65},
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;

      expect(settings.chatAppearance.shared, isTrue);
      expect(settings.chatAppearance.light.type, ChatBackgroundType.none);
      expect(settings.chatAppearance.light.maskStrength, 0.65);
      expect(settings.chatAppearance.dark.maskStrength, 0.65);
      expect(
        harness.preferences.containsKey('display_chat_appearance_v1'),
        isTrue,
      );
      expect(
        settings.chatAppearance.backgroundFor(Brightness.dark),
        settings.chatAppearance.backgroundFor(Brightness.light),
      );
    },
  );

  test('split themes persist, reload, and survive provider copy', () async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    addTearDown(settings.dispose);
    await settings.loaded;
    const appearance = ChatAppearanceSettings(
      shared: false,
      light: ChatBackgroundSettings(
        type: ChatBackgroundType.gradient,
        fit: ChatBackgroundFit.contain,
        focusX: 0.3,
        brightness: 1.2,
        saturation: 0.7,
      ),
      dark: ChatBackgroundSettings(
        type: ChatBackgroundType.none,
        blur: 6,
        maskStrength: 1.8,
      ),
    );

    await settings.setChatAppearance(appearance);
    final reloaded = SettingsProvider(harness.preferences);
    addTearDown(reloaded.dispose);
    await reloaded.loaded;
    expect(reloaded.chatAppearance, appearance);
    expect(
      reloaded.chatAppearance.backgroundFor(Brightness.dark),
      appearance.dark,
    );
    expect(settings.copyWith().chatAppearance, appearance);

    await settings.setChatAppearance(appearance.copyWith(shared: true));
    expect(
      settings.chatAppearance.backgroundFor(Brightness.dark),
      appearance.light,
    );
  });

  test(
    'current legacy assistant image is copied once without changing assistants',
    () async {
      final source = File('${appData.path}/picked.png');
      await source.writeAsBytes([1, 2, 3, 4]);
      final rawAssistants = jsonEncode([
        {'id': 'first', 'name': 'First', 'useGradientBackground': true},
        {'id': 'current', 'name': 'Current', 'background': source.path},
      ]);
      final harness = await createBusinessTestHarness(
        initial: {
          'assistants_v1': rawAssistants,
          'current_assistant_id_v1': 'current',
          'display_chat_background_mask_strength_v1': 0.4,
        },
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;

      final background = settings.chatAppearance.light;
      expect(background.type, ChatBackgroundType.image);
      expect(background.maskStrength, 0.4);
      expect(
        background.path,
        startsWith('kelivo-file:///images/chat_backgrounds/'),
      );
      final managed = File(SandboxPathResolver.fix(background.path!));
      expect(await managed.readAsBytes(), [1, 2, 3, 4]);
      expect(await source.exists(), isTrue);
      expect(harness.preferences.getString('assistants_v1'), rawAssistants);
      expect(
        harness.preferences.getDouble(
          'display_chat_background_mask_strength_v1',
        ),
        0.4,
      );

      await settings.setChatAppearance(const ChatAppearanceSettings());
      final reloaded = SettingsProvider(harness.preferences);
      addTearDown(reloaded.dispose);
      await reloaded.loaded;
      expect(reloaded.chatAppearance.light.type, ChatBackgroundType.none);
      expect(await managed.exists(), isFalse);
      expect(await source.exists(), isTrue);
    },
  );

  test(
    'legacy gradient tuning migrates from first assistant when id is invalid',
    () async {
      final harness = await createBusinessTestHarness(
        initial: {
          'assistants_v1': jsonEncode([
            {
              'id': 'gradient',
              'name': 'Gradient',
              'useGradientBackground': true,
              'gradientBackgroundAnimated': false,
              'gradientBackgroundPhase': 2.5,
              'gradientBackgroundOffsetX': 0.25,
              'gradientBackgroundOffsetY': -0.35,
            },
          ]),
          'current_assistant_id_v1': 'missing',
        },
      );
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;

      final background = settings.chatAppearance.light;
      expect(background.type, ChatBackgroundType.gradient);
      expect(background.gradientAnimated, isFalse);
      expect(background.gradientPhase, 2.5);
      expect(background.gradientOffsetX, 0.25);
      expect(background.gradientOffsetY, -0.35);
    },
  );

  test(
    'explicit none and malformed existing key block legacy migration',
    () async {
      for (final raw in [
        jsonEncode(const ChatAppearanceSettings().toJson()),
        '{invalid',
      ]) {
        final harness = await createBusinessTestHarness(
          initial: {
            'display_chat_appearance_v1': raw,
            'assistants_v1': jsonEncode([
              {
                'id': 'gradient',
                'name': 'Gradient',
                'useGradientBackground': true,
              },
            ]),
          },
        );
        final settings = SettingsProvider(harness.preferences);
        addTearDown(settings.dispose);
        await settings.loaded;
        expect(settings.chatAppearance.light.type, ChatBackgroundType.none);
        expect(
          harness.preferences.getString('display_chat_appearance_v1'),
          raw,
        );
      }
    },
  );

  test(
    'media import owns a private copy and only replaces its selected theme',
    () async {
      final source = File('${appData.path}/picked.mp4');
      await source.writeAsBytes([5, 6, 7]);
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setChatAppearance(
        settings.chatAppearance.copyWith(shared: false),
      );

      expect(
        await settings.importChatBackground(
          source.path,
          ChatBackgroundType.video,
          brightness: Brightness.dark,
        ),
        isTrue,
      );
      expect(settings.chatAppearance.light.type, ChatBackgroundType.none);
      final background = settings.chatAppearance.dark;
      expect(background.type, ChatBackgroundType.video);
      expect(
        background.path,
        startsWith('kelivo-file:///images/chat_backgrounds/'),
      );
      final copied = File(SandboxPathResolver.fix(background.path!));
      expect(await copied.readAsBytes(), [5, 6, 7]);
      await source.delete();
      final reloaded = SettingsProvider(harness.preferences);
      addTearDown(reloaded.dispose);
      await reloaded.loaded;
      expect(
        await File(
          SandboxPathResolver.fix(reloaded.chatAppearance.dark.path!),
        ).exists(),
        isTrue,
      );
      expect(
        await settings.importChatBackground(
          source.path,
          ChatBackgroundType.gif,
        ),
        isFalse,
      );
      expect(settings.chatAppearance.dark, background);
    },
  );

  test(
    'appearance exports with a portable file URI and backup validator accepts it',
    () async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      final source = File('${appData.path}/picked.gif');
      await source.writeAsBytes([8, 9]);
      expect(
        await settings.importChatBackground(
          source.path,
          ChatBackgroundType.gif,
        ),
        isTrue,
      );

      final exported = await DataSync.exportBusinessSettingsFrom(
        harness.repository,
      );
      final data = jsonDecode(exported.settingsJson) as Map<String, dynamic>;
      expect(data['display_chat_appearance_v1'], isNotNull);
      expect(
        data['display_chat_appearance_v1'],
        contains('kelivo-file:///images/chat_backgrounds/'),
      );
      expect(() => BackupSettingsValidator.validate(data), returnsNormally);
      expect(
        BusinessKeyRegistry.classify('display_chat_appearance_v1'),
        BusinessKeyDisposition.preference,
      );
    },
  );

  test(
    'ordinary file backup includes privately copied video and its appearance settings',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Moru',
        packageName: 'Kelivo',
        version: '0.1.47',
        buildNumber: '48',
        buildSignature: 'test',
      );
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      final source = File('${appData.path}/picked.mp4');
      await source.writeAsBytes([10, 11, 12]);
      expect(
        await settings.importChatBackground(
          source.path,
          ChatBackgroundType.video,
        ),
        isTrue,
      );
      final savedPath = settings.chatAppearance.light.path!;
      final entryName = Uri.parse(savedPath).path.substring(1);
      final chat = ChatService();
      final sync = DataSync(
        businessRepository: harness.repository,
        chatService: chat,
      );
      final backup = await sync.prepareBackupFile(
        const WebDavConfig(includeChats: false, includeFiles: true),
      );
      final input = InputFileStream(backup.path);
      Archive? archive;
      try {
        archive = ZipDecoder().decodeStream(input);
        expect(archive.findFile(entryName)?.readBytes(), [10, 11, 12]);
        final exported =
            jsonDecode(
                  utf8.decode(archive.findFile('settings.json')!.readBytes()!),
                )
                as Map<String, dynamic>;
        final appearance = ChatAppearanceSettings.fromJson(
          jsonDecode(exported['display_chat_appearance_v1'] as String)
              as Map<String, dynamic>,
        );
        expect(appearance.light.path, savedPath);
        expect(appearance.light.type, ChatBackgroundType.video);
      } finally {
        archive?.clearSync();
        input.closeSync();
        await DataSync.cleanupTemporaryBackupFile(backup);
        await chat.close();
      }
    },
  );

  test(
    'rejected video preparation preserves saved appearance and removes its candidate',
    () async {
      final harness = await createBusinessTestHarness();
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      final source = File('${appData.path}/unsupported.mp4');
      await source.writeAsBytes([13, 14]);
      final previous = settings.chatAppearance;
      final saved = harness.preferences.getString('display_chat_appearance_v1');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.chat_background_video'),
            (call) async {
              throw PlatformException(code: 'unsupported');
            },
          );

      expect(
        await settings.importChatBackground(
          source.path,
          ChatBackgroundType.video,
        ),
        isFalse,
      );
      expect(settings.chatAppearance, previous);
      expect(
        harness.preferences.getString('display_chat_appearance_v1'),
        saved,
      );
      expect(
        await Directory(
          '${appData.path}/images/chat_backgrounds',
        ).list().toList(),
        isEmpty,
      );
      expect(await source.readAsBytes(), [13, 14]);
    },
  );

  test(
    'failed legacy copy retries next launch without overwriting an explicit choice',
    () async {
      final source = File('${appData.path}/unavailable.png');
      final harness = await createBusinessTestHarness(
        initial: {
          'assistants_v1': jsonEncode([
            {'id': 'current', 'name': 'Current', 'background': source.path},
          ]),
          'current_assistant_id_v1': 'current',
        },
      );
      final first = SettingsProvider(harness.preferences);
      addTearDown(first.dispose);
      await first.loaded;
      expect(first.chatAppearance.light.type, ChatBackgroundType.none);
      expect(
        harness.preferences.containsKey('display_chat_appearance_v1'),
        isFalse,
      );

      await source.writeAsBytes([15, 16]);
      final second = SettingsProvider(harness.preferences);
      addTearDown(second.dispose);
      await second.loaded;
      expect(second.chatAppearance.light.type, ChatBackgroundType.image);
      expect(
        harness.preferences.containsKey('display_chat_appearance_v1'),
        isTrue,
      );
    },
  );

  test('legacy URL wallpaper becomes a private portable file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.add([17, 18, 19]);
      await request.response.close();
    });
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });
    final harness = await createBusinessTestHarness(
      initial: {
        'assistants_v1': jsonEncode([
          {
            'id': 'remote',
            'name': 'Remote',
            'background': 'http://127.0.0.1:${server.port}/wallpaper.png',
          },
        ]),
      },
    );
    await HttpOverrides.runWithHttpOverrides(() async {
      final settings = SettingsProvider(harness.preferences);
      addTearDown(settings.dispose);
      await settings.loaded;
      final background = settings.chatAppearance.light;
      expect(background.type, ChatBackgroundType.image);
      expect(
        background.path,
        startsWith('kelivo-file:///images/chat_backgrounds/'),
      );
      expect(
        await File(SandboxPathResolver.fix(background.path!)).readAsBytes(),
        [17, 18, 19],
      );
    }, _RealHttpOverrides());
  });

  test('malformed media fields and unsupported controls are normalized', () {
    final background = ChatBackgroundSettings.fromJson({
      'type': 'unknown',
      'path': 42,
      'fit': 'unknown',
      'focusX': -5,
      'focusY': 5,
      'maskStrength': 9,
      'blur': double.infinity,
      'brightness': -1,
      'saturation': double.nan,
    });
    expect(background.type, ChatBackgroundType.none);
    expect(background.path, isNull);
    expect(background.fit, ChatBackgroundFit.cover);
    expect(background.focusX, -1);
    expect(background.focusY, 1);
    expect(background.maskStrength, 2);
    expect(background.blur, 0);
    expect(background.brightness, 0);
    expect(background.saturation, 1);
  });
}
