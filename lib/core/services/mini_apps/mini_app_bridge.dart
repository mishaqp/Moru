import 'dart:convert';

import 'mini_app_fetch.dart';
import 'mini_app_jobs.dart';
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
    this.vibrate,
    this.haptic,
    this.close,
    this.jobs,
    this.background = false,
    this.server,
    this.serverUrl,
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

  /// Vibrates for the milliseconds in [pattern]: on, off, on, ...
  final Future<void> Function(List<int> pattern)? vibrate;

  /// A short system haptic, one of [MiniAppBridge.hapticKinds].
  final Future<void> Function(String kind)? haptic;

  /// Closes the app screen.
  final Future<void> Function()? close;
  final MiniAppJobs? jobs;

  /// The app runs out of sight for a background job.
  final bool background;

  /// `moru.server.fetch`: a request to the app's own server.
  final Future<Map<String, Object?>> Function(Map<String, dynamic> args)?
  server;

  /// `moru.server.url`: the address of a path on the app's own server, for
  /// the page to reach it directly.
  final Future<String> Function(String path)? serverUrl;
}

/// Answers `window.moru` calls from one mini app page. Each message is
/// `{id, method, args}`; [handle] returns the JavaScript that settles the
/// page's promise.
class MiniAppBridge {
  MiniAppBridge({
    required this.store,
    required this.appId,
    this.host = const MiniAppHost(),
    this.onProblem,
  });

  static const int maxPromptChars = 32000;

  final MiniAppStore store;
  final String appId;
  final MiniAppHost host;

  /// Called with each problem noted in [pageErrors] (its kind: `error`,
  /// `promise`, `resource`) or [failedCalls] (kind `call`), e.g. to keep it
  /// in the app's error journal.
  final void Function(String kind, String problem)? onProblem;

  static const int maxProblems = 50;

  /// Code of a call the publish check does not make, e.g. to the app's
  /// server; it is not a problem of the app.
  static const String notInCheck = 'not_in_check';

  static const Set<String> hapticKinds = {
    'light',
    'medium',
    'heavy',
    'selection',
  };

  /// Longest vibration pattern: segments and total milliseconds.
  static const int maxVibrationSegments = 20;
  static const int maxVibrationMs = 5000;

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
        final kind = '${args['kind']}';
        _note(pageErrors, kind, '$kind: ${args['message']}');
        return null;
      }
      final value = await _dispatch(method, args);
      return _reply(id, true, value);
    } on MiniAppException catch (e) {
      if (e.code != notInCheck) {
        _note(failedCalls, 'call', '$method: ${e.message}');
      }
      return _reply(id, false, e.message);
    } catch (e) {
      _note(failedCalls, 'call', '$method: $e');
      return _reply(id, false, '$e');
    }
  }

  void _note(List<String> list, String kind, String problem) {
    if (list.length >= maxProblems) return;
    list.add(problem);
    onProblem?.call(kind, problem);
  }

  /// Tells the page that [key] changed outside it.
  static String changedScript(String key) =>
      'window.__moruChanged && window.__moruChanged(${jsonEncode(key)});';

  /// Moru's active theme and WebView insets, available before UI-kit startup
  /// and again when the user switches theme or rotates the phone.
  static String themeScript(Map<String, Object?> theme) =>
      '''
(function () {
  var theme = ${jsonEncode(theme)};
  window.__moruTheme = theme;
  if (window.moru) window.moru.theme = theme;
  var root = document.documentElement;
  root.dataset.moruTheme = theme.dark ? 'dark' : 'light';
  Object.keys(theme.colors || {}).forEach(function (name) {
    root.style.setProperty('--moru-' + name, theme.colors[name]);
  });
  Object.keys(theme.insets || {}).forEach(function (name) {
    root.style.setProperty('--moru-safe-' + name, theme.insets[name] + 'px');
  });
  window.dispatchEvent(new CustomEvent('moru:theme', {detail: theme}));
})();
''';

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
        return {
          'id': appId,
          'name': app?.name,
          'platform': 'android',
          'fullscreen': app?.fullscreen ?? false,
          'orientation': (app?.orientation ?? MiniAppOrientation.any).name,
          'background': host.background,
        };
      case 'app.close':
        await _need(host.close)();
        return null;
      case 'vibrate':
        await _need(host.vibrate)(_vibrationPattern(args['pattern']));
        return null;
      case 'haptic':
        final kind = args['kind'] ?? 'light';
        if (!hapticKinds.contains(kind)) {
          throw MiniAppException(
            'invalid_argument',
            'kind must be one of: ${hapticKinds.join(', ')}.',
          );
        }
        await _need(host.haptic)(kind as String);
        return null;
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
      case 'jobs.set':
        await _need(host.jobs).set(appId, text('id', max: 40), args['job']);
        return null;
      case 'jobs.remove':
        await _need(host.jobs).remove(appId, text('id', max: 40));
        return null;
      case 'jobs.list':
        return [
          for (final job in await _need(host.jobs).list(appId)) job.toJson(),
        ];
      case 'fetch':
        return _need(host.fetch).fetch(_app(), args);
      case 'server.fetch':
        return _need(host.server)(args);
      case 'server.url':
        return _need(host.serverUrl)(text('path', max: 2000));
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

  /// `moru.vibrate(200)` or `moru.vibrate([100, 50, 100])`.
  static List<int> _vibrationPattern(Object? raw) {
    final values = raw is List ? raw : [raw];
    final pattern = <int>[];
    for (final value in values) {
      if (value is! num || !value.isFinite || value < 0) {
        throw const MiniAppException(
          'invalid_argument',
          'pattern must be milliseconds or a list of them.',
        );
      }
      pattern.add(value.round());
    }
    final total = pattern.fold<int>(0, (sum, ms) => sum + ms);
    if (pattern.isEmpty ||
        pattern.length > maxVibrationSegments ||
        total > maxVibrationMs) {
      throw const MiniAppException(
        'invalid_argument',
        'pattern takes 1-$maxVibrationSegments values and at most '
            '$maxVibrationMs ms in total.',
      );
    }
    return pattern;
  }

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
