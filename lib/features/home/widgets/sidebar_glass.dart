import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/models/chat_appearance.dart';
import '../../../core/providers/settings_provider.dart';
import '../../chat/widgets/chat_background.dart';
import '../../chat/widgets/chat_gradient_background.dart';
import '../../chat/widgets/frosted/chat_frosted_backdrop.dart';

/// Frosted glass behind the sidebar in the glass theme: the chat's own
/// backdrop (the assistant's wallpaper, or a still frame of the glass
/// gradient) blurred under a veil, so the panel reads as a sheet of glass
/// over the same scene. Economy mode keeps the translucency without the
/// blur.
class SidebarGlassBackdrop extends StatelessWidget {
  const SidebarGlassBackdrop({super.key});

  static const double blurSigma = 26;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final economy = context.select<SettingsProvider, bool>(
      (s) => s.glassEconomy,
    );
    final wallpaper =
        context.select<AssistantProvider, String?>(
          (p) => p.currentAssistant?.background,
        ) ??
        '';
    final dark = Theme.of(context).brightness == Brightness.dark;

    // A wallpaper is static; the gradient animates in the chat, so the panel
    // takes one still frame of it and never repaints while it slides.
    Widget scene = ChatBackdropSpec.isBackgroundActive(wallpaper)
        ? ChatBackground(
            configuration: ChatBackgroundSettings(
              type: ChatBackgroundType.image,
              path: wallpaper,
              maskStrength: context.select<SettingsProvider, double>(
                (s) => s.chatBackgroundMaskStrength,
              ),
            ),
            active: false,
          )
        : ChatGradientBackgroundHost(
            enabled: false,
            phase: 7,
            accent: cs.primary,
            child: const ChatGradientBackground(),
          );
    if (!economy) {
      scene = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.clamp,
        ),
        child: RepaintBoundary(child: scene),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(child: scene),
        ColoredBox(
          color: cs.surface.withValues(
            alpha: economy ? (dark ? 0.58 : 0.5) : (dark ? 0.42 : 0.36),
          ),
        ),
      ],
    );
  }
}

/// Whether sidebar rows and bars go without their own fill: in the tablet
/// side panel, and on the glass theme, where a solid fill would cover the
/// frosted backdrop with dark slabs.
bool sidebarSurfacesClear(BuildContext context, {required bool embedded}) =>
    embedded || context.select<SettingsProvider, bool>((s) => s.glassTheme);

/// A light glass tile on the sidebar glass (search, buttons): a brighter
/// veil and a hairline edge. Plain surfaces without the glass theme.
BoxDecoration sidebarGlassTile(
  BuildContext context, {
  required bool glass,
  required BorderRadius radius,
  Color? fill,
}) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (!glass) {
    return BoxDecoration(
      color: fill ?? cs.surfaceContainerHighest.withValues(alpha: 0.8),
      borderRadius: radius,
    );
  }
  return BoxDecoration(
    color: fill ?? cs.surface.withValues(alpha: dark ? 0.34 : 0.55),
    borderRadius: radius,
    border: Border.all(
      color: (dark ? Colors.white : Colors.black).withValues(
        alpha: dark ? 0.1 : 0.06,
      ),
      width: 0.8,
    ),
  );
}
