import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/features/workspace/widgets/preview/preview_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late HttpClient client;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('preview_http_boundary_');
    root = Directory('${temporary.path}/preview')..createSync();
    File('${root.path}/index.html').writeAsStringSync('<h1>inside</h1>');
    final outside = Directory('${temporary.path}/outside')..createSync();
    File('${outside.path}/secret.txt').writeAsStringSync('outside marker');
    Link('${root.path}/escaped.txt').createSync('${outside.path}/secret.txt');
    Link('${root.path}/escaped').createSync(outside.path);
    File('${root.path}/asset.txt').writeAsStringSync('inside asset');
    Link('${root.path}/inside.txt').createSync('${root.path}/asset.txt');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await closePreviewFileBrowserServer();
    temporary.deleteSync(recursive: true);
  });

  test(
    'browser preview rejects escaped links and keeps inside resources usable',
    () async {
      final uri = await startPreviewFileBrowserServer(
        File('${root.path}/index.html'),
      );
      for (final path in ['/escaped.txt', '/escaped/secret.txt']) {
        final response = await (await client.getUrl(
          uri.replace(path: path),
        )).close();
        expect(response.statusCode, HttpStatus.forbidden);
        expect(
          await response.transform(utf8.decoder).join(),
          isNot(contains('outside marker')),
        );
      }
      final response = await (await client.getUrl(
        uri.replace(path: '/inside.txt'),
      )).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(await response.transform(utf8.decoder).join(), 'inside asset');
    },
  );
}
