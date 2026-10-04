import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/models/sidebar_appearance.dart';
import '../../../core/models/sidebar_shortcut.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../home/widgets/sidebar_bottom_bar.dart';
import 'background_appearance_editor.dart';
import 'custom_theme_widgets.dart';
import 'settings_search_target.dart';
import 'sidebar_appearance_preview.dart';

class SidebarAppearanceEditor extends StatelessWidget {
  const SidebarAppearanceEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onCommit,
    required this.onSelectSource,
    required this.onPickMedia,
    required this.showThumbnails,
    required this.onThumbnailsChanged,
    required this.shortcuts,
    required this.onShortcutsChanged,
    this.importing = false,
    this.error,
  });

  final SidebarAppearanceSettings value;
  final ValueChanged<SidebarAppearanceSettings> onChanged;
  final VoidCallback onCommit;
  final ValueChanged<ChatBackgroundType> onSelectSource;
  final ValueChanged<ChatBackgroundType> onPickMedia;
  final bool showThumbnails;
  final ValueChanged<bool> onThumbnailsChanged;
  final List<SidebarShortcut> shortcuts;
  final ValueChanged<List<SidebarShortcut>> onShortcutsChanged;
  final bool importing;
  final String? error;

  void _save(SidebarAppearanceSettings next) {
    if (importing) return;
    onChanged(next);
    onCommit();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final dock = [
      ...value.dockItems,
      for (final item in SidebarDockItem.values)
        if (!value.dockItems.contains(item)) item,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _target(
          context,
          l.appearanceSidebarBackground,
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.appearanceSidebarBackground,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final mode in SidebarBackgroundMode.values)
                      ChoiceChip(
                        key: ValueKey('appearanceSidebarMode.${mode.name}'),
                        label: Text(switch (mode) {
                          SidebarBackgroundMode.sameAsChat =>
                            l.appearanceSidebarSameAsChat,
                          SidebarBackgroundMode.custom =>
                            l.appearanceSidebarCustomBackground,
                          SidebarBackgroundMode.theme =>
                            l.appearanceSidebarThemeBackground,
                        }),
                        selected: value.backgroundMode == mode,
                        onSelected: importing
                            ? null
                            : (_) =>
                                  _save(value.copyWith(backgroundMode: mode)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (value.backgroundMode == SidebarBackgroundMode.custom) ...[
          const SizedBox(height: 12),
          BackgroundAppearanceEditor(
            keyPrefix: 'appearanceSidebar',
            title: l.appearanceSidebarCustomBackground,
            configuration: value.customBackground,
            onChanged: (background) =>
                onChanged(value.copyWith(customBackground: background)),
            onCommit: onCommit,
            onSelectSource: onSelectSource,
            onPickMedia: onPickMedia,
            importing: importing,
            error: error,
            includeMaskAndBlur: false,
            includeNone: false,
          ),
        ],
        if (error != null &&
            value.backgroundMode != SidebarBackgroundMode.custom)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: TextStyle(color: cs.error)),
          ),
        const SizedBox(height: 12),
        SectionCard(
          children: [
            _slider(
              'Mask',
              l.appearanceSidebarMask,
              value.maskStrength,
              2,
              (next) => value.copyWith(maskStrength: next),
              percentage: true,
            ),
            _slider(
              'Blur',
              l.appearanceSidebarBlur,
              value.blur,
              30,
              (next) => value.copyWith(blur: next),
            ),
            _slider(
              'Opacity',
              l.appearanceSidebarOpacity,
              value.opacity,
              1,
              (next) => value.copyWith(opacity: next),
              percentage: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          children: [
            _slider(
              'PhoneWidth',
              l.appearanceSidebarPhoneWidth,
              value.phoneWidthPercent,
              95,
              (next) => value.copyWith(phoneWidthPercent: next),
              min: 60,
              suffix: '%',
            ),
            _slider(
              'WideWidth',
              l.appearanceSidebarWideWidth,
              value.wideWidthPercent,
              45,
              (next) => value.copyWith(wideWidthPercent: next),
              min: 20,
              suffix: '%',
            ),
            _choiceRow<SidebarDensity>(
              context,
              key: 'appearanceSidebarDensity',
              label: l.appearanceSidebarDensity,
              selected: value.density,
              choices: SidebarDensity.values,
              title: (density) => switch (density) {
                SidebarDensity.compact => l.appearanceSidebarCompact,
                SidebarDensity.normal => l.appearanceSidebarNormal,
                SidebarDensity.spacious => l.appearanceSidebarSpacious,
              },
              onSelected: (density) => _save(value.copyWith(density: density)),
            ),
            _slider(
              'CardRadius',
              l.appearanceSidebarCardRadius,
              value.cardRadius,
              32,
              (next) => value.copyWith(cardRadius: next),
            ),
            _colorRow(
              context,
              l.appearanceSidebarCardColor,
              value.cardColor,
              initial: cs.surfaceContainer,
              onPicked: (color) =>
                  _save(value.copyWith(cardColor: color.toARGB32())),
              onReset: () => _save(value.copyWith(clearCardColor: true)),
              key: 'appearanceSidebarCardColor',
            ),
            _colorRow(
              context,
              l.appearanceSidebarActiveCardColor,
              value.activeCardColor,
              initial: cs.primaryContainer,
              onPicked: (color) =>
                  _save(value.copyWith(activeCardColor: color.toARGB32())),
              onReset: () => _save(value.copyWith(clearActiveCardColor: true)),
              key: 'appearanceSidebarActiveCardColor',
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          children: [
            _switch(
              context,
              'appearanceSidebarThumbnails',
              l.displaySettingsPageSidebarThumbnailsTitle,
              showThumbnails,
              onThumbnailsChanged,
            ),
            _switch(
              context,
              'appearanceSidebarTimestamp',
              l.appearanceSidebarTimestamp,
              value.showTimestamp,
              (next) => _save(value.copyWith(showTimestamp: next)),
            ),
            _switch(
              context,
              'appearanceSidebarAssistant',
              l.appearanceSidebarAssistant,
              value.showAssistant,
              (next) => _save(value.copyWith(showAssistant: next)),
            ),
            _switch(
              context,
              'appearanceSidebarModel',
              l.appearanceSidebarModel,
              value.showModel,
              (next) => _save(value.copyWith(showModel: next)),
            ),
            _switch(
              context,
              'appearanceSidebarLastPreview',
              l.appearanceSidebarLastPreview,
              value.showPreview,
              (next) => _save(value.copyWith(showPreview: next)),
            ),
            _choiceRow<SidebarGrouping>(
              context,
              key: 'appearanceSidebarGrouping',
              label: l.appearanceSidebarGrouping,
              selected: value.grouping,
              choices: SidebarGrouping.values,
              title: (grouping) => switch (grouping) {
                SidebarGrouping.date => l.appearanceSidebarGroupingDate,
                SidebarGrouping.assistant =>
                  l.appearanceSidebarGroupingAssistant,
                SidebarGrouping.none => l.appearanceSidebarGroupingNone,
              },
              onSelected: (grouping) =>
                  _save(value.copyWith(grouping: grouping)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _target(
          context,
          l.appearanceSidebarDock,
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.appearanceSidebarDock,
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.appearanceSidebarDockHint,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ReorderableListView.builder(
                  key: const ValueKey('appearanceSidebarDockOrder'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: dock.length,
                  onReorderItem: (oldIndex, newIndex) {
                    if (importing) return;
                    final ordered = [...dock];
                    ordered.insert(newIndex, ordered.removeAt(oldIndex));
                    _save(
                      value.copyWith(
                        dockItems: [
                          for (final item in ordered)
                            if (value.dockItems.contains(item)) item,
                        ],
                      ),
                    );
                  },
                  itemBuilder: (context, index) {
                    final item = dock[index];
                    return IosSwitchRow(
                      key: ValueKey('appearanceSidebarDock.${item.name}'),
                      icon: sidebarDockIcon(item),
                      label: sidebarDockLabel(l, item),
                      value: value.dockItems.contains(item),
                      labelTrailing: _dragHandle(index, enabled: !importing),
                      onChanged: (show) => _save(
                        value.copyWith(
                          dockItems: show
                              ? [...value.dockItems, item]
                              : [
                                  for (final current in value.dockItems)
                                    if (current != item) current,
                                ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _target(
          context,
          l.sideDrawerShortcutsTitle,
          SectionCard(
            child: Column(
              children: [
                IosNavRow(
                  key: const ValueKey('appearanceSidebarShortcutPicker'),
                  icon: LucideIcons.layoutGrid,
                  label: l.sideDrawerShortcutsTitle,
                  subtitle: l.appearanceSidebarShortcutsHint,
                  subtitleMaxLines: null,
                  onTap: importing
                      ? null
                      : () => unawaited(showSidebarShortcutPicker(context)),
                ),
                if (shortcuts.isNotEmpty)
                  ReorderableListView.builder(
                    key: const ValueKey('appearanceSidebarShortcutOrder'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: shortcuts.length,
                    onReorderItem: (oldIndex, newIndex) {
                      if (importing) return;
                      final ordered = [...shortcuts];
                      ordered.insert(newIndex, ordered.removeAt(oldIndex));
                      onShortcutsChanged(ordered);
                    },
                    itemBuilder: (context, index) => IosNavRow(
                      key: ValueKey(
                        'appearanceSidebarShortcut.${shortcuts[index].encode()}',
                      ),
                      icon: shortcuts[index].web
                          ? LucideIcons.globe
                          : LucideIcons.layoutGrid,
                      label: sidebarShortcutPreviewLabel(l, shortcuts[index]),
                      trailing: _dragHandle(index, enabled: !importing),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _slider(
    String key,
    String label,
    double current,
    double max,
    SidebarAppearanceSettings Function(double) change, {
    double min = 0,
    bool percentage = false,
    String suffix = '',
  }) => AppearanceSlider(
    sliderKey: ValueKey('appearanceSidebar$key'),
    label: label,
    value: current,
    min: min,
    max: max,
    step: percentage ? .01 : 1,
    valueLabel: percentage
        ? '${(current * 100).round()}%'
        : '${current.round()}$suffix',
    enabled: !importing,
    onChanged: (next) => onChanged(change(next)),
    onChangeEnd: onCommit,
  );

  Widget _switch(
    BuildContext context,
    String key,
    String label,
    bool current,
    ValueChanged<bool> change,
  ) => _target(
    context,
    label,
    IosSwitchRow(
      key: ValueKey(key),
      label: label,
      value: current,
      onChanged: (next) {
        if (!importing) change(next);
      },
    ),
  );

  Widget _choiceRow<T>(
    BuildContext context, {
    required String key,
    required String label,
    required T selected,
    required List<T> choices,
    required String Function(T) title,
    required ValueChanged<T> onSelected,
  }) => _target(
    context,
    label,
    Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final choice in choices)
                ChoiceChip(
                  key: ValueKey('$key.${(choice as Enum).name}'),
                  label: Text(title(choice)),
                  selected: selected == choice,
                  onSelected: importing ? null : (_) => onSelected(choice),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _colorRow(
    BuildContext context,
    String label,
    int? argb, {
    required Color initial,
    required ValueChanged<Color> onPicked,
    required VoidCallback onReset,
    required String key,
  }) => _target(
    context,
    label,
    IosNavRow(
      key: ValueKey(key),
      label: label,
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: argb == null ? initial : Color(argb),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      trailing: argb == null
          ? null
          : IosIconButton(
              icon: LucideIcons.rotateCcw,
              minSize: 48,
              tooltip: AppLocalizations.of(
                context,
              )!.appearanceSidebarResetColor,
              semanticLabel: AppLocalizations.of(
                context,
              )!.appearanceSidebarResetColor,
              enabled: !importing,
              onTap: onReset,
            ),
      onTap: importing
          ? null
          : () async {
              final color = await showAppColorPicker(
                context,
                title: label,
                initial: argb == null ? initial : Color(argb),
              );
              if (context.mounted && color != null) onPicked(color);
            },
    ),
  );

  Widget _dragHandle(int index, {required bool enabled}) =>
      ReorderableDragStartListener(
        index: index,
        enabled: enabled,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(LucideIcons.gripVertical, size: 18),
        ),
      );

  Widget _target(BuildContext context, String label, Widget child) =>
      SettingsSearchTarget.wrap(context, label, child);
}
