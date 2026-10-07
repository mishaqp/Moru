import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/services/mini_apps/mini_app_store.dart';
import '../../core/services/screen_wakelock.dart';

/// How an open mini app uses the screen, from its manifest.
class MiniAppDisplay {
  const MiniAppDisplay._();

  /// Applies the manifest's fullscreen, orientation and keepAwake, undoing
  /// what [previous] set; null [next] restores Moru's own.
  static void apply(MiniApp? previous, MiniApp? next) {
    // Hold before letting go, so the screen stays on between two apps
    // that both want it.
    if (next?.keepAwake ?? false) ScreenWakelock.hold();
    if (previous?.keepAwake ?? false) ScreenWakelock.unhold();
    final fullscreen = next?.fullscreen ?? false;
    if ((previous?.fullscreen ?? false) != fullscreen) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    }
    final orientation = next?.orientation ?? MiniAppOrientation.any;
    if ((previous?.orientation ?? MiniAppOrientation.any) != orientation) {
      unawaited(
        SystemChrome.setPreferredOrientations(switch (orientation) {
          MiniAppOrientation.any => const [],
          MiniAppOrientation.portrait => const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
          MiniAppOrientation.landscape => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        }),
      );
    }
  }
}
