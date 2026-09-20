import 'dart:async';
import 'dart:io';

import 'oauth_callback_types.dart';
import 'oauth_pkce.dart';

/// OpenRouter's own minimal, loopback-only OAuth callback.
///
/// OpenRouter's `/auth` authorization endpoint has no `state` parameter
/// (confirmed absent from its docs, and never echoed back), so the shared
/// `openOAuthCallback` helper cannot be reused here: on Android it
/// unconditionally requires a non-empty `state` query parameter whenever a
/// loopback redirect is passed, and throws otherwise. `callback_url` is also
/// a free-form query parameter for OpenRouter, not a pre-registered redirect
/// URI, so session binding instead uses a fresh random nonce embedded as a
/// path segment for every login attempt: only a request whose path matches
/// exactly is accepted. That gives exact-URL-match + one-time-nonce +
/// one-time-completion binding without fabricating a `state` parameter
/// OpenRouter does not document.
class OpenRouterOAuthCallback {
  OpenRouterOAuthCallback._(this._server, String nonce)
    : redirectUri = Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: _server.port,
        path: '/oauth/callback/$nonce',
      ) {
    _callback.future.ignore();
    _subscription = _server.listen(_handleRequest);
  }

  static Future<OpenRouterOAuthCallback> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return OpenRouterOAuthCallback._(server, oauthRandomString(18));
  }

  final HttpServer _server;
  final Uri redirectUri;
  final Completer<Uri> _callback = Completer<Uri>();
  late final StreamSubscription<HttpRequest> _subscription;
  bool _closed = false;
  bool _responding = false;

  Future<Uri> waitForCallback(Duration timeout) =>
      _callback.future.timeout(timeout);

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != redirectUri.path) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
      return;
    }
    if (_closed || _callback.isCompleted || _responding) {
      request.response.statusCode = HttpStatus.gone;
      await request.response.close();
      return;
    }
    final params = request.uri.queryParametersAll;
    final codes = params['code'];
    final errors = params['error'];
    final validResult =
        (codes?.length == 1 && codes!.single.isNotEmpty && errors == null) ||
        (errors?.length == 1 && errors!.single.isNotEmpty && codes == null);
    if (request.method != 'GET' || !validResult) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    _responding = true;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer')
      ..write(_callbackPage);
    await request.response.close();
    if (!_callback.isCompleted) {
      _callback.complete(redirectUri.replace(query: request.uri.query));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_callback.isCompleted) {
      _callback.completeError(
        const OAuthCallbackException(
          'authorization cancelled',
          cancelled: true,
        ),
      );
    }
    await _subscription.cancel();
    await _server.close(force: true);
  }
}

const _callbackPage = '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Moru</title></head>
<body style="background:#141414;color:#eee;font:18px sans-serif;padding:32px">
<p>Authorization received. Return to Moru to finish signing in.</p>
<p>Авторизация получена. Вернитесь в Moru для завершения входа.</p>
</body></html>''';
