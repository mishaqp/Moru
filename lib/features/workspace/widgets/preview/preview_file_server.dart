import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';

/// Per-preview capability server. The original workspace grant and the captured
/// real page directory are intersected for every actual opened descriptor.
class PreviewFileServer {
  PreviewFileServer._(this._server, this.uri);

  static const maxResourceBytes = 16 * 1024 * 1024;
  final HttpServer _server;
  final Uri uri;
  Future<void>? _closing;

  static Future<PreviewFileServer> start({
    required File sourceFile,
    required String accessRoot,
  }) async {
    final granted = WorkspaceFileAccess(roots: [accessRoot]);
    final source = await granted.openRead(sourceFile.path);
    late final String realSource;
    try {
      // hostPath is the candidate before open; derive this boundary from the fd.
      realSource = await granted.resolve(source.path);
    } finally {
      await source.close();
    }
    final pageDirectory = p.dirname(realSource);
    final page = WorkspaceFileAccess(roots: [pageDirectory]);
    // Freeze both roots before any request or subsequent directory replacement.
    await page.resolve(pageDirectory);
    final random = Random.secure();
    final token = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        pathSegments: [token, p.basename(realSource)],
      );
      server.listen((request) async {
        // Close every response, including errors, before a pipelined request.
        // Dart owns the HTTP parser and normalizes the request URI.
        request.response.persistentConnection = false;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('Referrer-Policy', 'no-referrer');
        request.response.headers.set('X-Content-Type-Options', 'nosniff');
        request.response.headers.set(
          'Content-Security-Policy',
          "default-src 'self' ${uri.origin} http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; base-uri 'none'; object-src 'none'",
        );
        try {
          final parts = _resourceSegments(request.uri.path, token);
          if (parts == null ||
              request.headers.value('host') != '127.0.0.1:${server.port}') {
            request.response.statusCode = HttpStatus.forbidden;
          } else if (request.method != 'GET' && request.method != 'HEAD') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
          } else {
            final target = p.joinAll([pageDirectory, ...parts]);
            final opened = await page.openRead(target);
            try {
              // The second common guard checks the ACTUAL fd against the
              // original grant, not the pre-open candidate or a union of roots.
              await granted.resolve(opened.path);
              final length = await opened.handle.length();
              if (length > maxResourceBytes) {
                request.response.statusCode = HttpStatus.requestEntityTooLarge;
              } else {
                final bytes = request.method == 'HEAD'
                    ? null
                    : await _readResource(opened.handle);
                if (bytes != null && bytes.length > maxResourceBytes) {
                  request.response.statusCode =
                      HttpStatus.requestEntityTooLarge;
                } else {
                  request.response.headers.contentType = ContentType.parse(
                    _mimeForPath(target),
                  );
                  request.response.contentLength = bytes?.length ?? length;
                  if (bytes != null) request.response.add(bytes);
                }
              }
            } finally {
              await opened.close();
            }
          }
        } on WorkspaceFileAccessException {
          request.response.statusCode = HttpStatus.forbidden;
        } on FileSystemException {
          request.response.statusCode = HttpStatus.notFound;
        } catch (_) {
          request.response.statusCode = HttpStatus.internalServerError;
        } finally {
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
      return PreviewFileServer._(server, uri);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _server.close(force: true);
}

Future<Uint8List> _readResource(RandomAccessFile file) async {
  final bytes = BytesBuilder(copy: false);
  while (bytes.length <= PreviewFileServer.maxResourceBytes) {
    final remaining = PreviewFileServer.maxResourceBytes + 1 - bytes.length;
    final chunk = await file.read(min(64 * 1024, remaining));
    if (chunk.isEmpty) break;
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

// The normalized URI path must still start with this server's capability token.
// Every opened resource is also checked against both captured real roots.
List<String>? _resourceSegments(String normalizedPath, String token) {
  if (normalizedPath.length > 8 * 1024) return null;
  if (!normalizedPath.startsWith('/') || normalizedPath.contains('\\')) {
    return null;
  }
  final raw = normalizedPath.split('/');
  if (raw.length < 3 || raw[1] != token) return null;
  final parts = <String>[];
  for (final segment in raw.skip(2)) {
    if (segment.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(segment);
    } catch (_) {
      return null;
    }
    if (decoded == '.' ||
        decoded == '..' ||
        decoded.contains('/') ||
        decoded.contains('\\') ||
        decoded.contains('\u0000') ||
        RegExp(r'%(?:2e|2f|5c|00)', caseSensitive: false).hasMatch(decoded)) {
      return null;
    }
    parts.add(decoded);
  }
  return parts;
}

String _mimeForPath(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.html':
    case '.htm':
      return 'text/html; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.js':
    case '.mjs':
      return 'text/javascript; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.ico':
      return 'image/x-icon';
    case '.json':
      return 'application/json';
    case '.txt':
      return 'text/plain; charset=utf-8';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    default:
      return 'application/octet-stream';
  }
}
