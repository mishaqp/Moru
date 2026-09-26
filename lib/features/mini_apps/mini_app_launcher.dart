import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/models/assistant.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import '../../core/services/mini_apps/mini_app_bridge.dart';
import '../../core/services/mini_apps/mini_app_reminders.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../core/services/notification_service.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/snackbar.dart';
import 'pages/mini_app_page.dart';

/// Opens mini apps from links, lists and home screen shortcuts.
class MiniAppLauncher {
  const MiniAppLauncher._();

  static const MethodChannel _channel = MethodChannel('app.mini_apps');
  static final StreamController<String> _launches =
      StreamController.broadcast();
  static bool _initialized = false;

  /// Shortcut taps while Moru is already running.
  static Stream<String> get launches => _launches.stream;

  static MiniAppReminders? _reminders;

  /// Reminders of the installed apps; deleting an app cancels its own.
  static MiniAppReminders get reminders => _reminders ??= () {
    final reminders = MiniAppReminders(
      store: MiniAppStore.instance,
      schedule: NotificationService.scheduleMiniAppReminder,
      cancel: NotificationService.cancel,
    );
    MiniAppStore.instance.addDeleteHook(reminders.cancelAll);
    return reminders;
  }();

  /// The model `moru.ai.ask` uses: the current assistant's chat model, else
  /// the default model, the same order the chat uses.
  static ({String provider, String model})? askModelFor(
    SettingsProvider settings,
    Assistant? assistant,
  ) {
    final provider =
        assistant?.chatModelProvider ?? settings.currentModelProvider;
    final model = assistant?.chatModelId ?? settings.currentModelId;
    if (provider == null || model == null) return null;
    return (provider: provider, model: model);
  }

  /// What [app] may use besides its storage: the chat model, notifications
  /// and reminders.
  static MiniAppHost hostFor(
    MiniApp app,
    SettingsProvider settings,
    AssistantProvider assistants,
  ) => MiniAppHost(
    ask: (prompt, system) async {
      final target = askModelFor(settings, assistants.currentAssistant);
      if (target == null) {
        throw const MiniAppException(
          'no_model',
          'Choose a chat model for the assistant or a default model in '
              'Moru settings first.',
        );
      }
      final result = await ChatApiService.generateMessage(
        config: settings.getProviderConfig(target.provider),
        modelId: target.model,
        messages: [
          if (system != null) {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ],
        textOnly: true,
        skipImageParsing: true,
      );
      return result.text;
    },
    notify: (title, body) async {
      await NotificationService.ensureAndroidNotificationsPermission();
      await NotificationService.showMiniApp(
        id: MiniAppReminders.notificationIds(app.id, '_notify', null).first,
        appId: app.id,
        title: title,
        body: body,
      );
    },
    reminders: reminders,
  );

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onOpenApp') return;
      final id = '${call.arguments ?? ''}'.trim();
      if (id.isNotEmpty) _launches.add(id);
    });
  }

  /// The app a home screen shortcut started Moru with, if any.
  static Future<String?> takeInitialApp() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final id = (await _channel.invokeMethod<String>(
        'takeInitialApp',
      ))?.trim();
      return id == null || id.isEmpty ? null : id;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> open(
    BuildContext context,
    String id, {
    MiniAppStore? store,
  }) async {
    final apps = store ?? MiniAppStore.instance;
    await apps.load();
    if (!context.mounted) return;
    final app = apps.byId(id);
    if (app == null) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.miniAppsNotFound,
        type: NotificationType.warning,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiniAppPage(app: app, store: store),
      ),
    );
  }

  /// Asks the launcher to pin [app]. False when it cannot pin shortcuts.
  static Future<bool> pinShortcut(MiniApp app) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final icon = await renderIcon(app, size: 192);
      return await _channel.invokeMethod<bool>('pinShortcut', {
            'id': app.id,
            'name': app.name,
            'icon': icon,
          }) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// PNG of the app's SVG icon, or of its first letter when it has none.
  static Future<Uint8List> renderIcon(MiniApp app, {required int size}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final extent = size.toDouble();
    final bounds = Rect.fromLTWH(0, 0, extent, extent);
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(extent * 0.22)),
    );
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFF2F2F7));
    final iconPath = app.iconPath;
    var drawn = false;
    if (iconPath != null && await File(iconPath).exists()) {
      try {
        final info = await vg.loadPicture(SvgFileLoader(File(iconPath)), null);
        final source = info.size;
        if (source.width > 0 && source.height > 0) {
          final scale =
              extent /
              (source.width > source.height ? source.width : source.height);
          canvas.save();
          canvas.translate(
            (extent - source.width * scale) / 2,
            (extent - source.height * scale) / 2,
          );
          canvas.scale(scale);
          canvas.drawPicture(info.picture);
          canvas.restore();
          drawn = true;
        }
        info.picture.dispose();
      } catch (e) {
        debugPrint('[MiniApps] icon for ${app.id}: $e');
      }
    }
    if (!drawn) {
      canvas.drawRect(bounds, Paint()..color = const Color(0xFF5A8DDE));
      final letter = TextPainter(
        text: TextSpan(
          text: app.name.characters.first.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: extent * 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      letter.paint(
        canvas,
        Offset((extent - letter.width) / 2, (extent - letter.height) / 2),
      );
    }
    final image = await recorder.endRecording().toImage(size, size);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
