import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'mini_app_bridge.dart';
import 'mini_app_store.dart';

/// Serves the installed mini apps over HTTP, so a browser on another device
/// in the same Wi-Fi (or this phone) can use them. `moru.*` calls travel as
/// POSTs to `/app/<id>/__moru` and run in the same [MiniAppBridge] as in
/// Moru, with the same data.
class MiniAppWebServer {
  MiniAppWebServer({required this.store, required this.bridgeFor});

  final MiniAppStore store;

  /// The bridge a browser page of [app] talks to; built once per app while
  /// the server runs.
  final MiniAppBridge Function(MiniApp app) bridgeFor;

  HttpServer? _server;
  final Map<String, MiniAppBridge> _bridges = {};
  String? _password;

  static const int maxBridgeMessageBytes = 8 * 1024 * 1024;

  bool get running => _server != null;
  int? get port => _server?.port;

  /// Listens on [port] of every network ([localhostOnly]: of this phone
  /// only). With a [password], the browser asks for it (HTTP Basic, any
  /// user name).
  Future<void> start({
    required int port,
    required bool localhostOnly,
    String? password,
  }) async {
    await stop();
    _password = password == null || password.isEmpty ? null : password;
    final server = await HttpServer.bind(
      localhostOnly ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
      port,
    );
    // Off: byte ranges of compressed bodies would not match the file.
    server.autoCompress = false;
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _bridges.clear();
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorized(request)) {
        response
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Basic realm="Moru", charset="UTF-8"',
          )
          ..write('Password required.');
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.isEmpty) {
        await _index(response);
      } else if (segments.first == 'app' && segments.length >= 2) {
        await _app(request, segments[1], segments.skip(2).toList());
      } else {
        _notFound(response);
      }
    } catch (e) {
      try {
        response
          ..statusCode = HttpStatus.internalServerError
          ..write('$e');
      } catch (_) {
        // The headers were already sent.
      }
    } finally {
      await response.close().catchError((_) {});
    }
  }

  bool _authorized(HttpRequest request) {
    final password = _password;
    if (password == null) return true;
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Basic ')) return false;
    try {
      final decoded = utf8.decode(base64.decode(header.substring(6).trim()));
      final colon = decoded.indexOf(':');
      return colon >= 0 && _same(decoded.substring(colon + 1), password);
    } on FormatException {
      return false;
    }
  }

  /// Compares in constant time for equal lengths.
  static bool _same(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  Future<void> _index(HttpResponse response) async {
    await store.load();
    final items = StringBuffer();
    for (final app in store.apps) {
      items.write(
        '<a class="app" href="/app/${Uri.encodeComponent(app.id)}/">'
        '<b>${_escape(app.name)}</b>'
        '${app.description.isEmpty ? '' : '<span>${_escape(app.description)}</span>'}'
        '</a>',
      );
    }
    response.headers.contentType = ContentType.html;
    response.write(
      _indexPage.replaceFirst(
        '{{apps}}',
        items.isEmpty ? '<p class="empty">No apps yet.</p>' : '$items',
      ),
    );
  }

  Future<void> _app(HttpRequest request, String id, List<String> rest) async {
    final response = request.response;
    await store.load();
    final app = store.byId(id);
    if (app == null) return _notFound(response);
    // "/app/<id>" -> "/app/<id>/", so relative links resolve inside the app.
    if (rest.isEmpty) {
      response
        ..statusCode = HttpStatus.movedPermanently
        ..headers.set(
          HttpHeaders.locationHeader,
          '/app/${Uri.encodeComponent(id)}/',
        );
      return;
    }
    final path = rest.join('/');
    if (path == '__moru') return _bridge(request, app);
    if (path == MiniAppStore.bridgeFile) {
      response.headers
        ..contentType = ContentType(
          'application',
          'javascript',
          charset: 'utf-8',
        )
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(webBridgeScript(app.id));
      return;
    }
    // An entry in a folder loads its files relative to that folder.
    if (path.isEmpty && app.entry.contains('/')) {
      response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          '/app/${Uri.encodeComponent(id)}/${app.entry}',
        );
      return;
    }
    final relative = path.isEmpty ? app.entry : path;
    final code = p.normalize(app.codeDirectory);
    final file = File(p.normalize(p.join(code, relative)));
    if (!p.isWithin(code, file.path) || !await file.exists()) {
      return _notFound(response);
    }
    await _file(request, file);
  }

  /// A file with revalidation (ETag) and byte ranges, so the browser keeps
  /// it cached and can seek in audio and video.
  static Future<void> _file(HttpRequest request, File file) async {
    final response = request.response;
    final stat = await file.stat();
    final size = stat.size;
    final etag = '"$size-${stat.modified.millisecondsSinceEpoch}"';
    response.headers
      ..contentType = contentTypeFor(file.path)
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.etagHeader, etag)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.lastModifiedHeader, stat.modified);
    final ifNoneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
    if (ifNoneMatch != null &&
        ifNoneMatch.split(',').any((tag) => tag.trim() == etag)) {
      response.statusCode = HttpStatus.notModified;
      return;
    }
    var start = 0;
    var end = size - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final parsed = parseRange(range, size);
      if (parsed == null) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return;
      }
      (start, end) = parsed;
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$size',
        );
    }
    response.contentLength = size == 0 ? 0 : end - start + 1;
    if (request.method == 'HEAD' || size == 0) return;
    await response.addStream(file.openRead(start, end + 1));
  }

  /// The first range of a `Range: bytes=...` header as inclusive
  /// `(start, end)`, or null when it cannot be served.
  static (int, int)? parseRange(String header, int size) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)').firstMatch(header.trim());
    if (match == null || size == 0) return null;
    final first = match[1]!;
    final last = match[2]!;
    int start;
    int end;
    if (first.isEmpty) {
      // "bytes=-500": the last 500 bytes.
      final suffix = int.tryParse(last);
      if (suffix == null || suffix == 0) return null;
      start = suffix >= size ? 0 : size - suffix;
      end = size - 1;
    } else {
      start = int.parse(first);
      end = last.isEmpty ? size - 1 : int.parse(last);
      if (end >= size) end = size - 1;
    }
    if (start > end || start >= size) return null;
    return (start, end);
  }

  Future<void> _bridge(HttpRequest request, MiniApp app) async {
    final response = request.response;
    if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBridgeMessageBytes) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
    }
    final bridge = _bridges[app.id] ??= bridgeFor(app);
    final script = await bridge.handle(
      utf8.decode(bytes, allowMalformed: true),
    );
    response.headers.contentType = ContentType(
      'application',
      'javascript',
      charset: 'utf-8',
    );
    response.write(script ?? '');
  }

  static void _notFound(HttpResponse response) {
    response
      ..statusCode = HttpStatus.notFound
      ..write('Not found.');
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// `moru.js` for a browser: `MoruBridge.postMessage` becomes a POST to
  /// the app's bridge, and the reply runs like Moru's `runJavaScript`.
  static String webBridgeScript(String appId) =>
      '''
(function () {
  if (window.MoruBridge) return;
  var endpoint = ${jsonEncode('/app/${Uri.encodeComponent(appId)}/__moru')};
  window.MoruBridge = {
    postMessage: function (message) {
      fetch(endpoint, { method: 'POST', body: message, credentials: 'same-origin' })
        .then(function (response) { return response.text(); })
        .then(function (script) { if (script) (0, eval)(script); });
    }
  };
})();
${MiniAppStore.moruBridgeScript}''';

  static const Map<String, String> _types = {
    '.html': 'text/html; charset=utf-8',
    '.htm': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.mjs': 'application/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.ico': 'image/x-icon',
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.ogg': 'audio/ogg',
    '.mp4': 'video/mp4',
    '.webm': 'video/webm',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.txt': 'text/plain; charset=utf-8',
    '.wasm': 'application/wasm',
  };

  static ContentType contentTypeFor(String path) => ContentType.parse(
    _types[p.extension(path).toLowerCase()] ?? 'application/octet-stream',
  );

  static const String _indexPage = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moru apps</title>
<style>
:root { color-scheme: light dark; --bg: #f5f5f7; --card: #fff; --text: #111; --muted: #666; --accent: #4f7cff; }
@media (prefers-color-scheme: dark) { :root { --bg: #111214; --card: #1c1d21; --text: #eee; --muted: #999; } }
body { margin: 0; font: 15px/1.4 system-ui, sans-serif; background: var(--bg); color: var(--text); }
main { max-width: 640px; margin: 0 auto; padding: 32px 16px; }
h1 { font-size: 28px; margin: 0 0 20px; }
.app { display: block; background: var(--card); border-radius: 14px; padding: 14px 16px; margin-bottom: 10px; color: inherit; text-decoration: none; }
.app:hover { outline: 2px solid var(--accent); }
.app span { display: block; color: var(--muted); font-size: 13px; margin-top: 2px; }
.empty { color: var(--muted); }
</style></head>
<body><main><h1>Moru apps</h1>{{apps}}</main></body></html>''';
}
