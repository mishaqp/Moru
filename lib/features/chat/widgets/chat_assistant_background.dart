import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/providers/settings_provider.dart';
import 'chat_background.dart';

/// Global chat artwork. The legacy name is kept for the shared home layouts.
class ChatAssistantBackground extends StatelessWidget {
  const ChatAssistantBackground({
    super.key,
    this.desktop = false,
    this.pinnedToBackdrop = false,
    this.includeSurfaceFill = false,
    this.expand = true,
  });

  final bool desktop;
  final bool pinnedToBackdrop;
  final bool includeSurfaceFill;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final configuration = context
        .select<SettingsProvider, ChatBackgroundSettings>(
          (settings) => settings.chatAppearance.backgroundFor(brightness),
        );
    if (!expand &&
        configuration.type == ChatBackgroundType.none &&
        !includeSurfaceFill) {
      return const SizedBox.shrink();
    }
    return ChatBackground(
      configuration: configuration,
      desktop: desktop,
      includeSurfaceFill: includeSurfaceFill,
    );
  }
}
