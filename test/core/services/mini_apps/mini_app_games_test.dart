import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_check.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

void main() {
  late Directory temp;
  late Directory root;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-games-');
    root = Directory(p.join(temp.path, 'installed'));
    store = MiniAppStore(root: () async => root, now: () => DateTime(2026, 9));
  });
  tearDown(() => temp.delete(recursive: true));

  Future<MiniApp> install(Map<String, Object?> manifest) async {
    final dir = Directory(p.join(temp.path, 'src'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, MiniAppStore.manifestFile),
    ).writeAsString(jsonEncode({'id': 'snake', 'name': 'Snake', ...manifest}));
    await File(p.join(dir.path, 'index.html')).writeAsString('<canvas>');
    return (await store.install(dir)).app;
  }

  test('game settings of the manifest are kept and read back', () async {
    final game = await install({
      'fullscreen': true,
      'orientation': 'landscape',
      'keepAwake': true,
    });
    expect(game.fullscreen, isTrue);
    expect(game.orientation, MiniAppOrientation.landscape);
    expect(game.keepAwake, isTrue);

    final reopened = MiniAppStore(root: () async => root);
    await reopened.load();
    final loaded = reopened.byId('snake')!;
    expect(loaded.fullscreen, isTrue);
    expect(loaded.orientation, MiniAppOrientation.landscape);
    expect(loaded.keepAwake, isTrue);

    // An ordinary app keeps the defaults and writes none of them.
    final plain = await install({});
    expect(plain.fullscreen, isFalse);
    expect(plain.orientation, MiniAppOrientation.any);
    expect(plain.keepAwake, isFalse);
    expect(plain.toJson().keys, isNot(contains('orientation')));
  });

  test('invalid game settings are refused', () async {
    for (final (manifest, code) in [
      ({'orientation': 'sideways'}, 'invalid_orientation'),
      ({'fullscreen': 'yes'}, 'invalid_manifest'),
      ({'keepAwake': 1}, 'invalid_manifest'),
    ]) {
      await expectLater(
        install(manifest),
        throwsA(isA<MiniAppException>().having((e) => e.code, 'code', code)),
        reason: '$manifest',
      );
    }
    expect(store.apps, isEmpty);
  });

  group('bridge', () {
    late List<Object> host;
    late MiniAppBridge bridge;

    setUp(() async {
      await install({'fullscreen': true, 'orientation': 'portrait'});
      host = [];
      bridge = MiniAppBridge(
        store: store,
        appId: 'snake',
        host: MiniAppHost(
          vibrate: (pattern) async => host.add(pattern),
          haptic: (kind) async => host.add(kind),
          close: () async => host.add('close'),
        ),
      );
    });

    Future<(bool, Object?)> call(String method, [Object? args]) async {
      final script = await bridge.handle(
        jsonEncode({'id': 1, 'method': method, 'args': args ?? {}}),
      );
      final match = RegExp(
        r'^window\.__moruReply\(1, (true|false), (.*)\);$',
      ).firstMatch(script!)!;
      return (match[1] == 'true', jsonDecode(match[2]!));
    }

    test('vibrate takes milliseconds or a pattern within bounds', () async {
      expect((await call('vibrate', {'pattern': 80})).$1, isTrue);
      expect(
        (await call('vibrate', {
          'pattern': [100, 50, 100.4],
        })).$1,
        isTrue,
      );
      expect(host, [
        [80],
        [100, 50, 100],
      ]);
      for (final bad in [
        null,
        -5,
        'long',
        [],
        [100, 'x'],
        List.filled(MiniAppBridge.maxVibrationSegments + 1, 10),
        [MiniAppBridge.maxVibrationMs + 1],
      ]) {
        final (ok, message) = await call('vibrate', {'pattern': bad});
        expect(ok, isFalse, reason: '$bad');
        expect(message, contains('pattern'), reason: '$bad');
      }
      expect(host, hasLength(2));
    });

    test('haptic accepts the known kinds only', () async {
      expect((await call('haptic', {})).$1, isTrue);
      expect((await call('haptic', {'kind': 'heavy'})).$1, isTrue);
      expect((await call('haptic', {'kind': 'boom'})).$1, isFalse);
      expect(host, ['light', 'heavy']);
    });

    test('the app can close itself and learn its display', () async {
      expect((await call('app.close')).$1, isTrue);
      expect(host, ['close']);
      final (ok, info) = await call('app.info');
      expect(ok, isTrue);
      expect(info, containsPair('fullscreen', true));
      expect(info, containsPair('orientation', 'portrait'));
    });
  });

  test('the publish check accepts games that vibrate and close', () async {
    final game = await install({'fullscreen': true});
    final sandbox = await MiniAppSandbox.create(game);
    addTearDown(sandbox.dispose);
    for (final method in ['vibrate', 'haptic', 'app.close']) {
      await sandbox.bridge.handle(
        jsonEncode({
          'id': 1,
          'method': method,
          'args': {'pattern': 50},
        }),
      );
    }
    expect(sandbox.bridge.failedCalls, isEmpty);
  });
}
