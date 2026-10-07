import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late MiniAppStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-browser-storage-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
  });
  tearDown(() async {
    store.dispose();
    await temp.delete(recursive: true);
  });

  File marker(MiniApp app) =>
      File(p.join(app.directory, '.browser-storage.json'));

  test(
    'upgrade remembers the original file URL before a code update',
    () async {
      final directory = p.join(temp.path, 'apps', 'old-game');
      final old = MiniApp(
        id: 'old-game',
        name: 'Game',
        directory: directory,
        entry: 'pages/old.html',
        updatedAt: DateTime.utc(2025),
      );
      await Directory(old.codeDirectory).create(recursive: true);
      await File(
        p.join(directory, 'manifest.json'),
      ).writeAsString(jsonEncode(old.toJson()));
      await File(old.entryPath).create(recursive: true);
      await store.load();
      expect(await marker(old).exists(), isTrue);
      final state = jsonDecode(await marker(old).readAsString()) as Map;
      expect(state['legacyUrl'], Uri.file(old.entryPath).toString());
      expect(state['complete'], isFalse);

      final source = Directory(p.join(temp.path, 'replacement'));
      await source.create();
      await File(p.join(source.path, 'index.html')).writeAsString('new code');
      await store.install(
        source,
        manifest: {'id': old.id, 'name': old.name, 'entry': 'index.html'},
      );
      expect(store.byId(old.id)!.entry, 'index.html');
      expect(jsonDecode(await marker(old).readAsString()), state);
    },
  );

  test('fresh apps never inherit the old shared file storage', () async {
    final source = Directory(p.join(temp.path, 'new-game'));
    await source.create();
    await File(p.join(source.path, 'index.html')).writeAsString('new app');
    final app = (await store.install(
      source,
      manifest: {'id': 'new-game', 'name': 'New game'},
    )).app;
    expect(await marker(app).exists(), isTrue);
    final state = jsonDecode(await marker(app).readAsString()) as Map;
    expect(state['complete'], isTrue);
    expect(state['legacyUrl'], isNull);
  });
}
