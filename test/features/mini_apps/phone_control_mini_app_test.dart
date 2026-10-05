import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_manifest.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_permissions.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/mini_apps/phone_control_mini_app.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phone-panel-test-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
  });
  tearDown(() async {
    store.dispose();
    await temp.delete(recursive: true);
  });

  test(
    'installs a validated native example without granting capabilities',
    () async {
      await PhoneControlMiniApp.ensureInstalled(store);
      final app = store.byId('phone-control')!;
      expect(app.formatVersion, 2);
      expect(app.uiEngine, MiniAppUiEngine.native);
      expect(app.serverCommand, isNull);
      final screen = jsonDecode(await File(app.entryPath).readAsString());
      MiniAppManifest.validateScreen(screen, app.actions);
      final permissions = MiniAppPermissions(store);
      addTearDown(permissions.dispose);
      expect(await permissions.granted(app.id), isEmpty);
      expect(app.permissions, contains('actions.ai'));
      final handlers = <String>{};
      for (final action in app.actions) {
        if (action.executor['kind'] == 'native') {
          handlers.add(action.executor['handler'] as String);
        }
      }
      expect(handlers, containsAll(MiniAppDeviceService.handlers));
      expect(
        app.actions.where((a) => a.executor['kind'] == 'preset'),
        hasLength(3),
      );
      expect(
        app.actions.where((a) => a.executor['kind'] == 'restore'),
        hasLength(1),
      );
      expect(
        screen['title'].keys,
        containsAll(['en', 'ru', 'zh', 'zh_Hans', 'zh_Hant']),
      );
      final components = [
        for (final card in screen['components']) ...?card['children'],
      ];
      expect(
        components.where(
          (component) =>
              component['bind'] == 'device.system.uptimeMs' &&
              component['format'] == 'duration',
        ),
        hasLength(1),
      );
      expect(
        components.where(
          (component) =>
              component['bind'] == 'device.battery.levelPercent' &&
              component['type'] == 'indicator',
        ),
        hasLength(1),
      );
      expect(
        components.where(
          (component) =>
              component['type'] == 'list' &&
              component['action'] == 'settings' &&
              component['args']['page'] == 'app_details' &&
              component['args']['packageName'] is Map,
        ),
        hasLength(1),
      );
      expect(
        components.where(
          (component) =>
              component['action'] == 'settings' &&
              component['args']['page'] == 'dnd_access',
        ),
        hasLength(1),
      );
    },
  );

  test('does not replace a user app or its stored data', () async {
    final source = Directory(p.join(temp.path, 'custom'))..createSync();
    File(p.join(source.path, MiniAppStore.manifestFile)).writeAsStringSync(
      jsonEncode({'id': 'phone-control', 'name': 'My custom panel'}),
    );
    File(p.join(source.path, 'index.html')).writeAsStringSync('<p>mine</p>');
    await store.install(source);
    await store.storageSet('phone-control', 'custom', 42);
    final original = store.byId('phone-control');
    await PhoneControlMiniApp.ensureInstalled(store);
    expect(identical(original, store.byId('phone-control')), isTrue);
    expect(await store.storageGet('phone-control', 'custom'), 42);
    expect(await store.versions('phone-control'), isEmpty);
  });

  test('concurrent initializers create one copy', () async {
    await Future.wait([
      PhoneControlMiniApp.ensureInstalled(store),
      PhoneControlMiniApp.ensureInstalled(store),
    ]);
    expect(store.apps, hasLength(1));
    expect(await store.versions('phone-control'), isEmpty);
  });

  test(
    'user app wins when installed during built-in installation IO',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      var rootCalls = 0;
      final racingStore = MiniAppStore(
        root: () async {
          rootCalls++;
          if (rootCalls == 2) {
            reached.complete();
            await release.future;
          }
          return Directory(p.join(temp.path, 'racing-apps'));
        },
      );
      addTearDown(racingStore.dispose);
      final source = Directory(p.join(temp.path, 'race-custom'))..createSync();
      File(p.join(source.path, MiniAppStore.manifestFile)).writeAsStringSync(
        jsonEncode({'id': 'phone-control', 'name': 'User custom panel'}),
      );
      File(p.join(source.path, 'index.html')).writeAsStringSync('<p>user</p>');
      final builtin = PhoneControlMiniApp.ensureInstalled(racingStore);
      await reached.future.timeout(const Duration(seconds: 5));
      await racingStore.install(source);
      await racingStore.storageSet('phone-control', 'owned', true);
      final original = racingStore.byId('phone-control');
      release.complete();
      await builtin;
      expect(racingStore.byId('phone-control'), same(original));
      expect(await racingStore.storageGet('phone-control', 'owned'), isTrue);
      expect(
        await File(original!.entryPath).readAsString(),
        contains('<p>user</p>'),
      );
    },
  );
}
