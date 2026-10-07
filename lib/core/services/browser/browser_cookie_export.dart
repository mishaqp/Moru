import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'browser_guard.dart';

/// Hands the open site's login to the Linux terminal: the browser's cookies
/// for that site are written to a Netscape cookie file in the chat folder,
/// which `curl -b`, `wget --load-cookies` and Python's
/// `http.cookiejar.MozillaCookieJar` read. The values never enter the chat;
/// the model only learns the path and the cookie names.
class BrowserCookieExport {
  const BrowserCookieExport._();

  static const MethodChannel _channel = MethodChannel('app.browser');

  /// The folder inside the chat folder the files go to.
  static const String folder = 'browser-cookies';

  /// The `Cookie` header the browser would send to a URL. Replaced in tests.
  @visibleForTesting
  static Future<String?> Function(String url) readCookies = (url) =>
      _channel.invokeMethod<String>('cookies', {'url': url});

  /// Netscape cookie file lines for [cookieHeader] (`a=1; b=2`) of [url]:
  /// for this host only, every path, secure on https, kept for the session.
  static String netscapeFile(Uri url, String cookieHeader) {
    final secure = url.isScheme('https') ? 'TRUE' : 'FALSE';
    final lines = <String>[
      '# Netscape HTTP Cookie File',
      '# Exported by Moru from the browser for ${url.host}',
    ];
    for (final part in cookieHeader.split(';')) {
      final pair = part.trim();
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final name = eq < 0 ? pair : pair.substring(0, eq);
      final value = eq < 0 ? '' : pair.substring(eq + 1);
      if (name.isEmpty || name.contains(RegExp(r'[\t\r\n]'))) continue;
      if (value.contains(RegExp(r'[\t\r\n]'))) continue;
      lines.add([url.host, 'FALSE', '/', secure, '0', name, value].join('\t'));
    }
    return '${lines.join('\n')}\n';
  }

  /// Writes the cookies of [pageUrl]'s site into [hostDir] (the chat
  /// folder on the phone), and names the file as the terminal sees it
  /// under [modelDir].
  static Future<Map<String, dynamic>> export({
    required String? pageUrl,
    required Directory hostDir,
    required String modelDir,
  }) async {
    final url = Uri.tryParse(pageUrl ?? '');
    final host = BrowserGuard.host(pageUrl);
    if (url == null ||
        host == null ||
        !(url.isScheme('http') || url.isScheme('https'))) {
      return {
        'ok': false,
        'error': 'no_site',
        'message': 'Open the site in the browser first.',
      };
    }
    final String? header;
    try {
      header = await readCookies(url.toString());
    } on PlatformException catch (error) {
      return {
        'ok': false,
        'error': 'cookies_unavailable',
        'message': error.message ?? error.code,
      };
    }
    final content = netscapeFile(url, header ?? '');
    final names = [
      for (final line in content.split('\n'))
        if (line.isNotEmpty && !line.startsWith('#')) line.split('\t')[5],
    ];
    if (names.isEmpty) {
      return {
        'ok': false,
        'error': 'no_cookies',
        'message': 'The browser has no cookies for $host. Log in first.',
      };
    }
    final dir = Directory(p.join(hostDir.path, folder));
    await dir.create(recursive: true);
    final name = '${host.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_')}.txt';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(content, flush: true);
    // Only the app (and its terminal) may read a login.
    await Process.run('chmod', ['600', file.path]);
    final modelPath = p.posix.join(modelDir, folder, name);
    return {
      'ok': true,
      'path': modelPath,
      'site': host,
      'cookies': names,
      'usage':
          'curl -b $modelPath -c $modelPath ${url.origin}/ ... '
          '(wget --load-cookies $modelPath; Python MozillaCookieJar). '
          'The file is a login: do not print or upload it.',
    };
  }
}
