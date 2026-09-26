import 'dart:convert';

import 'mini_app_store.dart';

typedef ReminderScheduler =
    Future<void> Function({
      required int id,
      required String appId,
      required String title,
      required String body,
      required int hour,
      required int minute,
      int? weekday,
    });

/// Repeating reminders a mini app sets with `moru.reminders`. Definitions are
/// kept with the app; each one becomes one daily notification, or one per
/// chosen weekday.
class MiniAppReminders {
  MiniAppReminders({
    required this.store,
    required this.schedule,
    required this.cancel,
  });

  static const int maxReminders = 20;

  final MiniAppStore store;
  final ReminderScheduler schedule;
  final Future<void> Function(int id) cancel;

  static final RegExp _time = RegExp(r'^(\d{1,2}):(\d{2})$');
  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  Future<Map<String, dynamic>> list(String appId) => store.readReminders(appId);

  /// Adds or replaces reminder [id]: `{time: "HH:mm", days?: [1..7],
  /// title?, body?}`.
  Future<void> set(String appId, String id, Object? raw) async {
    if (!_id.hasMatch(id)) {
      throw const MiniAppException(
        'invalid_reminder',
        'Reminder ids are 1-40 letters, digits, "-" or "_".',
      );
    }
    final reminder = normalize(raw, fallbackTitle: store.byId(appId)?.name);
    final all = await store.readReminders(appId);
    if (!all.containsKey(id) && all.length >= maxReminders) {
      throw const MiniAppException(
        'too_many_reminders',
        'An app may keep at most $maxReminders reminders.',
      );
    }
    await _cancel(appId, id, all[id]);
    all[id] = reminder;
    await store.writeReminders(appId, all);
    await _schedule(appId, id, reminder);
  }

  Future<void> remove(String appId, String id) async {
    final all = await store.readReminders(appId);
    final previous = all.remove(id);
    if (previous == null) return;
    await _cancel(appId, id, previous);
    await store.writeReminders(appId, all);
  }

  /// Cancels every reminder of the app, for example before it is deleted.
  Future<void> cancelAll(String appId) async {
    final all = await store.readReminders(appId);
    for (final entry in all.entries) {
      await _cancel(appId, entry.key, entry.value);
    }
  }

  /// Checks and completes a reminder definition.
  static Map<String, dynamic> normalize(Object? raw, {String? fallbackTitle}) {
    if (raw is! Map) {
      throw const MiniAppException(
        'invalid_reminder',
        'A reminder is an object with "time".',
      );
    }
    final match = _time.firstMatch('${raw['time'] ?? ''}'.trim());
    final hour = int.tryParse(match?.group(1) ?? '') ?? -1;
    final minute = int.tryParse(match?.group(2) ?? '') ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const MiniAppException(
        'invalid_reminder',
        '"time" must be "HH:mm".',
      );
    }
    final days = raw['days'];
    List<int>? weekdays;
    if (days != null) {
      if (days is! List ||
          days.isEmpty ||
          days.any((d) => d is! int || d < 1 || d > 7)) {
        throw const MiniAppException(
          'invalid_reminder',
          '"days" must list weekdays from 1 (Monday) to 7 (Sunday).',
        );
      }
      weekdays = days.cast<int>().toSet().toList()..sort();
      if (weekdays.length == 7) weekdays = null;
    }
    String text(Object? value, int max) {
      final t = '${value ?? ''}'.trim();
      return t.length <= max ? t : t.substring(0, max);
    }

    final title = text(raw['title'], 80);
    return {
      'time':
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      'days': ?weekdays,
      'title': title.isEmpty ? (fallbackTitle ?? 'Moru') : title,
      'body': text(raw['body'], 300),
    };
  }

  /// Notification ids of one reminder: one per weekday, or one daily.
  static List<int> notificationIds(String appId, String id, Object? reminder) {
    final days = reminder is Map && reminder['days'] is List
        ? (reminder['days'] as List).cast<int>()
        : const [0];
    return [for (final day in days) _hash('$appId/$id/$day')];
  }

  Future<void> _cancel(String appId, String id, Object? reminder) async {
    if (reminder == null) return;
    for (final notification in notificationIds(appId, id, reminder)) {
      await cancel(notification);
    }
  }

  Future<void> _schedule(
    String appId,
    String id,
    Map<String, dynamic> reminder,
  ) async {
    final parts = (reminder['time'] as String).split(':');
    final days = (reminder['days'] as List?)?.cast<int>();
    final ids = notificationIds(appId, id, reminder);
    for (var i = 0; i < ids.length; i++) {
      await schedule(
        id: ids[i],
        appId: appId,
        title: reminder['title'] as String,
        body: reminder['body'] as String,
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
        weekday: days?[i],
      );
    }
  }

  /// A 30-bit FNV-1a hash in the upper half of the id space; a clash with a
  /// chat notification id only replaces that one notification.
  static int _hash(String key) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key)) {
      hash = ((hash ^ byte) * 0x01000193) & 0x3fffffff;
    }
    return 0x40000000 + hash;
  }
}
