import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../pages/webview/browser_mini_window.dart';
import 'snackbar.dart';
import 'tts_floating_player.dart';

class AppOverlays extends StatelessWidget {
  const AppOverlays({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final floatingBrowser = context.select<SettingsProvider?, bool>(
      (settings) => settings?.browserFloatingWindow ?? false,
    );
    return Overlay.wrap(
      child: Stack(
        children: [
          AppSnackBarOverlay(child: child),
          const Material(
            type: MaterialType.transparency,
            child: TtsFloatingPlayer(),
          ),
          BrowserMiniWindow(floating: floatingBrowser),
        ],
      ),
    );
  }
}
