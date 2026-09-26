import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mini_app_store.dart';

/// `moru.fetch`: HTTP requests from a mini app, only to the hosts its
/// manifest lists in `network`. Redirects are followed here, so a redirect
/// cannot leave the list either.
class MiniAppFetch {
  MiniAppFetch({http.Client? client}) : _client = client ?? http.Client();

  static const Set<String> methods = {
    'GET',
    'HEAD',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  };
  static const int maxRequestBytes = 1024 * 1024;
  static const int maxResponseBytes = 2 * 1024 * 1024;
  static const int maxRedirects = 5;
  static const Duration timeout = Duration(seconds: 20);

  static const Set<int> _redirects = {301, 302, 303, 307, 308};

  final http.Client _client;

  Future<Map<String, Object?>> fetch(
    MiniApp app,
    Map<String, dynamic> args,
  ) async {
    var uri = _uri(app, args['url']);
    var method = '${args['method'] ?? 'GET'}'.toUpperCase();
    if (!methods.contains(method)) {
      throw MiniAppException(
        'invalid_method',
        'method must be one of ${methods.join(', ')}.',
      );
    }
    final headers = <String, String>{};
    final rawHeaders = args['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) => headers['$key'] = '$value');
    } else if (rawHeaders != null) {
      throw const MiniAppException(
        'invalid_headers',
        'headers must be an object of strings.',
      );
    }
    var body = args['body'];
    if (body != null && body is! String) {
      throw const MiniAppException(
        'invalid_body',
        'body must be a string; use JSON.stringify for JSON.',
      );
    }
    if (body is String && utf8.encode(body).length > maxRequestBytes) {
      throw const MiniAppException(
        'body_too_large',
        'The request body is over 1 MB.',
      );
    }

    for (var redirects = 0; ; redirects++) {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (body is String && method != 'GET' && method != 'HEAD') {
        request.body = body;
      }
      final response = await _client.send(request).timeout(timeout);
      final location = response.headers['location'];
      if (_redirects.contains(response.statusCode) && location != null) {
        await response.stream.drain<void>();
        if (redirects == maxRedirects) {
          throw const MiniAppException(
            'too_many_redirects',
            'The server redirected too many times.',
          );
        }
        uri = _uri(app, uri.resolve(location).toString());
        // 303, and 301/302 after POST, turn into GET as browsers do.
        if (response.statusCode == 303 ||
            (method == 'POST' &&
                (response.statusCode == 301 || response.statusCode == 302))) {
          method = 'GET';
          body = null;
        }
        continue;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxResponseBytes) {
          throw const MiniAppException(
            'response_too_large',
            'The response is over 2 MB.',
          );
        }
      }
      return {
        'url': uri.toString(),
        'status': response.statusCode,
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'headers': response.headers,
        'body': utf8.decode(bytes, allowMalformed: true),
      };
    }
  }

  static Uri _uri(MiniApp app, Object? raw) {
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      throw const MiniAppException(
        'invalid_url',
        'url must be an absolute http(s) address.',
      );
    }
    if (!MiniAppStore.allowsHost(app, uri.host)) {
      throw MiniAppException(
        'host_not_allowed',
        '${uri.host} is not in "network" of moru-app.json.',
      );
    }
    return uri;
  }
}
