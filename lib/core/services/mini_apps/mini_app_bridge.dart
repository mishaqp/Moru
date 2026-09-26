import 'dart:convert';

import 'mini_app_fetch.dart';
import 'mini_app_reminders.dart';
import 'mini_app_store.dart';

/// What a mini app may ask of Moru beyond its own storage.
class MiniAppHost {
  const MiniAppHost({
    this.ask,
    this.notify,
    this.reminders,
    this.fetch,
    this.calendar,
  });

  /// Asks the default model; returns its text.
  final Future<String> Function(String prompt, String? system)? ask;

  /// Shows a notification that opens the app.
  final Future<void> Function(String title, String body)? notify;
  final MiniAppReminders? reminders;
  final MiniAppFetch? fetch;

  /// Runs a device calendar method (`queryCalendar`, `createCalendarEvent`)
  /// and returns its decoded JSON result.
  final Future<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic> args,
  )?
  calendar;
}

/// Answers `window.moru` calls from one mini app page. Each message is
/// `{id, method, args}`; [handle] returns the JavaScript that settles the
/// page's promise.
class MiniAppBridge {
  MiniAppBridge({
    required this.store,
    required this.appId,
    this.host = const MiniAppHost(),
  });

  static const int maxPromptChars = 32000;

  final MiniAppStore store;
  final String appId;
  final MiniAppHost host;

  static const int maxProblems = 50;

  /// One model request at a time, so a looping page cannot flood the model.
  bool _asking = false;

  /// Script errors, rejected promises and files that failed to load, as
  /// `moru.js` reported them.
  final List<String> pageErrors = [];

  /// `moru.*` calls that failed, as "method: message".
  final List<String> failedCalls = [];

  /// The script that settles the page's promise, or null for a message
  /// that needs no answer.
  Future<String?> handle(String message) async {
    Object? id;
    var method = '';
    try {
      final call = Map<String, dynamic>.from(jsonDecode(message) as Map);
      id = call['id'];
      method = '${call['method']}';
      final args = call['args'] is Map
          ? Map<String, dynamic>.from(call['args'] as Map)
          : const <String, dynamic>{};
      if (method == '__report') {
        _note(pageErrors, '${args['kind']}: ${args['message']}');
        return null;
      }
      final value = await _dispatch(method, args);
      return _reply(id, true, value);
    } on MiniAppException catch (e) {
      _note(failedCalls, '$method: ${e.message}');
      return _reply(id, false, e.message);
    } catch (e) {
      _note(failedCalls, '$method: $e');
      return _reply(id, false, '$e');
    }
  }

  static void _note(List<String> list, String problem) {
    if (list.length < maxProblems) list.add(problem);
  }

  /// Tells the page that [key] changed outside it.
  static String changedScript(String key) =>
      'window.__moruChanged && window.__moruChanged(${jsonEncode(key)});';

  Future<Object?> _dispatch(String method, Map<String, dynamic> args) async {
    String text(String name, {int max = 1000, bool required = true}) {
      final value = args[name];
      if (value is! String || (required && value.trim().isEmpty)) {
        if (!required && value == null) return '';
        throw MiniAppException('invalid_argument', '$name must be a string.');
      }
      return value.length <= max ? value : value.substring(0, max);
    }

    // The store checks key length.
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
        await store.storageSet(appId, key(), args['value'], fromApp: true);
        return null;
      case 'storage.remove':
        await store.storageRemove(appId, key(), fromApp: true);
        return null;
      case 'storage.keys':
        return store.storageKeys(appId);
      case 'app.info':
        final app = store.byId(appId);
        return {'id': appId, 'name': app?.name, 'platform': 'android'};
      case 'ai.ask':
        final ask = _need(host.ask);
        final prompt = text('prompt', max: maxPromptChars);
        final system = text('system', max: maxPromptChars, required: false);
        if (_asking) {
          throw const MiniAppException(
            'busy',
            'Wait for the previous moru.ai.ask to finish.',
          );
        }
        _asking = true;
        try {
          return await ask(prompt, system.isEmpty ? null : system);
        } finally {
          _asking = false;
        }
      case 'notify':
        await _need(host.notify)(
          text('title', max: 80),
          text('body', max: 300, required: false),
        );
        return null;
      case 'reminders.set':
        await _need(
          host.reminders,
        ).set(appId, text('id', max: 40), args['reminder']);
        return null;
      case 'reminders.remove':
        await _need(host.reminders).remove(appId, text('id', max: 40));
        return null;
      case 'reminders.list':
        return _need(host.reminders).list(appId);
      case 'fetch':
        return _need(host.fetch).fetch(_app(), args);
      case 'calendar.list':
        return _calendar('queryCalendar', args, _calendarListKeys);
      case 'calendar.add':
        return _calendar('createCalendarEvent', args, _calendarAddKeys);
      default:
        throw MiniAppException('unknown_method', 'Unknown method "$method".');
    }
  }

  static const Set<String> _calendarListKeys = {
    'begin',
    'end',
    'range',
    'query',
    'limit',
    'calendar_id',
    'include_calendars',
  };
  static const Set<String> _calendarAddKeys = {
    'title',
    'description',
    'location',
    'start',
    'end',
    'all_day',
    'reminders',
    'calendar_id',
  };

  MiniApp _app() {
    final app = store.byId(appId);
    if (app == null) {
      throw const MiniAppException('not_found', 'The app was deleted.');
    }
    return app;
  }

  Future<Map<String, dynamic>> _calendar(
    String method,
    Map<String, dynamic> args,
    Set<String> keys,
  ) async {
    final calendar = _need(host.calendar);
    if (!_app().permissions.contains('calendar')) {
      throw const MiniAppException(
        'permission_not_declared',
        'Add "permissions": ["calendar"] to moru-app.json.',
      );
    }
    final result = await calendar(method, {
      for (final entry in args.entries)
        if (keys.contains(entry.key)) entry.key: entry.value,
    });
    final error = result['error'];
    if (error != null) {
      throw MiniAppException('$error', '${result['message'] ?? error}');
    }
    return result;
  }

  static T _need<T>(T? value) {
    if (value == null) {
      throw const MiniAppException(
        'unavailable',
        'This is not available here.',
      );
    }
    return value;
  }

  /// `id` is a number the page chose; anything else is dropped by the page.
  static String _reply(Object? id, bool ok, Object? value) =>
      'window.__moruReply(${jsonEncode(id is num ? id : null)}, $ok, '
      '${jsonEncode(value)});';
}
