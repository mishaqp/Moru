import 'dart:convert';
import 'dart:math';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'mini_app_bridge.dart';
import 'mini_app_browser_storage.dart';
import 'mini_app_browser_storage_state.dart';
import 'mini_app_store.dart';
import 'mini_app_web_server.dart';

/// A fixed, isolated HTTPS origin for an app. Android intercepts its requests
/// and reads resources from a private capability-protected loopback server.
/// The server's lifetime and port never change the browser storage identity.
class MiniAppLocalSession {
  MiniAppLocalSession._(
    this._server,
    this._token,
    this._app,
    this._origin,
    this._ephemeral,
  );

  final MiniAppWebServer _server;
  final String _token;
  final MiniApp _app;
  String get _appId => _app.id;
  final Uri _origin;
  final bool _ephemeral;
  MiniAppBrowserStorage? _storage;
  Future<void>? _preparing;
  Future<void>? _closing;

  static Future<MiniAppLocalSession> start({
    required MiniAppStore store,
    required MiniApp app,
    String Function()? bootstrapScript,
    bool ephemeral = false,
  }) async {
    await store.load();
    final origin = ephemeral
        ? null
        : (await MiniAppBrowserStorageState.read(app)).origin;
    final random = Random.secure();
    final token = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final server = MiniAppWebServer(
      store: store,
      bridgeFor: (app) => MiniAppBridge(store: store, appId: app.id),
      onlyAppId: app.id,
      accessToken: token,
      nativeBridge: true,
      pageBootstrap: bootstrapScript,
    );
    await server.start(port: 0, localhostOnly: true);
    final host = ephemeral
        ? 'moru-miniapp-check-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.invalid'
        : origin!.host;
    return MiniAppLocalSession._(
      server,
      token,
      app,
      Uri(scheme: 'https', host: host),
      ephemeral,
    );
  }

  Uri entryUri(MiniApp app) {
    if (app.id != _appId) throw ArgumentError.value(app.id, 'app.id');
    if (!_server.running) throw StateError('The mini app session is closed.');
    return _origin.replace(path: '/${app.entry}');
  }

  /// Private backend address, used only by the native request interceptor.
  Uri backendUri(MiniApp app) {
    if (app.id != _appId) throw ArgumentError.value(app.id, 'app.id');
    final port = _server.port;
    if (port == null) throw StateError('The mini app session is closed.');
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: '/$_token/app/$_appId/${app.entry}',
    );
  }

  bool allowsNavigation(String url) {
    if (_storage?.isMigrating ?? false) {
      return url ==
          _origin.replace(path: MiniAppBrowserStorage.transferPath).toString();
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !_server.running ||
        uri.scheme != _origin.scheme ||
        uri.host != _origin.host ||
        uri.port != _origin.port ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final path = uri.pathSegments;
    return !path.any(
      (part) =>
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains(r'\') ||
          part.contains('\u0000') ||
          RegExp(r'%(?:2e|2f|5c|00)', caseSensitive: false).hasMatch(part),
    );
  }

  bool pageFinished(String url) => _storage?.pageFinished(url) ?? false;

  /// Call after setting the controller's navigation delegate, before loading
  /// app code. A checker uses a throwaway origin and skips legacy storage.
  Future<void> prepare(WebViewController controller) =>
      _preparing ??= _prepare(controller);

  Future<void> _prepare(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return;
    if (!_server.running) throw StateError('The mini app session is closed.');
    final storage = _storage = MiniAppBrowserStorage(
      controller: controller,
      app: _app,
      origin: _origin,
      nativeId: platform.webViewIdentifier,
    );
    await storage.prepare(
      backend: backendUri(_app).replace(path: '/$_token/app/$_appId/'),
      ephemeral: _ephemeral,
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _storage?.close();
    } finally {
      await _server.stop();
    }
  }
}
