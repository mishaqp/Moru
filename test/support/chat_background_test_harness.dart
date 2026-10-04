import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';

/// Keeps wallpaper rendering fixtures independent of assistant configuration.
Future<void> setTestChatBackground(
  SettingsProvider settings, {
  String? path,
  bool? gradient,
  bool? gradientAnimated,
  double? gradientOffsetY,
  double? gradientPhase,
}) {
  final current = settings.chatAppearance.light;
  final type = gradient == true
      ? ChatBackgroundType.gradient
      : gradient == false
      ? (current.path == null
            ? ChatBackgroundType.none
            : ChatBackgroundType.image)
      : path != null
      ? ChatBackgroundType.image
      : current.type;
  final background = current.copyWith(
    type: type,
    path: path,
    gradientAnimated: gradientAnimated,
    gradientOffsetY: gradientOffsetY,
    gradientPhase: gradientPhase,
  );
  return settings.setChatAppearance(
    ChatAppearanceSettings(light: background, dark: background),
  );
}
