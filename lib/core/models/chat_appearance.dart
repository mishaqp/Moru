import 'package:flutter/material.dart' show Brightness;

enum ChatBackgroundType { none, image, gif, video, gradient }

enum ChatBackgroundFit { cover, contain, fill, tile }

/// A global chat wallpaper. Local media use portable `kelivo-file:` references.
class ChatBackgroundSettings {
  const ChatBackgroundSettings({
    this.type = ChatBackgroundType.none,
    this.path,
    this.fit = ChatBackgroundFit.cover,
    this.focusX = 0,
    this.focusY = 0,
    this.maskStrength = 1,
    this.blur = 0,
    this.brightness = 1,
    this.saturation = 1,
    this.gradientAnimated = true,
    this.gradientPhase = 7,
    this.gradientOffsetX = 0,
    this.gradientOffsetY = 0,
  });

  final ChatBackgroundType type;
  final String? path;
  final ChatBackgroundFit fit;
  final double focusX;
  final double focusY;
  final double maskStrength;
  final double blur;
  final double brightness;
  final double saturation;
  final bool gradientAnimated;
  final double gradientPhase;
  final double gradientOffsetX;
  final double gradientOffsetY;

  factory ChatBackgroundSettings.fromJson(Map<String, dynamic> json) {
    double bounded(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final type = ChatBackgroundType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => ChatBackgroundType.none,
    );
    var fit = ChatBackgroundFit.values.firstWhere(
      (value) => value.name == json['fit'],
      orElse: () => ChatBackgroundFit.cover,
    );
    if (fit == ChatBackgroundFit.tile &&
        type != ChatBackgroundType.image &&
        type != ChatBackgroundType.gif) {
      fit = ChatBackgroundFit.cover;
    }
    final rawPath = json['path'];
    final rawPhase = json['gradientPhase'];
    return ChatBackgroundSettings(
      type: type,
      path: rawPath is String && rawPath.isNotEmpty ? rawPath : null,
      fit: fit,
      focusX: bounded('focusX', 0, -1, 1),
      focusY: bounded('focusY', 0, -1, 1),
      maskStrength: bounded('maskStrength', 1, 0, 2),
      blur: bounded('blur', 0, 0, 30),
      brightness: bounded('brightness', 1, 0, 2),
      saturation: bounded('saturation', 1, 0, 2),
      gradientAnimated: json['gradientAnimated'] != false,
      gradientPhase: rawPhase is num && rawPhase.isFinite && rawPhase >= 0
          ? rawPhase.toDouble()
          : 7,
      gradientOffsetX: bounded('gradientOffsetX', 0, -1, 1),
      gradientOffsetY: bounded('gradientOffsetY', 0, -1, 1),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (path != null) 'path': path,
    'fit': fit.name,
    'focusX': focusX,
    'focusY': focusY,
    'maskStrength': maskStrength,
    'blur': blur,
    'brightness': brightness,
    'saturation': saturation,
    'gradientAnimated': gradientAnimated,
    'gradientPhase': gradientPhase,
    'gradientOffsetX': gradientOffsetX,
    'gradientOffsetY': gradientOffsetY,
  };

  ChatBackgroundSettings copyWith({
    ChatBackgroundType? type,
    String? path,
    bool clearPath = false,
    ChatBackgroundFit? fit,
    double? focusX,
    double? focusY,
    double? maskStrength,
    double? blur,
    double? brightness,
    double? saturation,
    bool? gradientAnimated,
    double? gradientPhase,
    double? gradientOffsetX,
    double? gradientOffsetY,
  }) => ChatBackgroundSettings.fromJson({
    'type': (type ?? this.type).name,
    'path': clearPath ? null : path ?? this.path,
    'fit': (fit ?? this.fit).name,
    'focusX': focusX ?? this.focusX,
    'focusY': focusY ?? this.focusY,
    'maskStrength': maskStrength ?? this.maskStrength,
    'blur': blur ?? this.blur,
    'brightness': brightness ?? this.brightness,
    'saturation': saturation ?? this.saturation,
    'gradientAnimated': gradientAnimated ?? this.gradientAnimated,
    'gradientPhase': gradientPhase ?? this.gradientPhase,
    'gradientOffsetX': gradientOffsetX ?? this.gradientOffsetX,
    'gradientOffsetY': gradientOffsetY ?? this.gradientOffsetY,
  });

  @override
  bool operator ==(Object other) =>
      other is ChatBackgroundSettings &&
      type == other.type &&
      path == other.path &&
      fit == other.fit &&
      focusX == other.focusX &&
      focusY == other.focusY &&
      maskStrength == other.maskStrength &&
      blur == other.blur &&
      brightness == other.brightness &&
      saturation == other.saturation &&
      gradientAnimated == other.gradientAnimated &&
      gradientPhase == other.gradientPhase &&
      gradientOffsetX == other.gradientOffsetX &&
      gradientOffsetY == other.gradientOffsetY;

  @override
  int get hashCode => Object.hash(
    type,
    path,
    fit,
    focusX,
    focusY,
    maskStrength,
    blur,
    brightness,
    saturation,
    gradientAnimated,
    gradientPhase,
    gradientOffsetX,
    gradientOffsetY,
  );
}

class ChatAppearanceSettings {
  const ChatAppearanceSettings({
    this.shared = true,
    this.light = const ChatBackgroundSettings(),
    this.dark = const ChatBackgroundSettings(),
  });

  final bool shared;
  final ChatBackgroundSettings light;
  final ChatBackgroundSettings dark;

  ChatBackgroundSettings backgroundFor(Brightness brightness) =>
      !shared && brightness == Brightness.dark ? dark : light;

  factory ChatAppearanceSettings.fromJson(Map<String, dynamic> json) {
    ChatBackgroundSettings background(String key) {
      final value = json[key];
      return value is Map
          ? ChatBackgroundSettings.fromJson(Map<String, dynamic>.from(value))
          : const ChatBackgroundSettings();
    }

    return ChatAppearanceSettings(
      shared: json['shared'] != false,
      light: background('light'),
      dark: background('dark'),
    );
  }

  Map<String, dynamic> toJson() => {
    'shared': shared,
    'light': light.toJson(),
    'dark': dark.toJson(),
  };

  ChatAppearanceSettings copyWith({
    bool? shared,
    ChatBackgroundSettings? light,
    ChatBackgroundSettings? dark,
  }) => ChatAppearanceSettings(
    shared: shared ?? this.shared,
    light: light ?? this.light,
    dark: dark ?? this.dark,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatAppearanceSettings &&
      shared == other.shared &&
      light == other.light &&
      dark == other.dark;

  @override
  int get hashCode => Object.hash(shared, light, dark);
}
