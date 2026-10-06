import 'dart:convert';
import 'dart:math';

import 'mini_app_bridge.dart';
import 'mini_app_store.dart';
import 'mini_app_web_server.dart';

/// A local HTTP origin for one WebView. Modules, WASM and relative asset
/// fetches work without a network connection or duplicating APK resources.
/// Native bridge calls remain inside the WebView's JavaScript channel.
class MiniAppLocalSession {
  MiniAppLocalSession._(this._server, this._token, this._appId);

  final MiniAppWebServer _server;
  final String _token;
  final String _appId;

  static Future<MiniAppLocalSession> start({
    required MiniAppStore store,
    required MiniApp app,
    String Function()? bootstrapScript,
  }) async {
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
    return MiniAppLocalSession._(server, token, app.id);
  }

  Uri entryUri(MiniApp app) {
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
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !_server.running ||
        uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != _server.port ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final path = uri.pathSegments;
    return path.length >= 3 &&
        path[0] == _token &&
        path[1] == 'app' &&
        path[2] == _appId &&
        !path.any(
          (part) => part == '..' || part.contains('/') || part.contains(r'\'),
        );
  }

  Future<void> close() => _server.stop();
}
