import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/models/sidebar_appearance.dart';
import '../../../core/models/sidebar_shortcut.dart';
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
import '../widgets/background_appearance_editor.dart';
import '../widgets/settings_search_target.dart';
import '../widgets/sidebar_appearance_editor.dart';
import '../widgets/sidebar_appearance_preview.dart';
import 'message_style_settings_page.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  late ChatAppearanceSettings _saved;
  late ChatAppearanceSettings _draft;
  late SidebarAppearanceSettings _sidebarSaved;
  late SidebarAppearanceSettings _sidebarDraft;
  bool _dirty = false;
  bool _sidebarDirty = false;
  bool _importing = false;
  bool _editingDark = false;
  bool _initializedBrightness = false;
  late int _tab;
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
    final settings = context.read<SettingsProvider>();
    _saved = settings.chatAppearance;
    _draft = _saved;
    _sidebarSaved = settings.sidebarAppearance;
    _sidebarDraft = _sidebarSaved;
    _tab = widget.initialTab.clamp(0, 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedBrightness) {
      _editingDark = Theme.of(context).brightness == Brightness.dark;
      _initializedBrightness = true;
    }
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

  void _changeSidebar(SidebarAppearanceSettings value) {
    setState(() {
      _sidebarDraft = value;
      _sidebarDirty = true;
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
          () => _error = AppLocalizations.of(context)!.appearanceSaveError,
        );
      }
    }
  }

  Future<void> _commitSidebar() async {
    if (!_sidebarDirty) return;
    final value = _sidebarDraft;
    _sidebarSaved = value;
    _sidebarDirty = false;
    try {
      await context.read<SettingsProvider>().setSidebarAppearance(value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.appearanceSaveError,
        );
      }
    }
  }

  Future<void> _commitCurrent() => _tab == 1 ? _commitSidebar() : _commit();

  void _selectSource(ChatBackgroundType type) {
    if (_importing) return;
    if (type == ChatBackgroundType.image ||
        type == ChatBackgroundType.gif ||
        type == ChatBackgroundType.video) {
      unawaited(_pickMedia(type));
      return;
    }
    if (_tab == 1) {
      _changeSidebar(
        _sidebarDraft.copyWith(
          customBackground: _sidebarDraft.customBackground.copyWith(
            type: type,
            clearPath: true,
            gradientAnimated: true,
          ),
        ),
      );
    } else {
      _changeBackground(
        _background.copyWith(
          type: type,
          clearPath: true,
          gradientAnimated: true,
        ),
      );
    }
    unawaited(_commitCurrent());
  }

  /// Both editors use the existing Android picker and owned-media import path.
  Future<void> _pickMedia(ChatBackgroundType type) async {
    if (_importing) return;
    final settings = context.read<SettingsProvider>();
    final brightness = _brightness;
    final sidebar = _tab == 1;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      await _commitCurrent();
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
      final ok = sidebar
          ? await settings.importSidebarBackground(path, type)
          : await settings.importChatBackground(
              path,
              type,
              brightness: brightness,
            );
      if (!mounted) return;
      setState(() {
        if (sidebar) {
          _sidebarSaved = settings.sidebarAppearance;
          _sidebarDraft = _sidebarSaved;
        } else {
          _saved = settings.chatAppearance;
          _draft = _saved;
        }
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

  Future<void> _reset() async {
    if (_importing) return;
    if (_tab == 1) {
      final before = _sidebarSaved;
      _changeSidebar(const SidebarAppearanceSettings());
      _sidebarSaved = _sidebarDraft;
      _sidebarDirty = false;
      try {
        await context.read<SettingsProvider>().resetSidebarAppearance();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _sidebarDraft = before;
          _sidebarSaved = context.read<SettingsProvider>().sidebarAppearance;
          _sidebarDirty = _sidebarDraft != _sidebarSaved;
          _error = AppLocalizations.of(context)!.appearanceSaveError;
        });
      }
    } else {
      setState(() {
        _draft = const ChatAppearanceSettings();
        _dirty = true;
        _error = null;
      });
      unawaited(_commit());
    }
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
    final saved = context.select<SettingsProvider, ChatAppearanceSettings>(
      (s) => s.chatAppearance,
    );
    final sidebarSaved = context
        .select<SettingsProvider, SidebarAppearanceSettings>(
          (s) => s.sidebarAppearance,
        );
    final thumbnails = context.select<SettingsProvider, bool>(
      (s) => s.sidebarThumbnails,
    );
    final shortcuts = context.select<SettingsProvider, List<SidebarShortcut>>(
      (s) => s.sidebarShortcuts,
    );
    final glass = context.select<SettingsProvider, bool>((s) => s.glassTheme);
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
    if (sidebarSaved != _sidebarSaved) {
      _sidebarSaved = sidebarSaved;
      if (!_sidebarDirty) _sidebarDraft = sidebarSaved;
    }
    final previewTheme = _previewTheme(
      context,
      context.read<SettingsProvider>(),
    );
    final sidebarTheme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final chatHeight =
        ((MediaQuery.sizeOf(context).height -
                    MediaQuery.paddingOf(context).vertical -
                    kToolbarHeight) *
                .32)
            .clamp(100.0, 220.0);
    final sidebarHeight =
        ((MediaQuery.sizeOf(context).height -
                    MediaQuery.paddingOf(context).vertical -
                    kToolbarHeight) *
                .38)
            .clamp(100.0, 300.0);

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
            tooltip: _tab == 1 ? l.appearanceSidebarReset : l.appearanceReset,
            semanticLabel: _tab == 1
                ? l.appearanceSidebarReset
                : l.appearanceReset,
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _tab == 1
                      ? BackgroundPositioningPreview(
                          key: const ValueKey('appearanceSidebarPreview'),
                          configuration: _sidebarDraft.customBackground,
                          currentConfiguration: () =>
                              _sidebarDraft.customBackground,
                          height: sidebarHeight,
                          enabled:
                              !_importing &&
                              _sidebarDraft.backgroundMode ==
                                  SidebarBackgroundMode.custom,
                          onChanged: (background) => _changeSidebar(
                            _sidebarDraft.copyWith(
                              customBackground: background,
                            ),
                          ),
                          onCommit: () => unawaited(_commitSidebar()),
                          child: SidebarAppearancePreview(
                            appearance: _sidebarDraft,
                            backgroundConfiguration: _sidebarDraft
                                .backgroundFor(sidebarTheme.brightness, _draft),
                            theme: sidebarTheme,
                            height: sidebarHeight,
                            showThumbnails: thumbnails,
                            shortcuts: shortcuts,
                            glass: glass,
                          ),
                        )
                      : BackgroundPositioningPreview(
                          key: const ValueKey('appearancePreview'),
                          configuration: _background,
                          currentConfiguration: () => _background,
                          height: chatHeight,
                          enabled: !_importing,
                          onChanged: _changeBackground,
                          onCommit: () => unawaited(_commit()),
                          child: SizedBox(
                            height: chatHeight,
                            child: LayoutBuilder(
                              builder: (context, constraints) => FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  child: MessageStylePreview(
                                    theme: previewTheme,
                                    height: 240 * textScale,
                                    backgroundConfiguration: _background,
                                    backdrop: ChatBackground(
                                      configuration: _background,
                                      includeSurfaceFill: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _tabs(l),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: _tab == 1
                        ? SidebarAppearanceEditor(
                            value: _sidebarDraft,
                            onChanged: _changeSidebar,
                            onCommit: () => unawaited(_commitSidebar()),
                            onSelectSource: _selectSource,
                            onPickMedia: (type) => unawaited(_pickMedia(type)),
                            importing: _importing,
                            error: _error,
                            showThumbnails: thumbnails,
                            onThumbnailsChanged: (value) => unawaited(
                              context
                                  .read<SettingsProvider>()
                                  .setSidebarThumbnails(value),
                            ),
                            shortcuts: shortcuts,
                            onShortcutsChanged: (value) => unawaited(
                              context
                                  .read<SettingsProvider>()
                                  .setSidebarShortcuts(value),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                              BackgroundAppearanceEditor(
                                configuration: _background,
                                onChanged: _changeBackground,
                                onCommit: () => unawaited(_commit()),
                                onSelectSource: _selectSource,
                                onPickMedia: (type) =>
                                    unawaited(_pickMedia(type)),
                                importing: _importing,
                                error: _error,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs(AppLocalizations l) => SegmentedTabs(
    height: 48,
    tabs: [
      SegmentedTab(
        label: l.appearanceChatWindow,
        icon: LucideIcons.messageSquare,
      ),
      SegmentedTab(label: l.appearanceSidebar, icon: LucideIcons.panelLeft),
    ],
    index: _tab,
    onChanged: _importing
        ? (_) {}
        : (value) {
            unawaited(_commitCurrent());
            setState(() {
              _tab = value;
              _error = null;
            });
          },
  );
}
