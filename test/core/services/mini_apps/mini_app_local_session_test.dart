import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_local_session.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  late HttpClient client;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-local-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    for (final id in ['one', 'two']) {
      final src = Directory(p.join(temp.path, id))..createSync();
      File(p.join(src.path, 'moru-app.json')).writeAsStringSync(
        jsonEncode({'id': id, 'name': id, 'entry': 'pages/start.html'}),
      );
      File(p.join(src.path, 'pages/start.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<head></head><p>$id</p>');
      File(
        p.join(src.path, 'pages/main.mjs'),
      ).writeAsStringSync('export const id = "$id";');
      await store.install(src);
    }
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await temp.delete(recursive: true);
  });

  Future<({int status, String body})> get(Uri uri) async {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decodeStream(response),
    );
  }

  test(
    'each WebView has an isolated loopback origin and capability path',
    () async {
      final app = store.byId('one')!;
      final first = await MiniAppLocalSession.start(store: store, app: app);
      final second = await MiniAppLocalSession.start(store: store, app: app);
      addTearDown(first.close);
      addTearDown(second.close);
      final uri = first.entryUri(app);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      expect(second.entryUri(app).port, isNot(uri.port));
      expect(uri.pathSegments.first.length, greaterThanOrEqualTo(32));
      expect(
        second.entryUri(app).pathSegments.first,
        isNot(uri.pathSegments.first),
      );
      expect(first.allowsNavigation(uri.toString()), isTrue);
      expect(
        first.allowsNavigation(uri.resolve('main.mjs').toString()),
        isTrue,
      );
      expect(first.allowsNavigation(second.entryUri(app).toString()), isFalse);
      expect(first.allowsNavigation('https://example.com/'), isFalse);
      expect(first.allowsNavigation('file:///etc/passwd'), isFalse);
      expect((await get(uri)).body, contains('src="../moru.js"'));
      expect(
        (await get(uri.resolve('main.mjs'))).body,
        'export const id = "one";',
      );
      final token = uri.pathSegments.first;
      for (final path in [
        '/app/one/pages/start.html',
        '/wrong/app/one/pages/start.html',
        '/$token/app/two/pages/start.html',
        '/$token/app/one/__moru',
        '/$token/app/one/..%2Fmanifest.json',
      ]) {
        final candidate = uri.replace(path: path);
        expect((await get(candidate)).status, 404, reason: path);
        expect(
          first.allowsNavigation(
            uri.replace(path: '/$token/app/two/').toString(),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'old apps receive the current bridge and closing releases the port',
    () async {
      final app = store.byId('one')!;
      await File(
        p.join(app.codeDirectory, 'moru.js'),
      ).writeAsString('old bridge');
      final session = await MiniAppLocalSession.start(
        store: store,
        app: app,
        bootstrapScript: () => 'window.themeWasSet = true;',
      );
      final uri = session.entryUri(app);
      final script = (await get(uri.resolve('../moru.js'))).body;
      expect(script, contains(MiniAppStore.moruBridgeScript));
      expect(script, contains('__moruAssetCatalog'));
      expect(script, contains('window.themeWasSet = true;'));
      expect(script, isNot(contains('fetch(endpoint')));
      await session.close();
      expect(session.allowsNavigation(uri.toString()), isFalse);
      await expectLater(
        Socket.connect(uri.host, uri.port),
        throwsA(isA<SocketException>()),
      );
      await session.close();
    },
  );

  test('resources stay inside the app and reject encoded separators', () async {
    final app = store.byId('one')!;
    final session = await MiniAppLocalSession.start(store: store, app: app);
    addTearDown(session.close);
    final uri = session.entryUri(app);
    final secret = File(p.join(temp.path, 'secret.txt'));
    await secret.writeAsString('outside app');
    await Link(p.join(app.codeDirectory, 'secret.txt')).create(secret.path);
    await Link(
      p.join(app.codeDirectory, 'inside.mjs'),
    ).create(p.join(app.codeDirectory, 'pages/main.mjs'));
    expect((await get(uri.resolve('../secret.txt'))).status, 404);
    expect((await get(uri.resolve('../inside.mjs'))).body, contains('one'));
    final root = uri.resolve('../');
    for (final path in [
      'pages%2Fmain.mjs',
      'pages%5Cmain.mjs',
      '%252e%252e/moru.js',
    ]) {
      expect((await get(Uri.parse('$root$path'))).status, 404, reason: path);
    }
  });
}
