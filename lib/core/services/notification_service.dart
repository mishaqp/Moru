import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_ru.dart';

typedef ChatCompletionNotificationSender =
    Future<void> Function({
      required String conversationId,
      String? title,
      String? body,
    });

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final StreamController<String> _conversationTapController =
      StreamController<String>.broadcast();
  static final StreamController<String> _scheduledRunTapController =
      StreamController<String>.broadcast();
  static String? _pendingScheduledRunId;
  static final StreamController<String> _miniAppTapController =
      StreamController<String>.broadcast();
  static String? _pendingMiniAppId;
  static const String _miniAppPayloadPrefix = 'mini-app:';

  /// Taps on mini app notifications, as app ids.
  static Stream<String> get miniAppTaps => _miniAppTapController.stream;
  static String? takePendingMiniAppId() {
    final id = _pendingMiniAppId;
    _pendingMiniAppId = null;
    return id;
  }

  static Stream<String> get scheduledRunTaps =>
      _scheduledRunTapController.stream;
  static String? takePendingScheduledRunId() {
    final id = _pendingScheduledRunId;
    _pendingScheduledRunId = null;
    return id;
  }

  static bool _inited = false;
  static Future<void>? _initialization;
  static String? _pendingConversationId;
  static final Map<String, String> _pendingMessageIds = {};
  static String? takePendingMessageId(String conversationId) =>
      _pendingMessageIds.remove(conversationId);
  static const String _chatCompletionPayloadPrefix = 'chat-complete:';
  static AppLocalizations _l10n = AppLocalizationsRu();

  static ({
    String title,
    String body,
    String channelName,
    String channelDescription,
  })
  get completionText => (
    title: _l10n.notificationChatCompletedTitle,
    body: _l10n.notificationChatCompletedBody,
    channelName: _l10n.moruChatNotificationChannel,
    channelDescription: _l10n.moruChatNotificationDescription,
  );

  static AndroidNotificationChannel get _channel => AndroidNotificationChannel(
    'kelivo_bg_chat_v2',
    completionText.channelName,
    description: completionText.channelDescription,
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> configureLocalizations(AppLocalizations l10n) async {
    final changed = _l10n.localeName != l10n.localeName;
    _l10n = l10n;
    if (changed && _inited && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
    }
  }

  static Stream<String> get conversationTaps =>
      _conversationTapController.stream;

  /// Returns a notification target received before the home page subscribed.
  static String? takePendingConversationId() {
    final conversationId = _pendingConversationId;
    _pendingConversationId = null;
    return conversationId;
  }

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_inited) return;
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }

    final initialization = _initializeAndroid();
    _initialization = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    }
  }

  static Future<void> _initializeAndroid() async {
    // Android initialization
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@drawable/ic_background_generation');
    const InitializationSettings init = InitializationSettings(
      android: androidInit,
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Create channel
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(_channel);
      // Runtime notification permission (Android 13+) should be requested by app UI if needed
    }
    _inited = true;

    // The response callback covers warm starts. Cold starts must be queried
    // explicitly after plugin initialization.
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final response = launchDetails?.notificationResponse;
        if (response != null) _handleNotificationResponse(response);
      }
    } catch (_) {}
  }

  /// Ensure Android 13+ notifications permission is granted (no-op on lower versions/other platforms).
  static Future<bool> ensureAndroidNotificationsPermission() async {
    if (!Platform.isAndroid) return true;
    await ensureInitialized();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    try {
      final enabled = await android.areNotificationsEnabled();
      if (enabled == true) return true;
    } catch (_) {}
    try {
      final ok = await android.requestNotificationsPermission();
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showChatCompleted({
    required String conversationId,
    String? title,
    String? body,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (conversationId.trim().isEmpty) return;
    await ensureInitialized();
    await _plugin.show(
      notificationIdForConversation(conversationId),
      title ?? completionText.title,
      body ?? completionText.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          ticker: 'Kelivo',
          styleInformation: BigTextStyleInformation(
            body ?? completionText.body,
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          threadIdentifier: 'kelivo.chat-completion',
        ),
      ),
      payload: '$_chatCompletionPayloadPrefix$conversationId',
    );
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final miniApp = miniAppIdFromPayload(response.payload);
    if (miniApp != null) {
      if (_miniAppTapController.hasListener) {
        _miniAppTapController.add(miniApp);
      } else {
        _pendingMiniAppId = miniApp;
      }
      return;
    }
    final runId = scheduledRunIdFromPayload(response.payload);
    if (runId != null) {
      if (_scheduledRunTapController.hasListener) {
        _scheduledRunTapController.add(runId);
      } else {
        _pendingScheduledRunId = runId;
      }
      return;
    }
    final conversationId = conversationIdFromPayload(response.payload);
    if (conversationId == null) return;
    openConversation(conversationId);
  }

  /// Also receives taps from the native ongoing notification, overlay and
  /// ActivityKit. Keep the target until the home route has initialized.
  static void openConversation(String conversationId, {String? messageId}) {
    if (messageId != null) _pendingMessageIds[conversationId] = messageId;
    if (conversationId.trim().isEmpty) return;
    if (_conversationTapController.hasListener) {
      _conversationTapController.add(conversationId);
    } else {
      _pendingConversationId = conversationId;
    }
  }

  @visibleForTesting
  static String? conversationIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_chatCompletionPayloadPrefix)) {
      return null;
    }
    final conversationId = payload
        .substring(_chatCompletionPayloadPrefix.length)
        .trim();
    return conversationId.isEmpty ? null : conversationId;
  }

  @visibleForTesting
  static String? miniAppIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_miniAppPayloadPrefix)) {
      return null;
    }
    final id = payload.substring(_miniAppPayloadPrefix.length).trim();
    return id.isEmpty ? null : id;
  }

  // ---------------------------------------------------------------------------
  // Mini apps
  // ---------------------------------------------------------------------------

  static AndroidNotificationDetails get _miniAppDetails =>
      AndroidNotificationDetails(
        'moru_mini_apps',
        _l10n.miniAppsNotificationChannel,
        channelDescription: _l10n.miniAppsNotificationChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      );

  static Future<void> showMiniApp({
    required int id,
    required String appId,
    required String title,
    required String body,
  }) async {
    await ensureInitialized();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: _miniAppDetails),
      payload: '$_miniAppPayloadPrefix$appId',
    );
  }

  static bool _timeZoneReady = false;

  static Future<void> _ensureTimeZone() async {
    if (_timeZoneReady) return;
    tz_data.initializeTimeZones();
    String? name;
    try {
      name = await const MethodChannel(
        'app.mini_apps',
      ).invokeMethod<String>('localTimeZone');
    } catch (_) {}
    try {
      tz.setLocalLocation(tz.getLocation(name ?? 'UTC'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _timeZoneReady = true;
  }

  /// Repeats at [hour]:[minute] every day, or every [weekday] (1 = Monday).
  static Future<void> scheduleMiniAppReminder({
    required int id,
    required String appId,
    required String title,
    required String body,
    required int hour,
    required int minute,
    int? weekday,
  }) async {
    await ensureInitialized();
    await _ensureTimeZone();
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    while (!next.isAfter(now) || (weekday != null && next.weekday != weekday)) {
      next = next.add(const Duration(days: 1));
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      next,
      NotificationDetails(android: _miniAppDetails),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: weekday == null
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      payload: '$_miniAppPayloadPrefix$appId',
    );
  }

  static Future<void> cancel(int id) async {
    await ensureInitialized();
    await _plugin.cancel(id);
  }

  @visibleForTesting
  static String? scheduledRunIdFromPayload(String? payload) {
    const prefix = 'scheduled-task:';
    if (payload == null || !payload.startsWith(prefix)) return null;
    final id = payload.substring(prefix.length).trim();
    return id.isEmpty ? null : id;
  }

  /// Stable per-conversation IDs let notifications from different chats
  /// coexist while a later completion in the same chat replaces the old one.
  @visibleForTesting
  static int notificationIdForConversation(String conversationId) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(conversationId)) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    const firstChatNotificationId = 10000;
    return firstChatNotificationId +
        (hash % (0x7fffffff - firstChatNotificationId));
  }
}
