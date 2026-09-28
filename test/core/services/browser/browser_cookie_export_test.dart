import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_cookie_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final originalRead = BrowserCookieExport.readCookies;
  tearDown(() => BrowserCookieExport.readCookies = originalRead);

  test('cookies become a Netscape file for this host only', () {
    final text = BrowserCookieExport.netscapeFile(
      Uri.parse('https://shop.example/cart'),
      'sid=abc=1; theme=dark;  ; bad\tname=x',
    );
    final rows = [
      for (final line in LineSplitter.split(text))
        if (!line.startsWith('#')) line.split('\t'),
    ];
    expect(rows, [
      ['shop.example', 'FALSE', '/', 'TRUE', '0', 'sid', 'abc=1'],
      ['shop.example', 'FALSE', '/', 'TRUE', '0', 'theme', 'dark'],
    ]);
  });

  test('export writes the file into the chat folder and tells the model '
      'only the path and names', () async {
    final dir = await Directory.systemTemp.createTemp('cookies');
    addTearDown(() => dir.delete(recursive: true));
    String? asked;
    BrowserCookieExport.readCookies = (url) async {
      asked = url;
      return 'sid=secret-value; lang=ru';
    };

    final result = await BrowserCookieExport.export(
      pageUrl: 'https://www.shop.example/account',
      hostDir: dir,
      modelDir: '/chat',
    );

    expect(asked, 'https://www.shop.example/account');
    expect(result['ok'], isTrue);
    expect(result['path'], '/chat/browser-cookies/shop.example.txt');
    expect(result['cookies'], ['sid', 'lang']);
    expect(jsonEncode(result), isNot(contains('secret-value')));
    final file = File('${dir.path}/browser-cookies/shop.example.txt');
    expect(file.readAsStringSync(), contains('\tsid\tsecret-value'));
    expect(file.statSync().modeString(), 'rw-------');
  });

  test('no page or no cookies is a clear error', () async {
    final dir = await Directory.systemTemp.createTemp('cookies');
    addTearDown(() => dir.delete(recursive: true));
    BrowserCookieExport.readCookies = (_) async => null;
    expect(
      (await BrowserCookieExport.export(
        pageUrl: 'about:blank',
        hostDir: dir,
        modelDir: '/chat',
      ))['error'],
      'no_site',
    );
    expect(
      (await BrowserCookieExport.export(
        pageUrl: 'https://shop.example',
        hostDir: dir,
        modelDir: '/chat',
      ))['error'],
      'no_cookies',
    );
  });
}
