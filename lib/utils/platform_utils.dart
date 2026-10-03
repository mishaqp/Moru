import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:restart_app/restart_app.dart';

abstract final class PlatformUtils {
  PlatformUtils._();

  static bool get isMobileTarget =>
      defaultTargetPlatform == TargetPlatform.android;

  static bool get isAndroid => Platform.isAndroid;

  static Future<void> restartApp() async {
    final result = await Restart.restartApp(mode: RestartMode.process);
    if (!result.success) {
      throw StateError('restart_app:${result.code ?? 'unknown'}');
    }
  }
}
