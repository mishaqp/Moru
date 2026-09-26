import 'dart:convert';

import 'mini_app_store.dart';

/// Answers `window.moru` calls from one mini app page. Each message is
/// `{id, method, args}`; [handle] returns the JavaScript that settles the
/// page's promise.
class MiniAppBridge {
  const MiniAppBridge({required this.store, required this.appId});

  final MiniAppStore store;
  final String appId;

  Future<String> handle(String message) async {
    Object? id;
    try {
      final call = Map<String, dynamic>.from(jsonDecode(message) as Map);
      id = call['id'];
      final args = call['args'] is Map
          ? Map<String, dynamic>.from(call['args'] as Map)
          : const <String, dynamic>{};
      final value = await _dispatch('${call['method']}', args);
      return _reply(id, true, value);
    } on MiniAppException catch (e) {
      return _reply(id, false, e.message);
    } catch (e) {
      return _reply(id, false, '$e');
    }
  }

  Future<Object?> _dispatch(String method, Map<String, dynamic> args) async {
    String key() {
      final value = args['key'];
      if (value is! String) {
        throw const MiniAppException('invalid_key', 'key must be a string.');
      }
      return value;
    }

    switch (method) {
      case 'storage.get':
        return store.storageGet(appId, key());
      case 'storage.set':
        await store.storageSet(appId, key(), args['value']);
        return null;
      case 'storage.remove':
        await store.storageRemove(appId, key());
        return null;
      case 'storage.keys':
        return store.storageKeys(appId);
      case 'app.info':
        final app = store.byId(appId);
        return {'id': appId, 'name': app?.name, 'platform': 'android'};
      default:
        throw MiniAppException('unknown_method', 'Unknown method "$method".');
    }
  }

  /// `id` is a number the page chose; anything else is dropped by the page.
  static String _reply(Object? id, bool ok, Object? value) =>
      'window.__moruReply(${jsonEncode(id is num ? id : null)}, $ok, '
      '${jsonEncode(value)});';
}
