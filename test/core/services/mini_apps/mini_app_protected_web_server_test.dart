import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_web_server.dart';

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniApp app;
  late MiniAppRuntime runtime;
  late MiniAppWebServer server;
  late HttpClient client;
  var calls = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-protected-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({'id': 'notes', 'name': 'Notes', 'formatVersion': 2}),
    );
    File(p.join(source.path, 'index.html')).writeAsStringSync('<p>Notes</p>');
    app = (await store.install(source)).app;
    runtime = MiniAppRuntime(store: store);
    calls = 0;
    server = MiniAppWebServer(
      store: store,
      protectedApp: app,
      bridgeFor: (app) {
        calls++;
        return MiniAppBridge(
          store: store,
          appId: app.id,
          host: MiniAppHost(
            runtime: runtime,
            invocation: const MiniAppInvocation(
              source: MiniAppInvocationSource.button,
            ),
          ),
        );
      },
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await runtime.dispose();
    await temp.delete(recursive: true);
  });

  Future<({int status, String body, HttpHeaders headers})> request(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decodeStream(response),
      headers: response.headers,
    );
  }

  test(
    'a local app host serves only its private app path and origin',
    () async {
      await server.start(port: 0, localhostOnly: true);
      final uri = server.appUri!;
      final page = await request(uri);
      expect(page.status, 200);
      expect(page.body, contains('Notes'));
      expect(page.headers.value('referrer-policy'), 'no-referrer');
      expect(
        page.headers.value('content-security-policy'),
        contains("frame-ancestors 'none'"),
      );
      expect(
        page.headers.value('content-security-policy'),
        contains("frame-src 'self'"),
      );
      expect((await request(uri.resolve('/'))).status, 404);
      expect((await request(uri.resolve('/app/notes/'))).status, 404);
      expect(
        (await request(uri, headers: {'Host': 'foreign.test'})).status,
        403,
      );
      expect(server.allowsNavigation(uri.resolve('index.html')), isTrue);
      expect(server.allowsNavigation(uri.resolve('/app/other/')), isFalse);
      expect(
        server.allowsNavigation(Uri.parse('https://foreign.test/')),
        isFalse,
      );
    },
  );

  test(
    'navigation rejects file, content and opaque origins without throwing',
    () async {
      await server.start(port: 0, localhostOnly: true);
      for (final target in [
        'file:///data/private.txt',
        'content://private',
        'about:blank',
        'data:text/html,hello',
        'javascript:alert(1)',
        '/app/notes/',
      ]) {
        expect(server.allowsNavigation(Uri.parse(target)), isFalse);
      }
    },
  );

  test(
    'foreign frames, absent origin and wrong nonces cannot reach the bridge',
    () async {
      await server.start(port: 0, localhostOnly: true);
      final uri = server.appUri!;
      final script = (await request(uri.resolve('moru.js'))).body;
      final token =
          jsonDecode(RegExp(r'var token = ("[^"]+");').firstMatch(script)![1]!)
              as String;
      final endpoint = uri.resolve('__moru');
      final body = jsonEncode({
        'id': 1,
        'method': 'storage.set',
        'args': {'key': 'n', 'value': 2},
      });
      for (final headers in <Map<String, String>>[
        <String, String>{},
        {'Origin': 'https://foreign.test', 'X-Moru-App-Token': token},
        {'Origin': uri.origin, 'X-Moru-App-Token': 'wrong'},
        {
          'Origin': uri.origin,
          'X-Moru-App-Token': token,
          'Sec-Fetch-Site': 'cross-site',
        },
        {'Origin': 'null', 'X-Moru-App-Token': token},
      ]) {
        expect(
          (await request(
            endpoint,
            method: 'POST',
            headers: headers,
            body: body,
          )).status,
          403,
        );
      }
      expect(calls, 0);
      expect(await store.storageGet(app.id, 'n'), isNull);
      final accepted = await request(
        endpoint,
        method: 'POST',
        headers: {
          'Origin': uri.origin,
          'X-Moru-App-Token': token,
          'Sec-Fetch-Site': 'same-origin',
        },
        body: body,
      );
      expect(accepted.status, 200);
      expect(await store.storageGet(app.id, 'n'), 2);
      expect(script, contains('window.top !== window'));
      expect(script, contains('X-Moru-App-Token'));
      expect(accepted.headers.value('access-control-allow-origin'), isNull);
    },
  );

  test(
    'deletion or a new installed version invalidates the local app host',
    () async {
      await server.start(port: 0, localhostOnly: true);
      final uri = server.appUri!;
      final source = Directory(p.join(temp.path, 'source'));
      File(p.join(source.path, 'index.html')).writeAsStringSync('<p>New</p>');
      await store.install(source);
      expect(server.allowsNavigation(uri), isFalse);
      expect((await request(uri)).status, 410);
    },
  );

  test(
    'stop cancels a start before its first asynchronous continuation',
    () async {
      final starting = server.start(port: 0, localhostOnly: true);
      await server.stop();
      await starting;
      expect(server.running, isFalse);
      expect(server.appUri, isNull);
    },
  );

  test('a protected app host cannot bind a Wi-Fi interface', () async {
    await expectLater(
      server.start(port: 0, localhostOnly: false),
      throwsA(isA<MiniAppException>().having((e) => e.code, 'code', 'denied')),
    );
    expect(server.running, isFalse);
  });

  test(
    'local resources stay inside the captured app directory after symlink replacement',
    () async {
      await server.start(port: 0, localhostOnly: true);
      final uri = server.appUri!;
      final private = File(p.join(temp.path, 'private.txt'))
        ..writeAsStringSync('private data');
      await Link(p.join(app.codeDirectory, 'escape.txt')).create(private.path);
      final escaped = await request(uri.resolve('escape.txt'));
      expect(escaped.status, 403);
      expect(escaped.body, isNot(contains('private data')));
      final outside = Directory(p.join(temp.path, 'outside'))..createSync();
      File(
        p.join(outside.path, 'index.html'),
      ).writeAsStringSync('private replacement');
      await Directory(
        app.codeDirectory,
      ).rename('${app.codeDirectory}-previous');
      await Link(app.codeDirectory).create(outside.path);
      expect((await request(uri)).status, 403);
    },
  );
}
