import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_publisher.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';

void main() {
  late Directory temp;
  late Directory workspace;
  late MiniAppStore store;
  late MiniAppPublisher publisher;
  late WorkspaceFileAccess access;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moru-publish-');
    workspace = Directory(p.join(temp.path, 'workspace'))..createSync();
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
      now: () => DateTime(2026, 10, 6),
    );
    publisher = MiniAppPublisher(store: store);
    access = WorkspaceFileAccess(roots: [workspace.path]);
  });
  tearDown(() async { store.dispose(); await temp.delete(recursive: true); });

  Directory source(String folder, Map<String, String> files) {
    final dir = Directory(p.join(workspace.path, folder))..createSync(recursive: true);
    for (final file in files.entries) {
      File(p.join(dir.path, file.key))
        ..createSync(recursive: true)
        ..writeAsStringSync(file.value);
    }
    return dir;
  }

  Future<MiniApp> initial() async => (await publisher.publish(
    source: source('project/dist', {
      'moru-app.json': jsonEncode({'id':'game','name':'Game',
        'data':'score: number', 'orientation':'landscape',
        'network':['example.com'], 'server':{'command':'node server.js'}}),
      'index.html':'<html><head></head><body>game<script type="module" src="./assets/main.js"></script></body></html>',
      'assets/main.js':'export const score=1;', 'assets/style.css':'body{margin:0}',
      'server.js':'console.log("server");',
    }), access: access,
  )).app;

  test('publishes built dist with modules and large binary assets, not node_modules', () async {
    final dist = source('vite/dist', {
      'moru-app.json':'{"id":"vite","name":"Vite"}',
      'index.html':'<script type="module" src="./assets/main.js"></script>',
      'assets/main.js':'export const url=new URL("./текст.bin",import.meta.url);',
      'node_modules/unused.js':'must not be published',
    });
    final bytes = List.generate(3 * 1024 * 1024 + 7, (i) => i % 251);
    File(p.join(dist.path, 'assets/текст.bin')).writeAsBytesSync(bytes);
    final result = await publisher.publish(source: dist, access: access);
    expect(result.updated, isFalse);
    expect(result.files, 3);
    expect(await File(p.join(result.app.codeDirectory, 'assets/текст.bin')).readAsBytes(), bytes);
    expect(await File(result.app.entryPath).readAsString(), contains('moru.js'));
    expect(Directory(p.join(result.app.codeDirectory, 'node_modules')).existsSync(), isFalse);
    // The installed app is independent of later builds and workspace deletion.
    await dist.delete(recursive: true);
    expect(await File(p.join(result.app.codeDirectory, 'assets/текст.bin')).length(), bytes.length);
  });

  test('patches selected files, preserves metadata/data/jobs/server and rolls back', () async {
    final first = await initial();
    await store.storageSet('game', 'score', 42);
    File(p.join(first.directory, 'jobs.json')).writeAsStringSync('{"daily":{"function":"tick"}}');
    File(p.join(first.directory, 'server-data/save.bin'))
      ..createSync(recursive: true)..writeAsBytesSync([1,2,3]);
    final patch = source('patch', {
      'assets/style.css':'body{color:red}',
      'assets/main.js':'export const score=2;',
      'ignored.txt':'do not publish',
      'moru-app.json':'{"id":"different","name":"Wrong"}',
    });
    final result = await publisher.publish(source: patch, access: access,
      appId:'game', files:['assets/main.js','assets/style.css']);
    expect(result.updated, isTrue);
    final app = result.app;
    expect(app.name, first.name);
    expect(app.serverCommand, first.serverCommand);
    expect(app.orientation, first.orientation);
    expect(app.network, first.network);
    expect(await store.storageGet('game','score'), 42);
    expect(await File(p.join(app.codeDirectory,'assets/main.js')).readAsString(), contains('score=2'));
    expect(File(p.join(app.codeDirectory,'ignored.txt')).existsSync(), isFalse);
    expect(await File(p.join(app.directory,'jobs.json')).readAsString(), contains('daily'));
    expect(await File(p.join(app.directory,'server-data/save.bin')).readAsBytes(), [1,2,3]);
    final versions = await store.versions('game');
    expect(versions, hasLength(1));
    final restored = await store.rollback('game',MiniAppStore.versionOf(versions.single));
    expect(await File(p.join(restored.codeDirectory,'assets/main.js')).readAsString(), contains('score=1'));
    expect(await store.storageGet('game','score'),42);
    final archive = await store.exportArchive('game', withData:true,
      into:Directory(p.join(temp.path,'export')));
    final other = MiniAppStore(root:() async => Directory(p.join(temp.path,'imported')));
    addTearDown(other.dispose);
    final imported = await other.importArchive(archive);
    expect(imported.dataRestored, isTrue);
    expect(await other.storageGet('game','score'),42);
  });

  test('concurrent patches keep both changes and five distinct rollback versions', () async {
    await initial();
    final a = source('a',{'assets/main.js':'export const score=9;'});
    final b = source('b',{'assets/style.css':'body{color:blue}'});
    await Future.wait([
      publisher.publish(source:a,access:access,appId:'game',files:['assets/main.js']),
      publisher.publish(source:b,access:access,appId:'game',files:['assets/style.css']),
    ]);
    final app = store.byId('game')!;
    expect(await File(p.join(app.codeDirectory,'assets/main.js')).readAsString(), contains('score=9'));
    expect(await File(p.join(app.codeDirectory,'assets/style.css')).readAsString(), contains('blue'));
    for (var i=0;i<5;i++) {
      await publisher.publish(source:a,access:access,appId:'game',files:['assets/main.js']);
    }
    final versions = await store.versions('game');
    expect(versions,hasLength(5));
    expect(versions.map(MiniAppStore.versionOf).toSet(),hasLength(5));
  });

  test('invalid patch or deletion leaves code, data and versions untouched', () async {
    final app = await initial();
    await store.storageSet('game','score',7);
    final patch = source('patch', {'assets/main.js':'new'});
    for (final files in [['../escape'],['moru.js'],['missing.js']]) {
      await expectLater(publisher.publish(source:patch,access:access,appId:'game',files:files),throwsException);
    }
    await expectLater(publisher.publish(source:patch,access:access,
      appId:'game',files:[],deleteFiles:['index.html']),throwsA(isA<MiniAppException>()));
    expect(await File(p.join(app.codeDirectory,'assets/main.js')).readAsString(),contains('score=1'));
    expect(await store.versions('game'),isEmpty);
    expect(await store.storageGet('game','score'),7);
    await publisher.publish(source:patch,access:access,
      appId:'game',files:[],deleteFiles:['assets/style.css']);
    expect(File(p.join(app.codeDirectory,'assets/style.css')).existsSync(),isFalse);
  });

  test('internal links work, but outward and ancestor-swap links never leak', () async {
    final dist=source('links',{'moru-app.json':'{"id":"links","name":"Links"}',
      'index.html':'<p>links</p>','assets/data.txt':'allowed'});
    Link(p.join(dist.path,'inside.txt')).createSync(p.join(dist.path,'assets/data.txt'));
    final result = await publisher.publish(source:dist,access:access);
    expect(await File(p.join(result.app.codeDirectory,'inside.txt')).readAsString(),'allowed');
    final secret=File(p.join(temp.path,'secret.txt'))..writeAsStringSync('secret');
    Link(p.join(dist.path,'escape.txt')).createSync(secret.path);
    await expectLater(publisher.publish(source:dist,access:access),throwsException);
    expect(await store.versions('links'),isEmpty);
    expect(File(p.join(result.app.codeDirectory,'escape.txt')).existsSync(),isFalse);
    final outside=Directory(p.join(temp.path,'outside'))..createSync();
    var swapped=false;
    final raceAccess=WorkspaceFileAccess(roots:[workspace.path],beforeOpen:(path) async {
      if (!swapped && path==dist.path) {
        swapped=true;
        await dist.rename('${dist.path}-old');
        await Link(dist.path).create(outside.path);
      }
    });
    await expectLater(publisher.publish(source:dist,access:raceAccess),throwsException);
    expect(swapped,isTrue);
  });
}
