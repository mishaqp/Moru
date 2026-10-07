import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';
import 'settings_search_target.dart';

/// Shared controls for the chat wallpaper and a custom sidebar wallpaper.
/// The owner keeps its draft and imports media through SettingsProvider.
class BackgroundAppearanceEditor extends StatelessWidget {
  const BackgroundAppearanceEditor({
    super.key,
    required this.configuration,
    required this.onChanged,
    required this.onCommit,
    required this.onSelectSource,
    required this.onPickMedia,
    this.keyPrefix = 'appearance',
    this.title,
    this.importing = false,
    this.error,
    this.includeMaskAndBlur = true,
    this.includeNone = true,
  });

  final ChatBackgroundSettings configuration;
  final ValueChanged<ChatBackgroundSettings> onChanged;
  final VoidCallback onCommit;
  final ValueChanged<ChatBackgroundType> onSelectSource;
  final ValueChanged<ChatBackgroundType> onPickMedia;
  final String keyPrefix;
  final String? title;
  final bool importing;
  final String? error;
  final bool includeMaskAndBlur;
  final bool includeNone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final background = configuration;
    final media = backgroundHasMedia(background);
    final label = title ?? l.appearanceBackground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSearchTarget.wrap(
          context,
          label,
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final type in ChatBackgroundType.values)
                      if (includeNone || type != ChatBackgroundType.none)
                        ChoiceChip(
                          key: ValueKey('${keyPrefix}Source.${type.name}'),
                          label: Text(backgroundSourceLabel(l, type)),
                          selected: background.type == type,
                          onSelected: importing
                              ? null
                              : (_) => onSelectSource(type),
                        ),
                  ],
                ),
                if (importing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (media) ...[
                  const SizedBox(height: 8),
                  IosNavRow(
                    icon: LucideIcons.folderOpen,
                    label: background.path == null
                        ? l.appearanceChooseMedia
                        : l.appearanceReplaceMedia,
                    subtitle: background.path == null
                        ? null
                        : p.basename(background.path!),
                    onTap: importing
                        ? null
                        : () => onPickMedia(background.type),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
        if (media) ...[
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.appearanceFit, style: const TextStyle(fontSize: 15)),
                DropdownButton<ChatBackgroundFit>(
                  key: ValueKey('${keyPrefix}Fit'),
                  isExpanded: true,
                  value: background.fit,
                  icon: const Icon(LucideIcons.chevronDown, size: 18),
                  items: [
                    for (final fit in ChatBackgroundFit.values)
                      if (fit != ChatBackgroundFit.tile ||
                          background.type != ChatBackgroundType.video)
                        DropdownMenuItem(
                          value: fit,
                          child: Text(backgroundFitLabel(l, fit)),
                        ),
                  ],
                  onChanged: importing
                      ? null
                      : (value) {
                          if (value == null) return;
                          onChanged(configuration.copyWith(fit: value));
                          onCommit();
                        },
                ),
              ],
            ),
          ),
        ],
        if (backgroundIsPositioned(background)) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: IosNavRow(
              key: ValueKey('${keyPrefix}Center'),
              icon: LucideIcons.scan,
              label: l.appearanceCenterFocus,
              subtitle: l.appearanceFocusHint,
              subtitleMaxLines: null,
              onTap: importing
                  ? null
                  : () {
                      onChanged(
                        configuration.copyWith(
                          focusX: 0,
                          focusY: 0,
                          gradientOffsetX: 0,
                          gradientOffsetY: 0,
                        ),
                      );
                      onCommit();
                    },
            ),
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          children: [
            if (includeMaskAndBlur) ...[
              _slider(
                '${keyPrefix}Mask',
                l.displaySettingsPageChatBackgroundMaskTitle,
                background.maskStrength,
                2,
                (value) => configuration.copyWith(maskStrength: value),
              ),
              _slider(
                '${keyPrefix}Blur',
                l.messageStyleSettingsPageBlur,
                background.blur,
                30,
                (value) => configuration.copyWith(blur: value),
                percentage: false,
              ),
            ],
            _slider(
              '${keyPrefix}Brightness',
              l.appearanceBrightness,
              background.brightness,
              2,
              (value) => configuration.copyWith(brightness: value),
            ),
            _slider(
              '${keyPrefix}Saturation',
              l.appearanceSaturation,
              background.saturation,
              2,
              (value) => configuration.copyWith(saturation: value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _slider(
    String key,
    String label,
    double value,
    double max,
    ChatBackgroundSettings Function(double) change, {
    bool percentage = true,
  }) => AppearanceSlider(
    key: ValueKey('$key.row'),
    sliderKey: ValueKey(key),
    label: label,
    value: value,
    max: max,
    step: percentage ? .01 : 1,
    valueLabel: percentage ? '${(value * 100).round()}%' : '${value.round()}',
    enabled: !importing,
    onChanged: (value) => onChanged(change(value)),
    onChangeEnd: onCommit,
  );
}

class AppearanceSlider extends StatelessWidget {
  const AppearanceSlider({
    super.key,
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = 0,
    this.step = 1,
    this.enabled = true,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String valueLabel;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsSearchTarget.wrap(
      context,
      label,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Text(
                  valueLabel,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            SfSliderTheme(
              data: SfSliderThemeData(
                activeTrackHeight: 6,
                inactiveTrackHeight: 6,
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                thumbColor: cs.primary,
              ),
              child: SfSlider(
                key: sliderKey,
                value: value,
                min: min,
                max: max,
                stepSize: step,
                onChanged: enabled
                    ? (dynamic value) => onChanged(value as double)
                    : null,
                onChangeEnd: enabled ? (_) => onChangeEnd() : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BackgroundPositioningPreview extends StatelessWidget {
  const BackgroundPositioningPreview({
    super.key,
    required this.configuration,
    required this.height,
    required this.onChanged,
    required this.onCommit,
    required this.child,
    this.enabled = true,
    this.currentConfiguration,
  });

  final ChatBackgroundSettings configuration;
  final double height;
  final ValueChanged<ChatBackgroundSettings> onChanged;
  final VoidCallback onCommit;
  final Widget child;
  final bool enabled;
  final ChatBackgroundSettings Function()? currentConfiguration;

  @override
  Widget build(BuildContext context) {
    final positioned = enabled && backgroundIsPositioned(configuration);
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: !positioned
            ? null
            : (details) {
                final dx = details.delta.dx * 2 / constraints.maxWidth;
                final dy = details.delta.dy * 2 / height;
                final current = currentConfiguration?.call() ?? configuration;
                final direction = current.fit == ChatBackgroundFit.cover
                    ? -1
                    : 1;
                onChanged(
                  current.type == ChatBackgroundType.gradient
                      ? current.copyWith(
                          gradientOffsetX: current.gradientOffsetX + dx,
                          gradientOffsetY: current.gradientOffsetY + dy,
                        )
                      : current.copyWith(
                          focusX: (current.focusX + dx * direction).clamp(
                            -1.0,
                            1.0,
                          ),
                          focusY: (current.focusY + dy * direction).clamp(
                            -1.0,
                            1.0,
                          ),
                        ),
                );
              },
        onPanEnd: !positioned ? null : (_) => onCommit(),
        onPanCancel: !positioned ? null : onCommit,
        child: child,
      ),
    );
  }
}

bool backgroundHasMedia(ChatBackgroundSettings background) =>
    switch (background.type) {
      ChatBackgroundType.image ||
      ChatBackgroundType.gif ||
      ChatBackgroundType.video => true,
      _ => false,
    };

bool backgroundIsPositioned(ChatBackgroundSettings background) =>
    background.type == ChatBackgroundType.gradient ||
    (backgroundHasMedia(background) &&
        (background.fit == ChatBackgroundFit.cover ||
            background.fit == ChatBackgroundFit.contain));

String backgroundSourceLabel(AppLocalizations l, ChatBackgroundType type) =>
    switch (type) {
      ChatBackgroundType.none => l.appearanceNone,
      ChatBackgroundType.image => l.appearancePhoto,
      ChatBackgroundType.gif => l.appearanceGif,
      ChatBackgroundType.video => l.appearanceVideo,
      ChatBackgroundType.gradient => l.appearanceAnimatedGradient,
    };

String backgroundFitLabel(AppLocalizations l, ChatBackgroundFit fit) =>
    switch (fit) {
      ChatBackgroundFit.cover => l.appearanceFitCover,
      ChatBackgroundFit.contain => l.appearanceFitContain,
      ChatBackgroundFit.fill => l.appearanceFitFill,
      ChatBackgroundFit.tile => l.appearanceFitTile,
    };
