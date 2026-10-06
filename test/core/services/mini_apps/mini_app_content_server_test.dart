import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_assets.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_content_server.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';

class _Bundle extends CachingAssetBundle {
  final requested = <String>[];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    return ByteData.sublistView(Uint8List.fromList([0, 97, 115, 109]));
  }
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniApp app;
  late _Bundle bundle;
  late MiniAppContentServer server;
  late HttpClient client;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moru-content-');
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({'id': 'nested', 'name': 'Nested', 'entry': 'web/index.html'}),
    );
    File(p.join(source.path, 'web/index.html'))
      ..createSync(recursive: true)
      ..writeAsStringSync('<html><head></head><body>old app</body></html>');
    File(p.join(source.path, 'web/main.mjs')).writeAsStringSync('export const n=42;');
    File(p.join(source.path, 'web/data.bin')).writeAsBytesSync(List.generate(65537, (i) => i % 256));
    store = MiniAppStore(root: () async => Directory(p.join(temp.path, 'apps')));
    app = (await store.install(source)).app;
    bundle = _Bundle();
    server = MiniAppContentServer(app: app, assets: MiniAppAssets(bundle: bundle));
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    store.dispose();
    await temp.delete(recursive: true);
  });

  Future<({int status, List<int> bytes, HttpHeaders headers})> get(
    Uri uri, {String method = 'GET', String? range},
  ) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    return (status: response.statusCode,
      bytes: await response.fold<List<int>>([], (a,b) => a..addAll(b)),
      headers: response.headers);
  }

  test('old nested apps, relative modules and native bridge use one local origin', () async {
    final entry = await server.start();
    expect(entry.scheme, 'http');
    expect(entry.host, '127.0.0.1');
    expect(entry.path, endsWith('/app/web/index.html'));
    final html = await get(entry);
    expect(html.status, 200);
    expect(utf8.decode(html.bytes), contains('../moru.js'));
    final module = await get(entry.resolve('main.mjs'));
    expect(module.headers.contentType?.mimeType, 'application/javascript');
    expect(utf8.decode(module.bytes), 'export const n=42;');
    final bridge = await get(entry.resolve('../moru.js'));
    expect(utf8.decode(bridge.bytes), contains(MiniAppStore.moruBridgeScript));
    expect(utf8.decode(bridge.bytes), contains(server.libraryBase.toString()));
    expect(server.allowsNavigation(entry.toString()), isTrue);
    expect(server.allowsNavigation('file://${app.entryPath}'), isFalse);
    expect(server.allowsNavigation('https://example.com'), isFalse);
    expect(server.allowsNavigation(server.libraryBase.toString()), isFalse);
  });

  test('shared assets have correct WASM MIME, no app copies, and cache once', () async {
    await server.start();
    final wasm = server.libraryBase.resolve(MiniAppAssets.libraryFiles['sqljs-wasm']!);
    for (var i = 0; i < 2; i++) {
      final response = await get(wasm);
      expect(response.status, 200);
      expect(response.headers.contentType?.mimeType, 'application/wasm');
      expect(response.bytes, [0,97,115,109]);
    }
    expect(bundle.requested, hasLength(1));
    expect(Directory(app.codeDirectory).listSync(recursive: true).whereType<File>()
      .map((f) => p.basename(f.path)), isNot(contains('sql-wasm-1.14.2.wasm')));
    expect((await get(server.libraryBase.resolve('not-bundled.js'))).status, 404);
    expect(bundle.requested, hasLength(1));
  });

  test('large files support byte ranges and HEAD without truncation', () async {
    final entry = await server.start();
    final data = entry.resolve('data.bin');
    final whole = await get(data);
    expect(whole.bytes, List.generate(65537, (i) => i % 256));
    final part = await get(data, range: 'bytes=65530-65536');
    expect(part.status, 206);
    expect(part.bytes, whole.bytes.sublist(65530));
    expect(part.headers.value('content-range'), 'bytes 65530-65536/65537');
    final head = await get(data, method: 'HEAD');
    expect(head.bytes, isEmpty);
    expect(head.headers.contentLength, 65537);
    expect((await get(data, range: 'bytes=999999-')).status, 416);
  });

  test('tokens, encoded separators, outward links and POST cannot cross the boundary', () async {
    final entry = await server.start();
    final secret = File(p.join(temp.path, 'secret.txt'))..writeAsStringSync('private');
    Link(p.join(app.codeDirectory, 'leak.txt')).createSync(secret.path);
    final appRoot = entry.resolve('../');
    for (final uri in [
      entry.replace(path: '/wrong/app/web/index.html'),
      appRoot.resolve('..%2F..%2Fsecret.txt'),
      appRoot.resolve('%5c..%5csecret.txt'),
      appRoot.resolve('leak.txt'),
      entry.resolve('../../../manifest.json'),
    ]) {
      final response = await get(uri);
      expect(response.status, 404, reason: '$uri');
      expect(utf8.decode(response.bytes), isNot(contains('private')));
    }
    expect((await get(appRoot.resolve('__moru'), method: 'POST')).status, 405);
  });

  test('close during startup leaves no late listener', () async {
    final opening = server.start();
    await server.close();
    await expectLater(opening, throwsStateError);
    expect(server.running, isFalse);
  });
}
