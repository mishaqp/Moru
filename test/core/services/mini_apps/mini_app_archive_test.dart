import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

void main() {
  late Directory temp;
  late MiniAppStore home;

  MiniAppStore storeAt(String name) =>
      MiniAppStore(root: () async => Directory(p.join(temp.path, name)));

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-apps-archive-');
    home = storeAt('home');
    final dir = Directory(p.join(temp.path, 'src'))..createSync();
    File(p.join(dir.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'water',
        'name': 'Water',
        'description': 'Tracks water',
        'icon': 'icon.svg',
        'data': 'log: list',
        'network': ['api.example.com'],
        'permissions': ['calendar'],
      }),
    );
    File(p.join(dir.path, 'index.html')).writeAsStringSync('<p>x</p>');
    File(p.join(dir.path, 'icon.svg')).writeAsStringSync('<svg/>');
    Directory(p.join(dir.path, 'js')).createSync();
    File(p.join(dir.path, 'js', 'app.js')).writeAsStringSync('1;');
    await home.install(dir);
    await home.storageSet('water', 'log', [250, 500]);
  });
  tearDown(() => temp.delete(recursive: true));

  Future<File> export({required bool withData}) => home.exportArchive(
    'water',
    withData: withData,
    into: Directory(p.join(temp.path, 'out')),
  );

  test('an exported app installs elsewhere with its files and data', () async {
    final file = await export(withData: true);
    expect(p.basename(file.path), 'water.moruapp');
    final names = ZipDecoder()
        .decodeBytes(file.readAsBytesSync())
        .files
        .map((f) => f.name)
        .toSet();
    expect(names, {
      'moru-app.json',
      'index.html',
      'icon.svg',
      'js/app.js',
      '.moru-data.json',
    });

    final other = storeAt('other');
    final result = await other.importArchive(file);
    expect(result.updated, isFalse);
    expect(result.dataRestored, isTrue);
    final app = other.byId('water')!;
    expect(app.name, 'Water');
    expect(app.dataHelp, 'log: list');
    expect(app.network, ['api.example.com']);
    expect(app.permissions, {'calendar'});
    expect(await other.storageGet('water', 'log'), [250, 500]);
    expect(
      File(p.join(app.codeDirectory, 'js', 'app.js')).readAsStringSync(),
      '1;',
    );
    expect(
      File(p.join(app.codeDirectory, MiniAppStore.bridgeFile)).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(app.codeDirectory, MiniAppStore.archiveDataFile),
      ).existsSync(),
      isFalse,
    );
  });

  test('without data only the app travels', () async {
    final file = await export(withData: false);
    final other = storeAt('other');
    final result = await other.importArchive(file);
    expect(result.dataRestored, isFalse);
    expect(await other.storageKeys('water'), isEmpty);
  });

  test('importing never overwrites data already stored', () async {
    final file = await export(withData: true);
    await home.storageSet('water', 'log', [1]);
    final result = await home.importArchive(file);
    expect(result.updated, isTrue);
    expect(result.dataRestored, isFalse);
    expect(await home.storageGet('water', 'log'), [1]);
  });

  test('damaged and unsafe files are refused', () async {
    final junk = File(p.join(temp.path, 'junk.moruapp'))
      ..writeAsStringSync('not a zip');
    await expectLater(
      home.importArchive(junk),
      throwsA(
        isA<MiniAppException>().having(
          (e) => e.code,
          'code',
          'invalid_archive',
        ),
      ),
    );

    final evil = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'moru-app.json',
          utf8.encode(jsonEncode({'id': 'evil', 'name': 'Evil'})),
        ),
      )
      ..addFile(ArchiveFile.bytes('index.html', utf8.encode('x')))
      ..addFile(ArchiveFile.bytes('../../escape.txt', utf8.encode('x')));
    final evilFile = File(p.join(temp.path, 'evil.moruapp'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(evil));
    await expectLater(
      home.importArchive(evilFile),
      throwsA(isA<MiniAppException>()),
    );
    expect(File(p.join(temp.path, 'escape.txt')).existsSync(), isFalse);
    expect(home.byId('evil'), isNull);
    // No staging folders are left behind.
    expect(
      Directory(p.join(temp.path, 'home'))
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name.startsWith('.')),
      isEmpty,
    );
  });
}
