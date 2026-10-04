import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart' show Brightness;

import 'chat_appearance.dart';

enum SidebarBackgroundMode { sameAsChat, custom, theme }

enum SidebarDensity { compact, normal, spacious }

enum SidebarGrouping { date, assistant, none }

enum SidebarDockItem {
  profile,
  settings,
  memory,
  miniApps,
  environment,
  translate,
  scheduledTasks,
}

/// Sidebar presentation only; folders, pinned shortcuts and thumbnails retain
/// their existing preference keys.
@immutable
class SidebarAppearanceSettings {
  const SidebarAppearanceSettings({
    this.backgroundMode = SidebarBackgroundMode.sameAsChat,
    this.customBackground = const ChatBackgroundSettings(),
    this.maskStrength = 1,
    this.blur = 0,
    this.opacity = 1,
    this.phoneWidthPercent = 80,
    this.wideWidthPercent = 30,
    this.density = SidebarDensity.normal,
    this.cardRadius = 14,
    this.cardColor,
    this.activeCardColor,
    this.showTimestamp = false,
    this.showAssistant = false,
    this.showModel = false,
    this.showPreview = false,
    this.grouping = SidebarGrouping.date,
    this.dockItems = defaultDockItems,
  });

  static const minPhoneWidthPercent = 60.0;
  static const maxPhoneWidthPercent = 95.0;
  static const minWideWidthPercent = 20.0;
  static const maxWideWidthPercent = 45.0;
  static const defaultDockItems = <SidebarDockItem>[
    SidebarDockItem.profile,
    SidebarDockItem.settings,
    SidebarDockItem.memory,
    SidebarDockItem.miniApps,
    SidebarDockItem.environment,
    SidebarDockItem.translate,
    SidebarDockItem.scheduledTasks,
  ];

  final SidebarBackgroundMode backgroundMode;
  final ChatBackgroundSettings customBackground;
  final double maskStrength;
  final double blur;

  /// Opacity of the entire background scene, independent of sidebar content.
  final double opacity;
  final double phoneWidthPercent;
  final double wideWidthPercent;
  final SidebarDensity density;
  final double cardRadius;

  /// Optional ARGB colors; their own alpha controls the card's opacity.
  final int? cardColor;
  final int? activeCardColor;
  final bool showTimestamp;
  final bool showAssistant;
  final bool showModel;
  final bool showPreview;
  final SidebarGrouping grouping;

  /// Enabled dock actions in the user's order. An empty list hides the dock.
  final List<SidebarDockItem> dockItems;

  ChatBackgroundSettings backgroundFor(
    Brightness brightness,
    ChatAppearanceSettings chatAppearance,
  ) => switch (backgroundMode) {
    SidebarBackgroundMode.sameAsChat => chatAppearance.backgroundFor(
      brightness,
    ),
    SidebarBackgroundMode.custom => customBackground,
    SidebarBackgroundMode.theme => const ChatBackgroundSettings(),
  };

  /// Shared bounds keep previews and the phone/tablet layouts consistent.
  double widthFor(double screenWidth, {required bool wide}) {
    if (!screenWidth.isFinite || screenWidth <= 0) return 0;
    final upper = wide
        ? math.min(480.0, math.max(0.0, screenWidth - 320))
        : screenWidth * 0.95;
    final lower = math.min(240.0, upper);
    final percent = wide ? wideWidthPercent : phoneWidthPercent;
    return (screenWidth * percent / 100).clamp(lower, upper);
  }

