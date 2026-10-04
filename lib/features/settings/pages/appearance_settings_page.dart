import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/segmented_tabs.dart';
import '../../../theme/custom_theme.dart';
import '../../../theme/palettes.dart';
import '../../../theme/theme_factory.dart';
import '../../chat/widgets/chat_background.dart';
import '../widgets/settings_search_target.dart';
import 'message_style_settings_page.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  late ChatAppearanceSettings _saved;
  late ChatAppearanceSettings _draft;
  bool _dirty = false;
  bool _importing = false;
  bool _editingDark = false;
  int _tab = 0;
  String? _error;
  Object? _themeKey;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  Brightness get _brightness =>
      _editingDark ? Brightness.dark : Brightness.light;

  ChatBackgroundSettings get _background => _draft.backgroundFor(_brightness);

  @override
  void initState() {
    super.initState();
    _saved = context.read<SettingsProvider>().chatAppearance;
    _draft = _saved;
  }

  void _changeBackground(ChatBackgroundSettings value) {
    setState(() {
      _draft = _draft.shared
          ? _draft.copyWith(light: value, dark: value)
          : _editingDark
          ? _draft.copyWith(dark: value)
          : _draft.copyWith(light: value);
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _commit() async {
    if (!_dirty) return;
    final value = _draft;
    _saved = value;
    _dirty = false;
    try {
      await context.read<SettingsProvider>().setChatAppearance(value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.appearanceMediaError,
        );
      }
    }
  }

  void _selectSource(ChatBackgroundType type) {
    if (_importing) return;
    if (type == ChatBackgroundType.image ||
        type == ChatBackgroundType.gif ||
        type == ChatBackgroundType.video) {
      unawaited(_pickMedia(type));
      return;
    }
    _changeBackground(
      _background.copyWith(type: type, clearPath: true, gradientAnimated: true),
    );
    unawaited(_commit());
  }

  Future<void> _pickMedia(ChatBackgroundType type) async {
    if (_importing) return;
    final settings = context.read<SettingsProvider>();
    final brightness = _brightness;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      await _commit();
      if (!mounted) return;
      String? path;
      if (type == ChatBackgroundType.gif) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['gif'],
        );
        path = result?.files.single.path;
      } else if (type == ChatBackgroundType.video) {
        path = (await ImagePicker().pickVideo(
          source: ImageSource.gallery,
        ))?.path;
      } else {
        path = (await ImagePicker().pickImage(
          source: ImageSource.gallery,
        ))?.path;
      }
      if (path == null || !mounted) return;
      final ok = await settings.importChatBackground(
        path,
        type,
        brightness: brightness,
      );
      if (!mounted) return;
      setState(() {
        _saved = settings.chatAppearance;
        _draft = _saved;
        if (!ok) _error = AppLocalizations.of(context)!.appearanceMediaError;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.appearanceMediaError,
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _reset() {
    if (_importing) return;
    setState(() {
      _draft = const ChatAppearanceSettings();
      _dirty = true;
      _error = null;
    });
    unawaited(_commit());
  }

  ThemeData _previewTheme(BuildContext context, SettingsProvider settings) {
    final current = Theme.of(context);
    final custom = settings.selectedCustomTheme;
    final key = (
      current,
      settings.themePaletteId,
      custom,
      settings.usePureBackground,
      settings.useLayeredSurfaces,
    );
    if (_themeKey != key) {
      final palette =
          settings.themePaletteId == ThemePalettes.customPaletteId &&
              custom != null
          ? buildCustomThemePalette(custom)
          : ThemePalettes.byId(settings.themePaletteId);
      _lightTheme = current.brightness == Brightness.light
          ? current
          : buildLightThemeForScheme(
              palette.light,
              pureBackground: settings.usePureBackground,
              layeredSurfaces: settings.useLayeredSurfaces,
            );
      _darkTheme = current.brightness == Brightness.dark
          ? current
          : buildDarkThemeForScheme(
              palette.dark,
              pureBackground: settings.usePureBackground,
              layeredSurfaces: settings.useLayeredSurfaces,
            );
      _themeKey = key;
    }
    return _editingDark ? _darkTheme! : _lightTheme!;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final saved = context.select<SettingsProvider, ChatAppearanceSettings>(
      (s) => s.chatAppearance,
    );
    context.select<SettingsProvider, Object>(
      (s) => (
        s.selectedCustomTheme,
        s.themePaletteId,
        s.usePureBackground,
        s.useLayeredSurfaces,
      ),
    );
    if (saved != _saved) {
      _saved = saved;
      if (!_dirty) _draft = saved;
    }
    final background = _background;
    final media = switch (background.type) {
      ChatBackgroundType.image ||
      ChatBackgroundType.gif ||
      ChatBackgroundType.video => true,
      _ => false,
    };
    final positioned =
        background.type == ChatBackgroundType.gradient ||
        (media &&
            (background.fit == ChatBackgroundFit.cover ||
                background.fit == ChatBackgroundFit.contain));
    final previewTheme = _previewTheme(
      context,
      context.read<SettingsProvider>(),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Scaffold(
      appBar: AppBar(
        leading: IosIconButton(
          icon: LucideIcons.arrowLeft,
          minSize: 48,
          tooltip: l.settingsPageBackButton,
          semanticLabel: l.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l.appearanceSettingsPageTitle),
        actions: [
          IosIconButton(
            key: const ValueKey('appearanceReset'),
            icon: LucideIcons.rotateCcw,
            minSize: 48,
            tooltip: l.appearanceReset,
            semanticLabel: l.appearanceReset,
            enabled: !_importing,
            onTap: _reset,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      key: const ValueKey('appearancePreview'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: !positioned || _importing
                          ? null
                          : (details) {
                              final dx =
                                  details.delta.dx * 2 / constraints.maxWidth;
                              final dy =
                                  details.delta.dy * 2 / (240 * textScale);
                              final value = _background;
                              final focusDirection =
                                  value.fit == ChatBackgroundFit.cover ? -1 : 1;
                              _changeBackground(
                                value.type == ChatBackgroundType.gradient
                                    ? value.copyWith(
                                        gradientOffsetX:
                                            value.gradientOffsetX + dx,
                                        gradientOffsetY:
                                            value.gradientOffsetY + dy,
                                      )
                                    : value.copyWith(
                                        focusX:
                                            (value.focusX + dx * focusDirection)
                                                .clamp(-1.0, 1.0),
                                        focusY:
                                            (value.focusY + dy * focusDirection)
                                                .clamp(-1.0, 1.0),
                                      ),
                              );
                            },
                      onPanEnd: !positioned || _importing
                          ? null
                          : (_) => unawaited(_commit()),
                      onPanCancel: !positioned || _importing
                          ? null
                          : () => unawaited(_commit()),
                      child: MessageStylePreview(
                        theme: previewTheme,
                        height: 240 * textScale,
                        backgroundConfiguration: background,
                        backdrop: ChatBackground(
                          configuration: background,
                          includeSurfaceFill: true,
                          active: _tab == 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedTabs(
                    height: 48,
                    tabs: [
                      SegmentedTab(
                        label: l.appearanceChatWindow,
                        icon: LucideIcons.messageSquare,
                      ),
                      SegmentedTab(
                        label: l.appearanceSidebar,
                        icon: LucideIcons.panelLeft,
                      ),
                    ],
                    index: _tab,
                    onChanged: _importing
                        ? (_) {}
                        : (value) => setState(() => _tab = value),
                  ),
                  const SizedBox(height: 12),
                  if (_tab == 1)
                    SectionCard(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l.appearanceSidebarComingSoon,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    )
                  else ...[
                    SettingsSearchTarget.wrap(
                      context,
                      l.appearanceSameBackground,
                      SectionCard(
                        child: IosSwitchRow(
                          key: const ValueKey('appearanceShared'),
                          label: l.appearanceSameBackground,
                          subtitle: l.appearanceSameBackgroundHint,
                          value: _draft.shared,
                          onChanged: (value) {
                            if (_importing) return;
                            setState(() {
                              _draft = _draft.copyWith(shared: value);
                              _dirty = true;
                            });
                            unawaited(_commit());
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedTabs(
                      key: const ValueKey('appearanceBrightnessMode'),
                      height: 48,
                      tabs: [
                        SegmentedTab(
                          label: l.messageStyleSettingsPageLight,
                          icon: LucideIcons.sun,
                        ),
                        SegmentedTab(
                          label: l.messageStyleSettingsPageDark,
                          icon: LucideIcons.moon,
                        ),
                      ],
                      index: _editingDark ? 1 : 0,
                      onChanged: (value) {
                        if (_importing) return;
                        unawaited(_commit());
                        setState(() => _editingDark = value == 1);
                      },
                    ),
                    const SizedBox(height: 12),
                    SettingsSearchTarget.wrap(
                      context,
                      l.appearanceBackground,
                      SectionCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.appearanceBackground,
                              style: const TextStyle(fontSize: 15),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final type in ChatBackgroundType.values)
                                  ChoiceChip(
                                    key: ValueKey(
                                      'appearanceSource.${type.name}',
                                    ),
                                    label: Text(_sourceLabel(l, type)),
                                    selected: background.type == type,
                                    onSelected: _importing
                                        ? null
                                        : (_) => _selectSource(type),
                                  ),
                              ],
                            ),
                            if (_importing) ...[
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
                                onTap: _importing
                                    ? null
                                    : () => unawaited(
                                        _pickMedia(background.type),
                                      ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(_error!, style: TextStyle(color: cs.error)),
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
                            Text(
                              l.appearanceFit,
                              style: const TextStyle(fontSize: 15),
                            ),
                            DropdownButton<ChatBackgroundFit>(
                              key: const ValueKey('appearanceFit'),
                              isExpanded: true,
                              value: background.fit,
                              icon: const Icon(
                                LucideIcons.chevronDown,
                                size: 18,
                              ),
                              items: [
                                for (final fit in ChatBackgroundFit.values)
                                  if (fit != ChatBackgroundFit.tile ||
                                      background.type !=
                                          ChatBackgroundType.video)
                                    DropdownMenuItem(
                                      value: fit,
                                      child: Text(_fitLabel(l, fit)),
                                    ),
                              ],
                              onChanged: _importing
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      _changeBackground(
                                        _background.copyWith(fit: value),
                                      );
                                      unawaited(_commit());
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (positioned) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        child: IosNavRow(
                          key: const ValueKey('appearanceCenter'),
                          icon: LucideIcons.scan,
                          label: l.appearanceCenterFocus,
                          subtitle: l.appearanceFocusHint,
                          subtitleMaxLines: null,
                          onTap: _importing
                              ? null
                              : () {
                                  _changeBackground(
                                    _background.copyWith(
                                      focusX: 0,
                                      focusY: 0,
                                      gradientOffsetX: 0,
                                      gradientOffsetY: 0,
                                    ),
                                  );
                                  unawaited(_commit());
                                },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SectionCard(
                      children: [
                        _slider(
                          'appearanceMask',
                          l.displaySettingsPageChatBackgroundMaskTitle,
                          background.maskStrength,
                          2,
                          (v) => _background.copyWith(maskStrength: v),
                        ),
                        _slider(
                          'appearanceBlur',
                          l.messageStyleSettingsPageBlur,
                          background.blur,
                          30,
                          (v) => _background.copyWith(blur: v),
                          percentage: false,
                        ),
                        _slider(
                          'appearanceBrightness',
                          l.appearanceBrightness,
                          background.brightness,
                          2,
                          (v) => _background.copyWith(brightness: v),
                        ),
                        _slider(
                          'appearanceSaturation',
                          l.appearanceSaturation,
                          background.saturation,
                          2,
                          (v) => _background.copyWith(saturation: v),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(
    String key,
    String label,
    double value,
    double max,
    ChatBackgroundSettings Function(double) change, {
    bool percentage = true,
  }) {
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
                  percentage
                      ? '${(value * 100).round()}%'
                      : value.round().toString(),
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
                key: ValueKey(key),
                value: value,
                min: 0.0,
                max: max,
                stepSize: percentage ? .01 : 1,
                onChanged: _importing
                    ? null
                    : (dynamic v) => _changeBackground(change(v as double)),
                onChangeEnd: _importing ? null : (_) => unawaited(_commit()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceLabel(AppLocalizations l, ChatBackgroundType type) =>
    switch (type) {
      ChatBackgroundType.none => l.appearanceNone,
      ChatBackgroundType.image => l.appearancePhoto,
      ChatBackgroundType.gif => l.appearanceGif,
      ChatBackgroundType.video => l.appearanceVideo,
      ChatBackgroundType.gradient => l.appearanceAnimatedGradient,
    };

String _fitLabel(AppLocalizations l, ChatBackgroundFit fit) => switch (fit) {
  ChatBackgroundFit.cover => l.appearanceFitCover,
  ChatBackgroundFit.contain => l.appearanceFitContain,
  ChatBackgroundFit.fill => l.appearanceFitFill,
  ChatBackgroundFit.tile => l.appearanceFitTile,
};
