import 'dart:async';
import 'dart:io';

import 'oauth_callback_types.dart';
import 'oauth_pkce.dart';

/// OpenRouter's own minimal, loopback-only OAuth callback.
///
/// `state` is not among OpenRouter's documented `/auth` parameters. That is
/// not proof the server would reject or silently drop an undocumented one —
/// only that nothing guarantees it is preserved and echoed back, so this
/// adapter cannot depend on it for session binding. The shared
/// `openOAuthCallback` helper is unusable here regardless: on Android it
/// unconditionally requires a non-empty `state` query parameter whenever a
/// loopback redirect is passed, and throws otherwise, which would crash a
/// login built on an authorize URL that has no such parameter.
///
/// `callback_url` is a free-form query parameter for OpenRouter, not a
/// pre-registered redirect URI, so session binding instead uses a fresh
/// random nonce embedded as a path segment for every login attempt: only a
/// request whose path matches exactly is accepted, and only once — a repeat
/// delivery to the same path after completion, or a request to a path from a
/// different (e.g. cancelled or stale) attempt, gets rejected rather than
/// treated as a valid callback. `close()` (called on cancellation and on
/// every login exit path) stops the listening socket outright, so a late
/// callback cannot even reach the handler afterwards. Combined with PKCE
/// (the authorization code alone is useless without this device's matching
/// `code_verifier`), this binds a completed login to the exact attempt that
/// started it without relying on an unconfirmed `state` echo.
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
