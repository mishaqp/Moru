import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

void main() {
  late Directory temp;
  late Directory root;
  late MiniAppStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-apps-');
    root = Directory(p.join(temp.path, 'installed'));
    store = MiniAppStore(root: () async => root, now: () => DateTime(2026, 9));
  });
  tearDown(() => temp.delete(recursive: true));

  Future<Directory> source(
    Map<String, Object?> manifest, {
    Map<String, String> files = const {
      'index.html': '<html><head><title>W</title></head><body></body></html>',
      'app.js': 'console.log(1)',
      'icon.svg': '<svg xmlns="http://www.w3.org/2000/svg"/>',
    },
  }) async {
    final dir = Directory(p.join(temp.path, 'src-${manifest['id']}'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, MiniAppStore.manifestFile),
    ).writeAsString(jsonEncode(manifest));
    for (final entry in files.entries) {
      final file = File(p.join(dir.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    return dir;
  }

  test('install copies the app, loads the bridge and lists it', () async {
    final dir = await source({
      'id': 'water',
      'name': 'Water',
      'description': 'Track water',
      'icon': 'icon.svg',
    });
    await Directory(
      p.join(dir.path, 'node_modules', 'x'),
    ).create(recursive: true);
    await File(
      p.join(dir.path, 'node_modules', 'x', 'big.js'),
    ).writeAsString('skip me');

    final result = await store.install(dir);

    expect(result.updated, isFalse);
    expect(result.files, 3);
    final app = result.app;
    expect(app.link, 'kelivo://app/water');
    expect(store.apps.map((a) => a.id), ['water']);
    final html = await File(app.entryPath).readAsString();
    expect(html, contains('<head><script src="moru.js"></script><title>'));
    expect(
      await File(p.join(app.codeDirectory, 'moru.js')).readAsString(),
      MiniAppStore.moruBridgeScript,
    );
    expect(
      File(p.join(app.codeDirectory, 'node_modules')).existsSync(),
      isFalse,
    );
    expect(app.iconPath, p.join(app.codeDirectory, 'icon.svg'));

    // A fresh store finds the installed app on disk.
    final reopened = MiniAppStore(root: () async => root);
    await reopened.load();
    expect(reopened.byId('water')?.description, 'Track water');
  });

  test('republishing replaces the code and keeps the data', () async {
    await store.install(await source({'id': 'water', 'name': 'Water'}));
    await store.storageSet('water', 'glasses', [1, 2]);

    final result = await store.install(
      await source(
        {'id': 'water', 'name': 'Water 2'},
        files: {'index.html': '<p>v2</p>'},
      ),
    );

    expect(result.updated, isTrue);
    expect(store.apps.single.name, 'Water 2');
    expect(await store.storageGet('water', 'glasses'), [1, 2]);
    expect(
      File(p.join(result.app.codeDirectory, 'app.js')).existsSync(),
      isFalse,
    );
    expect(
      await File(result.app.entryPath).readAsString(),
      '<script src="moru.js"></script><p>v2</p>',
    );
  });

  test('bad manifests are refused and leave nothing behind', () async {
    Future<String> code(
      Map<String, Object?> manifest, [
      Map<String, String>? files,
    ]) async {
      try {
        await store.install(
          await source(manifest, files: files ?? const {'index.html': 'x'}),
        );
      } on MiniAppException catch (e) {
        return e.code;
      }
      return 'ok';
    }

    expect(await code({'id': 'Bad Id', 'name': 'X'}), 'invalid_id');
    expect(await code({'id': 'a', 'name': ''}), 'invalid_name');
    expect(
      await code({'id': 'b', 'name': 'B', 'entry': 'main.html'}),
      'missing_entry',
    );
    expect(
      await code({'id': 'c', 'name': 'C', 'entry': '../x.html'}),
      'invalid_path',
    );
    expect(
      await code(
        {'id': 'd', 'name': 'D', 'icon': 'i.png'},
        {'index.html': 'x', 'i.png': 'x'},
      ),
      'invalid_icon',
    );
    final empty = Directory(p.join(temp.path, 'empty'))..createSync();
    expect(
      () => store.install(empty),
      throwsA(
        isA<MiniAppException>().having(
          (e) => e.code,
          'code',
          'missing_manifest',
        ),
      ),
    );
    expect(store.apps, isEmpty);
  });

  test('delete removes the app and its data', () async {
    await store.install(await source({'id': 'notes', 'name': 'Notes'}));
    await store.storageSet('notes', 'a', 1);
    final dir = store.byId('notes')!.directory;
    await store.delete('notes');
    expect(store.apps, isEmpty);
    expect(Directory(dir).existsSync(), isFalse);
  });

  test('links map to app ids', () {
    expect(MiniAppStore.idFromLink('kelivo://app/water'), 'water');
    expect(MiniAppStore.idFromLink('KELIVO://app/water-2/'), 'water-2');
    expect(MiniAppStore.idFromLink('kelivo://workspace/water'), isNull);
    expect(MiniAppStore.idFromLink('kelivo://app/../x'), isNull);
  });

  test('bridge scripts nested entries relative to the app root', () {
    expect(
      MiniAppStore.withBridgeScript('<body></body>', 'pages/main.html'),
      '<script src="../moru.js"></script><body></body>',
    );
    expect(
      MiniAppStore.withBridgeScript(
        '<script src="moru.js"></script>',
        'index.html',
      ),
      '<script src="moru.js"></script>',
    );
  });

  test('the bridge answers storage calls and reports errors', () async {
    await store.install(await source({'id': 'water', 'name': 'Water'}));
    final bridge = MiniAppBridge(store: store, appId: 'water');
    Future<String> call(Map<String, Object?> message) async =>
        (await bridge.handle(jsonEncode(message)))!;

    expect(
      await call({
        'id': 1,
        'method': 'storage.set',
        'args': {
          'key': 'goal',
          'value': {'ml': 2000},
        },
      }),
      'window.__moruReply(1, true, null);',
    );
    expect(
      await call({
        'id': 2,
        'method': 'storage.get',
        'args': {'key': 'goal'},
      }),
      'window.__moruReply(2, true, {"ml":2000});',
    );
    expect(
      await call({'id': 3, 'method': 'storage.keys'}),
      'window.__moruReply(3, true, ["goal"]);',
    );
    expect(
      await call({
        'id': 4,
        'method': 'storage.remove',
        'args': {'key': 'goal'},
      }),
      'window.__moruReply(4, true, null);',
    );
    expect(
      await call({
        'id': 5,
        'method': 'storage.get',
        'args': {'key': 'goal'},
      }),
      'window.__moruReply(5, true, null);',
    );
    expect(
      await call({
        'id': 6,
        'method': 'storage.set',
        'args': {'key': ''},
      }),
      startsWith('window.__moruReply(6, false, "Keys must be'),
    );
    expect(
      await call({'id': 7, 'method': 'files.delete'}),
      'window.__moruReply(7, false, "Unknown method \\"files.delete\\".");',
    );
    expect(
      await call({'id': 8, 'method': 'app.info'}),
      'window.__moruReply(8, true, {"id":"water","name":"Water","platform":"android"});',
    );
  });

  test('parallel writes are all kept', () async {
    await store.install(await source({'id': 'water', 'name': 'Water'}));
    await Future.wait([
      for (var i = 0; i < 20; i++) store.storageSet('water', 'k$i', i),
    ]);
    expect((await store.storageKeys('water')).length, 20);
  });
}
