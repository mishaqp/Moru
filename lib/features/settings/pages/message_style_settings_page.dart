import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../icons/reasoning_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../../theme/chat_bubble_style.dart';
import '../../../theme/custom_theme.dart';
import '../../../theme/palettes.dart';
import '../../../theme/theme_factory.dart';
import '../../chat/widgets/frosted/chat_frosted_backdrop.dart';
import '../../chat/widgets/frosted/frosted_surface.dart';
import '../../home/pages/home_mobile_layout.dart';
import '../widgets/custom_theme_widgets.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';

part 'message_style_rows.dart';
part 'message_style_preview.dart';

class MessageStyleSettingsPage extends StatelessWidget {
  const MessageStyleSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.messageStyleSettingsPageTitle),
        actions: [
          Tooltip(
            message: l10n.messageStyleSettingsPageReset,
            child: IosIconButton(
              icon: Lucide.RotateCcw,
              color: cs.onSurface,
              size: 20,
              minSize: 44,
              semanticLabel: l10n.messageStyleSettingsPageReset,
              onTap: () => resetMessageStyleSettings(context),
            ),
          ),
        ],
      ),
      body: const MessageStyleSettingsBody(),
    );
  }
}

Future<void> resetMessageStyleSettings(BuildContext context) async {
  final ok = await _confirmReset(context);
  if (!ok || !context.mounted) return;
  await context.read<SettingsProvider>().setChatBubbleStyleOverrides(
    const ChatBubbleStyleOverrides(),
  );
}

class MessageStyleSettingsBody extends StatefulWidget {
  const MessageStyleSettingsBody({super.key});

  @override
  State<MessageStyleSettingsBody> createState() =>
      _MessageStyleSettingsBodyState();
}

class _MessageStyleSettingsBodyState extends State<MessageStyleSettingsBody> {
  bool? _editingDark;
  bool _editingUser = false;
  ThemeData? _cachedLightTheme;
  ThemeData? _cachedDarkTheme;
  String? _previewThemeKey;

  bool get _isEditingDark =>
      _editingDark ?? Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    // Rebuild only for the settings this page and its preview show.
    context.select<SettingsProvider, Object>(
      (s) => (
        s.userChatBubbleStyleOverrides,
        s.assistantChatBubbleStyleOverrides,
        s.assistantBubbleFitContent,
        s.assistantBubbleSplitParagraphs,
        s.chatMessageBackgroundStyle,
        s.selectedCustomTheme,
        s.themePaletteId,
        s.useLayeredSurfaces,
        s.usePureBackground,
      ),
    );
    final style = settings.chatMessageBackgroundStyle;
    final overrides = settings.chatBubbleStyleOverridesFor(
      isUser: _editingUser,
    );
    final editingDark = _isEditingDark;
    final isDefault = style == ChatMessageBackgroundStyle.defaultStyle;
    final previewThemes = _previewThemes(context);
    final lightTheme = previewThemes.$1;
    final darkTheme = previewThemes.$2;
    final previewTheme = editingDark ? darkTheme : lightTheme;
    final resolved = resolveBubbleStyle(
      previewTheme.colorScheme,
      previewTheme.brightness,
      style,
      overrides,
    );

    final stylePicker = SectionCard(
      children: [
        _StyleRow(
          style: ChatMessageBackgroundStyle.defaultStyle,
          label: l10n.displaySettingsPageChatMessageBackgroundDefault,
          subtitle: l10n.messageStyleSettingsPageStyleDefaultSubtitle,
          selected: isDefault,
          onTap: () => settings.setChatMessageBackgroundStyle(
            ChatMessageBackgroundStyle.defaultStyle,
          ),
        ),
        _iosDivider(context),
        _StyleRow(
          style: ChatMessageBackgroundStyle.frosted,
          label: l10n.displaySettingsPageChatMessageBackgroundFrosted,
          subtitle: l10n.messageStyleSettingsPageStyleFrostedSubtitle,
          selected: style == ChatMessageBackgroundStyle.frosted,
          onTap: () => settings.setChatMessageBackgroundStyle(
            ChatMessageBackgroundStyle.frosted,
          ),
        ),
        _iosDivider(context),
        _StyleRow(
          style: ChatMessageBackgroundStyle.solid,
          label: l10n.displaySettingsPageChatMessageBackgroundSolid,
          subtitle: l10n.messageStyleSettingsPageStyleSolidSubtitle,
          selected: style == ChatMessageBackgroundStyle.solid,
          onTap: () => settings.setChatMessageBackgroundStyle(
            ChatMessageBackgroundStyle.solid,
          ),
        ),
      ],
    );

    final layoutCard = SectionCard(
      children: [
        _SwitchRow(
          label: l10n.messageStyleSettingsPageAssistantFitContent,
          subtitle: l10n.messageStyleSettingsPageAssistantFitContentSubtitle,
          value: settings.assistantBubbleFitContent,
          onChanged: settings.setAssistantBubbleFitContent,
        ),
        _iosDivider(context),
        _SwitchRow(
          label: l10n.messageStyleSettingsPageAssistantSplitParagraphs,
          subtitle:
              l10n.messageStyleSettingsPageAssistantSplitParagraphsSubtitle,
          value: settings.assistantBubbleSplitParagraphs,
          onChanged: settings.setAssistantBubbleSplitParagraphs,
        ),
      ],
    );

