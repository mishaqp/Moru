import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_assets.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_web_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These tests exercise a real loopback HTTP server, not widget requests.
  HttpOverrides.global = null;
  late Directory temp;
  late MiniAppStore store;
  late MiniAppWebServer server;
  late HttpClient client;
  var bridges = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-web-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
    Future<void> install(
      String id,
      String name,
      Map<String, String> files, {
      String? entry,
    }) async {
      final src = Directory(p.join(temp.path, 'src-$id'))..createSync();
      File(p.join(src.path, MiniAppStore.manifestFile)).writeAsStringSync(
        jsonEncode({'id': id, 'name': name, 'entry': ?entry}),
      );
      for (final file in files.entries) {
        File(p.join(src.path, file.key))
          ..createSync(recursive: true)
          ..writeAsStringSync(file.value);
      }
      await store.install(src);
    }

    await install('notes', 'Notes <b>', {
      'index.html': '<html><head></head><body>notes</body></html>',
      'style.css': 'body{}',
    });
    await install('game', 'Game', {
      'web/play.html': '<html><head></head><body>play</body></html>',
    }, entry: 'web/play.html');
    bridges = 0;
    server = MiniAppWebServer(
      store: store,
      bridgeFor: (app) {
        bridges++;
        return MiniAppBridge(store: store, appId: app.id);
      },
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await temp.delete(recursive: true);
  });

  Future<({int status, String body, HttpHeaders headers})> get(
    String path, {
    String? password,
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.followRedirects = false;
    if (password != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64.encode(utf8.encode('any:$password'))}',
      );
    }
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decodeStream(response),
      headers: response.headers,
    );
  }

  test('lists the apps and serves their files', () async {
    await server.start(port: 0, localhostOnly: true);
    final index = await get('/');
    expect(index.status, 200);
    expect(index.body, contains('href="/app/notes/"'));
    // Names are escaped.
    expect(index.body, contains('Notes &lt;b&gt;'));

    final redirect = await get('/app/notes');
    expect(redirect.status, 301);
    expect(redirect.headers.value('location'), '/app/notes/');

    final page = await get('/app/notes/');
    expect(page.body, contains('<script src="moru.js">'));
    expect(page.headers.contentType?.mimeType, 'text/html');
    final css = await get('/app/notes/style.css');
    expect(css.body, 'body{}');
    expect(css.headers.contentType?.mimeType, 'text/css');

    // An entry in a folder opens there, so its relative paths work.
    final game = await get('/app/game/');
    expect(game.status, 302);
    expect(game.headers.value('location'), '/app/game/web/play.html');

    for (final path in [
      '/app/nope/',
      '/app/notes/missing.js',
      '/app/notes/..%2F..%2Fmanifest.json',
      '/other',
    ]) {
      expect((await get(path)).status, 404, reason: path);
    }
  });

  test('moru.js posts calls to the app bridge, sharing its data', () async {
    await server.start(port: 0, localhostOnly: true);
    final script = await get('/app/notes/moru.js');
    expect(script.body, contains('"/app/notes/__moru"'));
    expect(script.body, contains(MiniAppStore.moruBridgeScript));

    final reply = await get(
      '/app/notes/__moru',
      method: 'POST',
      body: jsonEncode({
        'id': 7,
        'method': 'storage.set',
        'args': {'key': 'n', 'value': 3},
      }),
    );
    expect(reply.body, 'window.__moruReply(7, true, null);');
    expect(await store.storageGet('notes', 'n'), 3);
    await get(
      '/app/notes/__moru',
      method: 'POST',
      body: jsonEncode({'id': 8, 'method': 'storage.keys'}),
    );
    // One bridge per app while the server runs.
    expect(bridges, 1);
    expect((await get('/app/notes/__moru')).status, 405);
  });

  test(
    'serves bundled libraries and WASM locally without copying into apps',
    () async {
      await server.start(port: 0, localhostOnly: true);
      for (final asset in MiniAppAssets.catalog.values) {
        final filename = asset['file'] as String;
        final response = await get(
          '/app/notes/__moru_assets/$filename',
          method: 'HEAD',
        );
        expect(response.status, 200, reason: filename);
        expect(response.headers.contentLength, greaterThan(0));
        final type = filename.endsWith('.wasm')
            ? 'application/wasm'
            : filename.endsWith('.css')
            ? 'text/css'
            : 'application/javascript';
        expect(response.headers.contentType?.mimeType, type);
        expect(
          File(
            p.join(store.byId('notes')!.codeDirectory, filename),
          ).existsSync(),
          isFalse,
        );
      }
      final wasm = MiniAppAssets.catalog['sqljs-wasm']!['file'];
      final request = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/app/notes/__moru_assets/$wasm',
        ),
      );
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-7');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(await response.expand((chunk) => chunk).toList(), [
        0,
        97,
        115,
        109,
        1,
        0,
        0,
        0,
      ]);
      for (final path in [
        '/app/notes/__moru_assets/not-bundled.js',
        '/app/notes/__moru_assets/..%2Fmanifest.json',
        '/app/nope/__moru_assets/$wasm',
      ]) {
        expect((await get(path)).status, 404, reason: path);
      }
      expect(bridges, 0);
    },
  );

  test('injects the current bridge into secondary HTML pages', () async {
    final code = store.byId('notes')!.codeDirectory;
    final page = File(p.join(code, 'pages/next.html'));
    await page.create(recursive: true);
    await page.writeAsString(
      '<head></head><script type="module" src="./next.mjs"></script>',
    );
    await File(
      p.join(code, 'pages/next.mjs'),
    ).writeAsString('export const next = 1;');
    await server.start(port: 0, localhostOnly: true);
    final response = await get('/app/notes/pages/next.html');
    expect(response.body, contains('<script src="../moru.js"></script>'));
    final module = await get('/app/notes/pages/next.mjs');
    expect(module.status, 200);
    expect(module.headers.contentType?.mimeType, 'application/javascript');
    expect(module.body, 'export const next = 1;');
  });

  test('a password is asked by the browser and checked', () async {
    await server.start(port: 0, localhostOnly: true, password: 's3cret');
    final denied = await get('/');
    expect(denied.status, 401);
    expect(denied.headers.value('www-authenticate'), startsWith('Basic'));
    expect((await get('/', password: 'wrong')).status, 401);
    expect((await get('/', password: 's3cret')).status, 200);
  });

  test('stopping closes the port', () async {
    await server.start(port: 0, localhostOnly: true);
    final port = server.port!;
    await server.stop();
    expect(server.running, isFalse);
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
  });

  test('files revalidate by ETag and serve byte ranges for seeking', () async {
    await server.start(port: 0, localhostOnly: true);
    final full = await get('/app/notes/style.css');
    expect(full.headers.value('accept-ranges'), 'bytes');
    expect(full.headers.contentLength, 6);
    final etag = full.headers.value('etag')!;

    final cached = await get(
      '/app/notes/style.css',
      headers: {'if-none-match': etag},
    );
    expect(cached.status, 304);
    expect(cached.body, isEmpty);

    final part = await get(
      '/app/notes/style.css',
      headers: {'range': 'bytes=1-3'},
    );
    expect(part.status, 206);
    expect(part.body, 'ody');
    expect(part.headers.value('content-range'), 'bytes 1-3/6');

    final tail = await get(
      '/app/notes/style.css',
      headers: {'range': 'bytes=-2'},
    );
    expect(tail.body, '{}');
    final open = await get(
      '/app/notes/style.css',
      headers: {'range': 'bytes=4-'},
    );
    expect(open.body, '{}');

    final outside = await get(
      '/app/notes/style.css',
      headers: {'range': 'bytes=10-20'},
    );
    expect(outside.status, 416);
    expect(outside.headers.value('content-range'), 'bytes */6');

    final head = await get('/app/notes/style.css', method: 'HEAD');
    expect(head.status, 200);
    expect(head.headers.contentLength, 6);
    expect(head.body, isEmpty);
  });

  test('range headers are parsed like browsers send them', () {
    expect(MiniAppWebServer.parseRange('bytes=0-', 10), (0, 9));
    expect(MiniAppWebServer.parseRange('bytes=5-100', 10), (5, 9));
    expect(MiniAppWebServer.parseRange('bytes=-20', 10), (0, 9));
    expect(MiniAppWebServer.parseRange('bytes=0-1, 4-5', 10), (0, 1));
    for (final bad in ['bytes=9-2', 'bytes=10-', 'items=0-1', 'bytes=-0']) {
      expect(MiniAppWebServer.parseRange(bad, 10), isNull, reason: bad);
    }
    expect(MiniAppWebServer.parseRange('bytes=0-', 0), isNull);
  });
}
