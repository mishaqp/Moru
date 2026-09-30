import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/features/workspace/widgets/preview/preview_actions.dart';
import 'package:Kelivo/features/workspace/widgets/preview/preview_file_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late HttpClient client;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('preview_http_boundary_');
    root = Directory('${temporary.path}/preview')..createSync();
    File('${root.path}/index.html').writeAsStringSync(
      '<link rel="stylesheet" href="style.css"><script src="app.js"></script>'
      '<img src="images/pixel.png"><a href="sibling.html">next</a>',
    );
    File('${root.path}/style.css').writeAsStringSync('body { color: red; }');
    File('${root.path}/app.js').writeAsStringSync('window.preview = true;');
    Directory('${root.path}/images').createSync();
    File('${root.path}/images/pixel.png').writeAsBytesSync([137, 80, 78, 71]);
    File('${root.path}/sibling.html').writeAsStringSync('<h1>sibling</h1>');
    final outside = Directory('${temporary.path}/outside')..createSync();
    File('${outside.path}/secret.txt').writeAsStringSync('outside marker');
    Link('${root.path}/escaped.txt').createSync('${outside.path}/secret.txt');
    Link('${root.path}/escaped').createSync(outside.path);
    Link('${root.path}/inside.css').createSync('${root.path}/style.css');
    Link('${root.path}/inside-images').createSync('${root.path}/images');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await closePreviewFileBrowserServer();
    temporary.deleteSync(recursive: true);
  });

  test(
    'tokenized browser preview serves relative assets with safe headers',
    () async {
      final uri = await startPreviewFileBrowserServer(
        File('${root.path}/index.html'),
      );
      expect(uri.host, '127.0.0.1');
      expect(uri.pathSegments, hasLength(2));
      expect(uri.pathSegments.first.length, greaterThanOrEqualTo(32));
      for (final asset in {
        'index.html': 'text/html',
        'style.css': 'text/css',
        'app.js': 'text/javascript',
        'images/pixel.png': 'image/png',
        'sibling.html': 'text/html',
        'inside.css': 'text/css',
        'inside-images/pixel.png': 'image/png',
      }.entries) {
        final response = await (await client.getUrl(
          uri.resolve(asset.key),
        )).close();
        expect(response.statusCode, HttpStatus.ok, reason: asset.key);
        expect(response.headers.contentType!.mimeType, asset.value);
        expect(response.headers.value('referrer-policy'), 'no-referrer');
        expect(response.headers.value('cache-control'), 'no-store');
        expect(
          response.headers.value('content-security-policy'),
          contains("base-uri 'none'"),
        );
        expect(
          response.headers.value('content-security-policy'),
          contains("object-src 'none'"),
        );
        expect(
          await response.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          ),
          isNotEmpty,
        );
      }
    },
  );

  test('every resource requires the token and denies outside links', () async {
    final uri = await startPreviewFileBrowserServer(
      File('${root.path}/index.html'),
    );
    for (final path in ['/index.html', '/wrong/index.html']) {
      final response = await (await client.getUrl(
        uri.replace(path: path),
      )).close();
      expect(response.statusCode, HttpStatus.forbidden);
      await response.drain<void>();
    }
    for (final path in ['escaped.txt', 'escaped/secret.txt']) {
      final response = await (await client.getUrl(uri.resolve(path))).close();
      expect(response.statusCode, HttpStatus.forbidden);
      expect(
        await response.transform(utf8.decoder).join(),
        isNot(contains('outside marker')),
      );
    }
  });

  test('raw plain and encoded traversal or separators are forbidden', () async {
    final uri = await startPreviewFileBrowserServer(
      File('${root.path}/index.html'),
    );
    final token = uri.pathSegments.first;
    for (final path in [
      '/$token/../index.html',
      '/$token/sub/../style.css',
      '/$token/%2e%2e/index.html',
      '/$token/sub/%2E%2E/style.css',
      '/$token/%252e%252e/index.html',
      '/$token/images%2fpixel.png',
      '/$token/images%5cpixel.png',
      '/$token/images\\pixel.png',
    ]) {
      final response = await _rawGet(uri, path);
      expect(response, startsWith('HTTP/1.1 403'), reason: path);
    }
  });

  test(
    'HEAD has correct length without body and oversized resources are refused',
    () async {
      final uri = await startPreviewFileBrowserServer(
        File('${root.path}/index.html'),
      );
      final head = await (await client.openUrl(
        'HEAD',
        uri.resolve('style.css'),
      )).close();
      expect(head.statusCode, HttpStatus.ok);
      expect(head.contentLength, File('${root.path}/style.css').lengthSync());
      expect(
        await head.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
        isEmpty,
      );
      final oversized = File(
        '${root.path}/large.bin',
      ).openSync(mode: FileMode.write);
      oversized.truncateSync(16 * 1024 * 1024 + 1);
      oversized.closeSync();
      final response = await (await client.getUrl(
        uri.resolve('large.bin'),
      )).close();
      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      await response.drain<void>();
    },
  );

  test(
    'an internal index symlink uses actual page siblings and both boundaries',
    () async {
      final alias = File('${temporary.path}/alias.html');
      Link(alias.path).createSync('${root.path}/index.html');
      File(
        '${temporary.path}/workspace-only.css',
      ).writeAsStringSync('not in page directory');
      Link(
        '${root.path}/workspace-only.css',
      ).createSync('${temporary.path}/workspace-only.css');
      final uri = await startPreviewFileBrowserServer(
        alias,
        accessRoot: temporary.path,
      );
      expect(uri.pathSegments.last, 'index.html');
      final css = await (await client.getUrl(uri.resolve('style.css'))).close();
      expect(css.statusCode, HttpStatus.ok);
      expect(await css.transform(utf8.decoder).join(), 'body { color: red; }');
      final denied = await (await client.getUrl(
        uri.resolve('workspace-only.css'),
      )).close();
      expect(denied.statusCode, HttpStatus.forbidden);
      await denied.drain<void>();
      root.renameSync('${temporary.path}/moved-page');
      Link(root.path).createSync('${temporary.path}/outside');
      final replaced = await (await client.getUrl(
        uri.resolve('secret.txt'),
      )).close();
      expect(replaced.statusCode, HttpStatus.forbidden);
      expect(
        await replaced.transform(utf8.decoder).join(),
        isNot(contains('outside marker')),
      );
    },
  );

  test('pipelined second requests cannot bypass the raw-line gate', () async {
    final uri = await startPreviewFileBrowserServer(
      File('${root.path}/index.html'),
    );
    final socket = await Socket.connect(uri.host, uri.port);
    final token = uri.pathSegments.first;
    socket.write(
      'GET /$token/style.css HTTP/1.1\r\nHost: ${uri.host}:${uri.port}\r\nConnection: keep-alive\r\n\r\n'
      'GET /$token/sub/../sibling.html HTTP/1.1\r\nHost: ${uri.host}:${uri.port}\r\nConnection: close\r\n\r\n',
    );
    await socket.flush();
    final response = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    socket.destroy();
    expect('HTTP/1.1'.allMatches(response), hasLength(1));
    expect(response, contains('body { color: red; }'));
    expect(response, isNot(contains('<h1>sibling</h1>')));
  });

  test(
    'oversized first lines are refused and fragmented valid lines work',
    () async {
      final uri = await startPreviewFileBrowserServer(
        File('${root.path}/index.html'),
      );
      final denied = await _rawGet(
        uri,
        '/${uri.pathSegments.first}/${'a' * (8 * 1024)}',
      );
      expect(denied, startsWith('HTTP/1.1 403'));
      final socket = await Socket.connect(uri.host, uri.port);
      socket.write('GET /${uri.pathSegments.first}/');
      await socket.flush();
      socket.write(
        'style.css HTTP/1.1\r\nHost: ${uri.host}:${uri.port}\r\nConnection: close\r\n\r\n',
      );
      await socket.flush();
      final response = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      socket.destroy();
      expect(response, startsWith('HTTP/1.1 200'));
      expect(response, contains('body { color: red; }'));
    },
  );

  test(
    'independent owned previews close without closing another preview',
    () async {
      final first = await PreviewFileServer.start(
        sourceFile: File('${root.path}/index.html'),
        accessRoot: root.path,
      );
      final second = await PreviewFileServer.start(
        sourceFile: File('${root.path}/sibling.html'),
        accessRoot: root.path,
      );
      try {
        expect(
          first.uri.pathSegments.first,
          isNot(second.uri.pathSegments.first),
        );
        await first.close();
        await expectLater(
          Socket.connect(first.uri.host, first.uri.port),
          throwsA(isA<SocketException>()),
        );
        final response = await (await client.getUrl(second.uri)).close();
        expect(response.statusCode, HttpStatus.ok);
        expect(
          await response.transform(utf8.decoder).join(),
          '<h1>sibling</h1>',
        );
      } finally {
        await first.close();
        await second.close();
      }
    },
  );

  test('closing an owned browser server closes its port', () async {
    final uri = await startPreviewFileBrowserServer(
      File('${root.path}/index.html'),
    );
    await closePreviewFileBrowserServer();
    await expectLater(
      Socket.connect(uri.host, uri.port),
      throwsA(isA<SocketException>()),
    );
  });
}

Future<String> _rawGet(Uri origin, String path) async {
  final socket = await Socket.connect(origin.host, origin.port);
  socket.write(
    'GET $path HTTP/1.1\r\nHost: ${origin.host}:${origin.port}\r\nConnection: close\r\n\r\n',
  );
  await socket.flush();
  try {
    return await socket.cast<List<int>>().transform(utf8.decoder).join();
  } finally {
    socket.destroy();
  }
}