    final preview = _PreviewPanel(
      theme: previewTheme,
      editingDark: editingDark,
      editingUser: _editingUser,
      style: style,
      userOverrides: settings.userChatBubbleStyleOverrides,
      assistantOverrides: settings.assistantChatBubbleStyleOverrides,
    );

    final params = SectionCard(
      children: [
        if (style == ChatMessageBackgroundStyle.frosted) ...[
          _SliderRow(
            label: l10n.messageStyleSettingsPageBlur,
            valueText: resolved.blurSigma.round().toString(),
            child: _ThemedSlider(
              value: resolved.blurSigma,
              min: 0,
              max: 30,
              stepSize: 1,
              onChanged: (v) => settings.setChatBubbleStyleOverridesForRole(
                isUser: _editingUser,
                value: overrides.copyWith(blurSigma: () => v),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              l10n.messageStyleSettingsPageBlurHint,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
          _iosDivider(context, indent: 14),
        ],
        _ColorRow(
          label: l10n.messageStyleSettingsPageBackgroundColor,
          color: resolved.background.withValues(alpha: 1),
          onTap: () => _pickColor(
            context,
            title: l10n.messageStyleSettingsPageBackgroundColor,
            initial: resolved.background.withValues(alpha: 1),
            onPicked: (color) {
              final argb = _opaqueArgb(color);
              settings.setChatBubbleStyleOverridesForRole(
                isUser: _editingUser,
                value: editingDark
                    ? overrides.copyWith(backgroundArgbDark: () => argb)
                    : overrides.copyWith(backgroundArgbLight: () => argb),
              );
            },
          ),
        ),
        _iosDivider(context, indent: 14),
        _SliderRow(
          label: l10n.messageStyleSettingsPageBackgroundOpacity,
          valueText: '${((_styleOpacity(style, overrides) * 100).round())}%',
          child: _ThemedSlider(
            value: _styleOpacity(style, overrides) * 100,
            min: 0,
            max: 100,
            stepSize: 1,
            onChanged: (v) {
              final opacity = (v / 100).clamp(0.0, 1.0);
              settings.setChatBubbleStyleOverridesForRole(
                isUser: _editingUser,
                value: style == ChatMessageBackgroundStyle.frosted
                    ? overrides.copyWith(frostedOpacity: () => opacity)
                    : overrides.copyWith(solidOpacity: () => opacity),
              );
            },
          ),
        ),
        _iosDivider(context, indent: 14),
        _ColorRow(
          label: l10n.messageStyleSettingsPageBorderColor,
          color: resolved.border.withValues(alpha: 1),
          onTap: () => _pickColor(
            context,
            title: l10n.messageStyleSettingsPageBorderColor,
            initial: resolved.border.withValues(alpha: 1),
            onPicked: (color) {
              final argb = _opaqueArgb(color);
              settings.setChatBubbleStyleOverridesForRole(
                isUser: _editingUser,
                value: editingDark
                    ? overrides.copyWith(borderArgbDark: () => argb)
                    : overrides.copyWith(borderArgbLight: () => argb),
              );
            },
          ),
        ),
        _iosDivider(context, indent: 14),
        _SliderRow(
          label: l10n.messageStyleSettingsPageBorderOpacity,
          valueText: '${((resolved.border.a * 100).round())}%',
          child: _ThemedSlider(
            value: resolved.border.a * 100,
            min: 0,
            max: 100,
            stepSize: 1,
            onChanged: (v) => settings.setChatBubbleStyleOverridesForRole(
              isUser: _editingUser,
              value: overrides.copyWith(
                borderOpacity: () => (v / 100).clamp(0.0, 1.0),
              ),
            ),
          ),
        ),
        _iosDivider(context, indent: 14),
        _SliderRow(
          label: l10n.messageStyleSettingsPageBorderWidth,
          valueText: resolved.borderWidth.toStringAsFixed(1),
          child: _ThemedSlider(
            value: resolved.borderWidth,
            min: 0,
            max: 3,
            stepSize: 0.1,
            onChanged: (v) => settings.setChatBubbleStyleOverridesForRole(
              isUser: _editingUser,
              value: overrides.copyWith(borderWidth: () => v),
            ),
          ),
        ),
        _iosDivider(context, indent: 14),
        _ColorRow(
          label: l10n.messageStyleSettingsPageTextColor,
          color: resolved.text.withValues(alpha: 1),
          onTap: () => _pickColor(
            context,
            title: l10n.messageStyleSettingsPageTextColor,
            initial: resolved.text.withValues(alpha: 1),
            onPicked: (color) {
              final argb = _opaqueArgb(color);
              settings.setChatBubbleStyleOverridesForRole(
                isUser: _editingUser,
                value: editingDark
                    ? overrides.copyWith(textArgbDark: () => argb)
                    : overrides.copyWith(textArgbLight: () => argb),
              );
            },
          ),
        ),
        _iosDivider(context, indent: 14),
        _SliderRow(
          label: l10n.messageStyleSettingsPageCornerRadius,
          valueText: resolved.radius.round().toString(),
          child: _ThemedSlider(
            value: resolved.radius,
            min: 0,
            max: 28,
            stepSize: 1,
            onChanged: (v) => settings.setChatBubbleStyleOverridesForRole(
              isUser: _editingUser,
              value: overrides.copyWith(cornerRadius: () => v),
            ),
          ),
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            stylePicker,
            const SizedBox(height: 12),
            layoutCard,
            const SizedBox(height: 12),
            _SegmentedToggle(
              leftLabel: l10n.messageStyleSettingsPageLight,
              leftIcon: Lucide.Sun,
              rightLabel: l10n.messageStyleSettingsPageDark,
              rightIcon: Lucide.Moon,
              rightSelected: editingDark,
              onChanged: (value) {
                if (value == editingDark) return;
                Haptics.soft();
                setState(() => _editingDark = value);
              },
            ),
            if (!isDefault) ...[
              const SizedBox(height: 12),
              _SegmentedToggle(
                leftLabel: l10n.messageStyleSettingsPageRoleUser,
                leftIcon: Lucide.User,
                rightLabel: l10n.messageStyleSettingsPageRoleAssistant,
                rightIcon: Lucide.Bot,
                rightSelected: !_editingUser,
                onChanged: (rightSelected) {
                  final editingUser = !rightSelected;
                  if (editingUser == _editingUser) return;
                  Haptics.soft();
                  setState(() => _editingUser = editingUser);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  l10n.messageStyleSettingsPageRoleAssistantHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            preview,
            if (isDefault)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Text(
                  l10n.messageStyleSettingsPageDefaultHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 12),
              params,
            ],
          ],
        ),
      ),
    );
  }

  (ThemeData, ThemeData) _previewThemes(BuildContext context) {
    final current = Theme.of(context);
    final settings = context.read<SettingsProvider>();
    final custom = settings.selectedCustomTheme;
    final key =
        '${current.brightness.name}|${settings.themePaletteId}|${custom?.id}|${settings.usePureBackground}|${settings.useLayeredSurfaces}';
    if (_cachedLightTheme != null &&
        _cachedDarkTheme != null &&
        _previewThemeKey == key) {
      return (_cachedLightTheme!, _cachedDarkTheme!);
    }

    final palette =
        settings.themePaletteId == ThemePalettes.customPaletteId &&
            custom != null
        ? buildCustomThemePalette(custom)
        : ThemePalettes.byId(settings.themePaletteId);
    final light = current.brightness == Brightness.light
        ? current
        : buildLightThemeForScheme(
            palette.light,
            pureBackground: settings.usePureBackground,
            layeredSurfaces: settings.useLayeredSurfaces,
          );
    final dark = current.brightness == Brightness.dark
        ? current
        : buildDarkThemeForScheme(
            palette.dark,
            pureBackground: settings.usePureBackground,
            layeredSurfaces: settings.useLayeredSurfaces,
          );
    _cachedLightTheme = light;
    _cachedDarkTheme = dark;
    _previewThemeKey = key;
    return (light, dark);
  }

  Future<void> _pickColor(
    BuildContext context, {
    required String title,
    required Color initial,
    required ValueChanged<Color> onPicked,
  }) async {
    final result = await showAppColorPicker(
      context,
      title: title,
      initial: initial,
    );
    if (!mounted || result == null) return;
    onPicked(result);
  }
}

double _styleOpacity(
  ChatMessageBackgroundStyle style,
  ChatBubbleStyleOverrides overrides,
) {
  return switch (style) {
    ChatMessageBackgroundStyle.frosted => overrides.frostedOpacity ?? 0.66,
    ChatMessageBackgroundStyle.solid => overrides.solidOpacity ?? 1.0,
    ChatMessageBackgroundStyle.defaultStyle => overrides.solidOpacity ?? 1.0,
  };
}

int _opaqueArgb(Color color) => color.withValues(alpha: 1).toARGB32();

Future<bool> _confirmReset(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: cs.scrim.withValues(alpha: 0.25),
    pageBuilder: (ctx, _, __) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).maybePop(false),
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isDark
                            ? cs.onSurface.withValues(alpha: 0.08)
                            : cs.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.messageStyleSettingsPageResetConfirm,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: AppFontWeights.medium,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: IosTileButton(
                                icon: Lucide.X,
                                label: l10n.messageStyleSettingsPageCancel,
                                onTap: () => Navigator.of(ctx).maybePop(false),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: IosTileButton(
                                icon: Lucide.RotateCcw,
                                label: l10n.messageStyleSettingsPageReset,
                                backgroundColor: cs.primary,
                                foregroundColor: cs.primary,
                                onTap: () => Navigator.of(ctx).maybePop(true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return ok ?? false;
}
