import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';

void main() {
  late Directory temp;
  late Directory root;
  late DateTime clock;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-versions-');
    root = Directory(p.join(temp.path, 'installed'));
    clock = DateTime(2026, 9, 1, 10);
    store = MiniAppStore(root: () async => root, now: () => clock);
  });
  tearDown(() => temp.delete(recursive: true));

  /// Publishes version [n] of the app a minute after the previous one.
  Future<MiniApp> publish(int n, {String name = 'Water'}) async {
    clock = clock.add(const Duration(minutes: 1));
    final dir = Directory(p.join(temp.path, 'src'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, MiniAppStore.manifestFile),
    ).writeAsString(jsonEncode({'id': 'water', 'name': name}));
    await File(p.join(dir.path, 'index.html')).writeAsString('<p>v$n</p>');
    return (await store.install(dir)).app;
  }

  Future<String> code(MiniApp app) => File(app.entryPath).readAsString();

  Future<Map<String, dynamic>> tool(Map<String, dynamic> args) async =>
      jsonDecode(await MiniAppDataTool(store: store).execute(args))
          as Map<String, dynamic>;

  test('republishing keeps the previous code as a version', () async {
    final first = await publish(1);
    expect(await store.versions('water'), isEmpty);

    final second = await publish(2, name: 'Water 2');
    expect(await code(second), contains('v2'));
    final versions = await store.versions('water');
    expect(versions, hasLength(1));
    expect(versions.single.updatedAt, first.updatedAt);
    expect(versions.single.name, 'Water');
    expect(await code(versions.single), contains('v1'));
  });

  test('only the newest five versions are kept', () async {
    for (var n = 1; n <= 8; n++) {
      await publish(n);
    }
    final versions = await store.versions('water');
    expect(
      [for (final v in versions) await code(v)],
      [
        contains('v7'),
        contains('v6'),
        contains('v5'),
        contains('v4'),
        contains('v3'),
      ],
    );
  });

  test('rollback restores the code, keeps data and can be undone', () async {
    final first = await publish(1);
    await store.storageSet('water', 'glasses', 3);
    await publish(2);

    final restored = await store.rollback(
      'water',
      MiniAppStore.versionOf(first),
    );

    expect(restored.updatedAt, first.updatedAt);
    expect(store.byId('water')!.updatedAt, first.updatedAt);
    expect(await code(restored), contains('v1'));
    expect(
      await File(p.join(restored.codeDirectory, 'moru.js')).readAsString(),
      MiniAppStore.moruBridgeScript,
    );
    expect(await store.storageGet('water', 'glasses'), 3);
    final versions = await store.versions('water');
    expect(versions, hasLength(1));
    expect(await code(versions.single), contains('v2'));

    // A fresh store reads the restored manifest from disk.
    final reopened = MiniAppStore(root: () async => root);
    await reopened.load();
    expect(reopened.apps.single.updatedAt, first.updatedAt);

    await store.rollback('water', MiniAppStore.versionOf(versions.single));
    expect(await code(store.byId('water')!), contains('v2'));
  });

  test('rollback refuses unknown versions and leaves the app alone', () async {
    await publish(1);
    await publish(2);
    for (final version in ['123', '../app', '']) {
      await expectLater(
        store.rollback('water', version),
        throwsA(
          isA<MiniAppException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
    }
    expect(await code(store.byId('water')!), contains('v2'));
    expect(await store.versions('water'), hasLength(1));
  });

  test('a leftover staging folder is not loaded as an app', () async {
    await publish(1);
    final leftover = Directory(p.join(root.path, '.water.rollback'));
    await leftover.create();
    await File(
      p.join(leftover.path, 'manifest.json'),
    ).writeAsString(jsonEncode({'id': 'water', 'name': 'Old'}));

    final reopened = MiniAppStore(root: () async => root);
    await reopened.load();
    expect(reopened.apps.map((a) => a.name), ['Water']);
  });

  test('the error journal merges repeats, keeps the last 50 and resets on '
      'republish', () async {
    await publish(1);
    await store.logError('water', 'console: boom');
    await store.logError('water', 'console: boom');
    await store.logError('water', 'call: fetch: denied');
    var entries = await store.readErrors('water');
    expect(entries.map((e) => (e.message, e.count)), [
      ('console: boom', 2),
      ('call: fetch: denied', 1),
    ]);

    await Future.wait([
      for (var i = 0; i < 60; i++) store.logError('water', 'error $i'),
    ]);
    entries = await store.readErrors('water');
    expect(entries, hasLength(MiniAppStore.maxLogEntries));
    expect(entries.first.message, 'error 10');
    expect(entries.last.message, 'error 59');

    await publish(2);
    expect(await store.readErrors('water'), isEmpty);
  });

  test('the bridge passes each noted problem on with its kind', () async {
    await publish(1);
    final seen = <(String, String)>[];
    final bridge = MiniAppBridge(
      store: store,
      appId: 'water',
      onProblem: (kind, problem) => seen.add((kind, problem)),
    );
    await bridge.handle(
      jsonEncode({
        'method': '__report',
        'args': {'kind': 'resource', 'message': 'Failed to load a.js'},
      }),
    );
    await bridge.handle(jsonEncode({'id': 1, 'method': 'nope'}));
    expect(seen, [
      ('resource', 'resource: Failed to load a.js'),
      ('call', 'nope: Unknown method "nope".'),
    ]);
  });

  test('the mini_apps tool reads the journal and rolls back', () async {
    final first = await publish(1);
    await publish(2);
    await store.logError('water', 'console: x is not defined');

    final errors = await tool({
      'action': 'errors',
      'app_id': 'water',
      'clear': true,
    });
    expect(errors['ok'], isTrue);
    expect(errors['errors'], [
      {'at': clock.toIso8601String(), 'message': 'console: x is not defined'},
    ]);
    expect(await store.readErrors('water'), isEmpty);

    final versions = await tool({'action': 'versions', 'app_id': 'water'});
    expect(versions['versions'], [
      {
        'version': MiniAppStore.versionOf(first),
        'published': first.updatedAt.toIso8601String(),
      },
    ]);

    expect(
      (await tool({'action': 'rollback', 'app_id': 'water'}))['error'],
      'missing_version',
    );
    final rolled = await tool({
      'action': 'rollback',
      'app_id': 'water',
      'version': MiniAppStore.versionOf(first),
    });
    expect(rolled['ok'], isTrue, reason: '$rolled');
    expect(await code(store.byId('water')!), contains('v1'));
  });
}
