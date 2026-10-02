import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../features/chat/widgets/frosted/frosted_surface.dart';
import '../../../theme/chat_bubble_style.dart';

/// Browser chrome shares the Glass tint and rim, without capturing or blurring
/// the live native page behind it.
ResolvedBubbleStyle browserSurfaceStyle(
  BuildContext context, {
  required Color defaultColor,
}) {
  final preset = context
      .select<
        SettingsProvider?,
        ({bool glass, ChatBubbleStyleOverrides overrides})
      >(
        (settings) => (
          glass: settings?.glassTheme ?? false,
          overrides:
              settings?.chatBubbleStyleOverrides ??
              const ChatBubbleStyleOverrides(),
        ),
      );
  final theme = Theme.of(context);
  if (preset.glass) {
    return resolveBubbleStyle(
      theme.colorScheme,
      theme.brightness,
      ChatMessageBackgroundStyle.frosted,
      preset.overrides.copyWith(blurSigma: () => 0),
    );
  }
  return ResolvedBubbleStyle(
    background: defaultColor,
    border: Colors.transparent,
    text: theme.colorScheme.onSurface,
    borderWidth: 0,
    radius: 0,
    blurSigma: 0,
  );
}

class BrowserSurface extends StatelessWidget {
  const BrowserSurface({
    super.key,
    required this.defaultColor,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final Color defaultColor;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Keep the same ancestry across theme changes, including a parked WebView.
    return FrostedSurface(
      style: browserSurfaceStyle(context, defaultColor: defaultColor),
      borderRadius: borderRadius,
      child: child,
    );
  }
}
