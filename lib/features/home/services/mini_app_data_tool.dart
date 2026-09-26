import 'dart:convert';

import '../../../core/services/mini_apps/mini_app_store.dart';

class _ToolFailure implements Exception {
  const _ToolFailure(this.error, this.message);

  final String error;
  final String message;
}

/// The `mini_apps` local tool: the chat reads and changes the data of the
/// user's mini apps, e.g. "I drank a glass of water", without opening them.
class MiniAppDataTool {
  const MiniAppDataTool({required this.store});

  static const String toolName = 'mini_apps';

  static const String actionList = 'list';
  static const String actionRead = 'read';
  static const String actionWrite = 'write';
  static const String actionRemove = 'remove';

  static const List<String> actions = [
    actionList,
    actionRead,
    actionWrite,
    actionRemove,
  ];

  /// Larger reads return only the keys, so one app cannot flood the context.
  static const int maxReadChars = 20000;

  final MiniAppStore store;

  static String actionOf(Map<String, dynamic> args) =>
      (args['action'] ?? '').toString().trim().toLowerCase();

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Read and change the data of the user\'s Moru mini apps (small web '
          'apps such as a water tracker or a shopping list) without opening '
          'them. Call "list" first: it shows each app\'s id, what it does, '
          'how it stores its data and its keys. Keep the stored format '
          'exactly as the app expects; read a key before writing it. An open '
          'app redraws when its data changes.',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions,
            'description':
                'list: installed apps. read: one key of app_id, or all its '
                'data without key. write: set key of app_id to value. '
                'remove: delete key of app_id.',
          },
          'app_id': {'type': 'string', 'description': 'App id from "list".'},
          'key': {'type': 'string', 'description': 'Storage key.'},
          'value': {'description': 'JSON value to store under key.'},
        },
        'required': ['action'],
      },
    },
  };

  Future<String> execute(Map<String, dynamic> args) async {
    try {
      await store.load();
      final action = actionOf(args);
      final Map<String, dynamic> result;
      switch (action) {
        case actionList:
          result = {'apps': await _list()};
        case actionRead:
          result = await _read(args);
        case actionWrite:
          final app = _app(args);
          final key = _key(args);
          if (!args.containsKey('value')) {
            throw const _ToolFailure('missing_value', '"value" is required.');
          }
          await store.storageSet(app.id, key, args['value']);
          result = {'written': key};
        case actionRemove:
          final app = _app(args);
          final key = _key(args);
          await store.storageRemove(app.id, key);
          result = {'removed': key};
        default:
          throw _ToolFailure(
            'invalid_action',
            'Unknown action "$action". Use one of: ${actions.join(', ')}.',
          );
      }
      return jsonEncode({'ok': true, ...result});
    } on _ToolFailure catch (e) {
      return jsonEncode({'ok': false, 'error': e.error, 'message': e.message});
    } on MiniAppException catch (e) {
      return jsonEncode({'ok': false, 'error': e.code, 'message': e.message});
    }
  }

  Future<List<Map<String, dynamic>>> _list() async => [
    for (final app in store.apps)
      {
        'id': app.id,
        'name': app.name,
        if (app.description.isNotEmpty) 'description': app.description,
        if (app.dataHelp.isNotEmpty) 'data': app.dataHelp,
        'keys': await store.storageKeys(app.id),
      },
  ];

  Future<Map<String, dynamic>> _read(Map<String, dynamic> args) async {
    final app = _app(args);
    final key = args['key'];
    if (key is String && key.isNotEmpty) {
      return {'key': key, 'value': await store.storageGet(app.id, key)};
    }
    final all = await store.storageAll(app.id);
    if (jsonEncode(all).length > maxReadChars) {
      return {
        'keys': all.keys.toList(),
        'note': 'The data is large; read one key at a time.',
      };
    }
    return {'data': all};
  }

  MiniApp _app(Map<String, dynamic> args) {
    final id = '${args['app_id'] ?? ''}'.trim();
    final app = store.byId(id);
    if (app == null) {
      throw _ToolFailure(
        'not_found',
        'No mini app "$id". Call "list" to get the ids.',
      );
    }
    return app;
  }

  static String _key(Map<String, dynamic> args) {
    final key = args['key'];
    if (key is! String || key.isEmpty) {
      throw const _ToolFailure('missing_key', '"key" is required.');
    }
    return key;
  }
}