  factory SidebarAppearanceSettings.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) =>
        values.firstWhere(
          (value) => value.name == json[key],
          orElse: () => fallback,
        );
    double bounded(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    int? color(String key) {
      final value = json[key];
      return value is int && value >= 0 && value <= 0xffffffff ? value : null;
    }

    bool flag(String key) => json[key] == true;
    final background = json['customBackground'];
    final rawDock = json['dockItems'];
    final dockItems = rawDock is List
        ? <SidebarDockItem>{
            for (final name in rawDock)
              for (final item in SidebarDockItem.values)
                if (item.name == name) item,
          }.toList()
        : defaultDockItems;
    return SidebarAppearanceSettings(
      backgroundMode: enumValue(
        SidebarBackgroundMode.values,
        'backgroundMode',
        SidebarBackgroundMode.sameAsChat,
      ),
      customBackground:
          background is Map && background.keys.every((key) => key is String)
          ? ChatBackgroundSettings.fromJson(
              Map<String, dynamic>.from(background),
            )
          : const ChatBackgroundSettings(),
      maskStrength: bounded('maskStrength', 1, 0, 2),
      blur: bounded('blur', 0, 0, 30),
      opacity: bounded('opacity', 1, 0, 1),
      phoneWidthPercent: bounded(
        'phoneWidthPercent',
        80,
        minPhoneWidthPercent,
        maxPhoneWidthPercent,
      ),
      wideWidthPercent: bounded(
        'wideWidthPercent',
        30,
        minWideWidthPercent,
        maxWideWidthPercent,
      ),
      density: enumValue(
        SidebarDensity.values,
        'density',
        SidebarDensity.normal,
      ),
      cardRadius: bounded('cardRadius', 14, 0, 32),
      cardColor: color('cardColor'),
      activeCardColor: color('activeCardColor'),
      showTimestamp: flag('showTimestamp'),
      showAssistant: flag('showAssistant'),
      showModel: flag('showModel'),
      showPreview: flag('showPreview'),
      grouping: enumValue(
        SidebarGrouping.values,
        'grouping',
        SidebarGrouping.date,
      ),
      dockItems: List<SidebarDockItem>.unmodifiable(dockItems),
    );
  }

  Map<String, dynamic> toJson() => {
    'backgroundMode': backgroundMode.name,
    'customBackground': customBackground.toJson(),
    'maskStrength': maskStrength,
    'blur': blur,
    'opacity': opacity,
    'phoneWidthPercent': phoneWidthPercent,
    'wideWidthPercent': wideWidthPercent,
    'density': density.name,
    'cardRadius': cardRadius,
    if (cardColor != null) 'cardColor': cardColor,
    if (activeCardColor != null) 'activeCardColor': activeCardColor,
    'showTimestamp': showTimestamp,
    'showAssistant': showAssistant,
    'showModel': showModel,
    'showPreview': showPreview,
    'grouping': grouping.name,
    'dockItems': [for (final item in dockItems) item.name],
  };

  SidebarAppearanceSettings copyWith({
    SidebarBackgroundMode? backgroundMode,
    ChatBackgroundSettings? customBackground,
    double? maskStrength,
    double? blur,
    double? opacity,
    double? phoneWidthPercent,
    double? wideWidthPercent,
    SidebarDensity? density,
    double? cardRadius,
    int? cardColor,
    bool clearCardColor = false,
    int? activeCardColor,
    bool clearActiveCardColor = false,
    bool? showTimestamp,
    bool? showAssistant,
    bool? showModel,
    bool? showPreview,
    SidebarGrouping? grouping,
    List<SidebarDockItem>? dockItems,
  }) => SidebarAppearanceSettings.fromJson({
    'backgroundMode': (backgroundMode ?? this.backgroundMode).name,
    'customBackground': (customBackground ?? this.customBackground).toJson(),
    'maskStrength': maskStrength ?? this.maskStrength,
    'blur': blur ?? this.blur,
    'opacity': opacity ?? this.opacity,
    'phoneWidthPercent': phoneWidthPercent ?? this.phoneWidthPercent,
    'wideWidthPercent': wideWidthPercent ?? this.wideWidthPercent,
    'density': (density ?? this.density).name,
    'cardRadius': cardRadius ?? this.cardRadius,
    'cardColor': clearCardColor ? null : cardColor ?? this.cardColor,
    'activeCardColor': clearActiveCardColor
        ? null
        : activeCardColor ?? this.activeCardColor,
    'showTimestamp': showTimestamp ?? this.showTimestamp,
    'showAssistant': showAssistant ?? this.showAssistant,
    'showModel': showModel ?? this.showModel,
    'showPreview': showPreview ?? this.showPreview,
    'grouping': (grouping ?? this.grouping).name,
    'dockItems': [for (final item in dockItems ?? this.dockItems) item.name],
  });

  @override
  bool operator ==(Object other) =>
      other is SidebarAppearanceSettings &&
      backgroundMode == other.backgroundMode &&
      customBackground == other.customBackground &&
      maskStrength == other.maskStrength &&
      blur == other.blur &&
      opacity == other.opacity &&
      phoneWidthPercent == other.phoneWidthPercent &&
      wideWidthPercent == other.wideWidthPercent &&
      density == other.density &&
      cardRadius == other.cardRadius &&
      cardColor == other.cardColor &&
      activeCardColor == other.activeCardColor &&
      showTimestamp == other.showTimestamp &&
      showAssistant == other.showAssistant &&
      showModel == other.showModel &&
      showPreview == other.showPreview &&
      grouping == other.grouping &&
      listEquals(dockItems, other.dockItems);

  @override
  int get hashCode => Object.hash(
    backgroundMode,
    customBackground,
    maskStrength,
    blur,
    opacity,
    phoneWidthPercent,
    wideWidthPercent,
    density,
    cardRadius,
    cardColor,
    activeCardColor,
    showTimestamp,
    showAssistant,
    showModel,
    showPreview,
    grouping,
    Object.hashAll(dockItems),
  );
}
