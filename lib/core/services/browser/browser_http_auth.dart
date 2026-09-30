import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';

/// In-memory credentials for an app-owned OpenCode server. They never enter a
/// URL, JavaScript, the browser library or WebViewDatabase.
class BrowserHttpAuth {
  BrowserHttpAuth({
    required this.origin,
    required String username,
    required String password,
  }) : _credentials = (username: username, password: password);

  final Uri origin;
  ({String username, String password})? _credentials;
  final Set<void Function()> _pending = {};

  bool get isActive => _credentials != null;

  /// Revoke handoffs that outlive the server and release its secret reference.
  void dispose() {
    _credentials = null;
    for (final cancel in _pending.toList()) {
      cancel();
    }
  }

  /// Call only on a new, unloaded controller, before registering any browser
  /// session or user scripts. Android's auth callback omits the port, so an
  /// existing tab's URL cannot establish which origin requested credentials.
  /// This JS-disabled, JSON-only navigation has exactly one possible origin.
  /// Chromium then caches Basic auth by scheme, host and port for the clean UI.
  Future<void> bootstrap(
    WebViewController controller, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final credentials = _credentials;
    if (credentials == null ||
        origin.scheme != 'http' ||
        origin.host != '127.0.0.1' ||
        !origin.hasPort ||
        origin.port < 1 ||
        origin.port > 65535 ||
        origin.userInfo.isNotEmpty ||
        origin.query.isNotEmpty ||
        origin.fragment.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw const BrowserHttpAuthException();
    }
    final probe = origin.replace(path: '/session').toString();
    final ready = Completer<void>();
    // Attach the listener before native callbacks can complete with an error.
    ready.future.ignore();
    WebViewCredential? credential = WebViewCredential(
      user: credentials.username,
      password: credentials.password,
    );
    var active = true;
    var started = false;
    void fail() {
      credential = null;
      active = false;
      if (!ready.isCompleted) {
        ready.completeError(const BrowserHttpAuthException());
      }
    }

    Timer? timer;
    _pending.add(fail);
    try {
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!active || !request.isMainFrame || request.url != probe) {
              fail();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (!active || url != probe) {
              fail();
              return;
            }
            started = true;
          },
          onHttpAuthRequest: (request) {
            final value = credential;
            // Consume BEFORE proceeding: the platform can reenter this callback.
            credential = null;
            if (!active ||
                _credentials == null ||
                !started ||
                value == null ||
                request.host != origin.host ||
                request.realm != 'Secure Area') {
              request.onCancel();
              fail();
              return;
            }
            try {
              request.onProceed(value);
            } catch (_) {
              fail();
            }
          },
          onPageFinished: (url) async {
            // A fresh controller may share Chromium's exact-origin auth cache
            // with an earlier opening of this same live server. A successful
            // JSON navigation then needs no new challenge.
            if (!active || _credentials == null || !started || url != probe) {
              fail();
              return;
            }
            try {
              if (await controller.currentUrl() != probe ||
                  !active ||
                  _credentials == null) {
                fail();
                return;
              }
              active = false;
              if (!ready.isCompleted) ready.complete();
            } catch (_) {
              fail();
            }
          },
          onHttpError: (_) => fail(),
          onWebResourceError: (_) => fail(),
          onSslAuthError: (error) {
            unawaited(error.cancel());
            fail();
          },
        ),
      );
      timer = Timer(timeout, fail);
      // A stuck native load must not prevent the timeout from completing.
      unawaited(
        controller
            .loadRequest(Uri.parse(probe))
            .then<void>((_) {}, onError: (Object _) => fail()),
      );
      await ready.future;
    } catch (_) {
      fail();
      throw const BrowserHttpAuthException();
    } finally {
      _pending.remove(fail);
      timer?.cancel();
      active = false;
      credential = null;
      // No credential-bearing closure survives the bootstrap, including failure.
      await controller.setNavigationDelegate(
        NavigationDelegate(onHttpAuthRequest: (request) => request.onCancel()),
      );
    }
  }
}

class BrowserHttpAuthException implements Exception {
  const BrowserHttpAuthException();

  @override
  String toString() => 'Agent web authentication failed.';
}
