import '../widgets/settings_search_target.dart';
import 'mobile_background_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import '../../../core/providers/settings_provider.dart';
import 'auto_retry_page.dart';
import 'google_fonts_picker_page.dart';
import 'image_settings_page.dart';
import 'message_style_settings_page.dart';
import 'theme_settings_page.dart';
import '../../../theme/palettes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../widgets/memory_ui.dart';
import '../../../core/services/haptics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';

part 'display_settings_widgets.dart';
part 'display_chat_item_page.dart';
part 'display_rendering_page.dart';
part 'display_behavior_page.dart';
part 'display_haptics_page.dart';

enum _FontTarget { app, code }

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // Rows with their own details watch their settings in their own
    // builders; the page itself only shows the palette name.
    final paletteId = context.select<SettingsProvider, String>(
      (s) => s.themePaletteId,
    );

    String paletteName() {
      final palette = ThemePalettes.byId(paletteId);
      return palette.localizedName(l10n);
    }

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.settingsPageDisplay),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          // header(l10n.displaySettingsPageThemeSettingsTitle),
          SectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.Palette,
                label: l10n.displaySettingsPageThemeSettingsTitle,
                detailText: paletteName(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Languages,
                label: l10n.displaySettingsPageLanguageTitle,
                detailBuilder: (ctx) {
                  final settings = ctx.watch<SettingsProvider>();
                  String labelFor(Locale l) {
                    if (l.languageCode == 'ru') return l10n.moruLanguageRussian;
                    if (l.languageCode == 'zh') {
                      if ((l.scriptCode ?? '').toLowerCase() == 'hant') {
                        return l10n.languageDisplayTraditionalChinese;
                      }
                      return l10n.displaySettingsPageLanguageChineseLabel;
                    }
                    return l10n.displaySettingsPageLanguageEnglishLabel;
                  }

                  return Text(
                    settings.isFollowingSystemLocale
                        ? l10n.settingsPageSystemMode
                        : labelFor(settings.appLocale),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () async {
                  await _showLanguageSheet(context);
                  if (mounted) setState(() {});
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.MessageCircleMore,
                label: l10n.displaySettingsPageChatItemDisplayTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChatItemDisplaySettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.TextInitial,
                label: l10n.displaySettingsPageRenderingSettingsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RenderingSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.eclipse,
                label: l10n.displaySettingsPageBehaviorStartupTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BehaviorStartupSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Image,
                label: l10n.imageSettingsPageTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImageSettingsPage()),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.MessageSquare,
                label: l10n.messageStyleSettingsPageTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MessageStyleSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.RefreshCw,
                label: l10n.settingsPageAutoRetry,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AutoRetryPage()),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsSettingsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HapticsSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Activity,
                label: l10n.backgroundSettingsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MobileBackgroundSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Type,
                label: l10n.displaySettingsPageAppFontTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  final fam = sp.appFontFamily;
                  final useLocal = (sp.appFontLocalAlias ?? '').isNotEmpty;
                  final text = useLocal
                      ? l10n.displaySettingsPageFontLocalFileLabel
                      : (fam == null || fam.isEmpty)
                      ? l10n.desktopFontFamilySystemDefault
                      : fam;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showMobileFontSourceSheet(
                  context,
                  target: _FontTarget.app,
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Code,
                label: l10n.displaySettingsPageCodeFontTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  final fam = sp.codeFontFamily;
                  final useLocal = (sp.codeFontLocalAlias ?? '').isNotEmpty;
                  final text = useLocal
                      ? l10n.displaySettingsPageFontLocalFileLabel
                      : (fam == null || fam.isEmpty)
                      ? l10n.desktopFontFamilyMonospaceDefault
                      : fam;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showMobileFontSourceSheet(
                  context,
                  target: _FontTarget.code,
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.CaseSensitive,
                label: l10n.displaySettingsPageChatFontSizeTitle,
                detailBuilder: (ctx) {
                  final scale = ctx.watch<SettingsProvider>().chatFontScale;
                  return Text(
                    '${(scale * 100).round()}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatFontSizeSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.ArrowDown,
                label: l10n.displaySettingsPageAutoScrollIdleTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  if (!sp.autoScrollEnabled) {
                    return Text(
                      l10n.displaySettingsPageAutoScrollDisabledLabel,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    );
                  }
                  final seconds = sp.autoScrollIdleSeconds;
                  return Text(
                    AppLocalizations.of(
                      context,
                    )!.moruSecondsShort(seconds.round()),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showAutoScrollIdleSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Image,
                label: l10n.displaySettingsPageChatBackgroundMaskTitle,
                detailBuilder: (ctx) {
                  final v = ctx
                      .watch<SettingsProvider>()
                      .chatBackgroundMaskStrength;
                  return Text(
                    '${(v * 100).round()}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatBackgroundMaskSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.RectangleHorizontal,
                label: l10n.displaySettingsPageChatInputBackgroundOpacityTitle,
                detailBuilder: (ctx) {
                  final brightness = Theme.of(ctx).brightness;
                  final settings = ctx.watch<SettingsProvider>();
                  final opacity = settings.chatInputBackgroundOpacityFor(
                    brightness,
                  );
                  return Text(
                    '${(opacity * 100).round()}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatInputBackgroundOpacitySheet(context),
              ),
            ],
          ),
          // Inline cards replaced by sheet-triggering rows above.
        ],
      ),
    );
  }

  Future<void> _showMobileFontSourceSheet(
    BuildContext context, {
    required _FontTarget target,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetOption(
                ctx,
                label: l10n.googleFontsTitle,
                onTap: () => Navigator.of(ctx).pop('google'),
              ),
              _sheetDividerNoIcon(ctx),
              _sheetOption(
                ctx,
                label: l10n.fontPickerChooseLocalFile,
                onTap: () => Navigator.of(ctx).pop('local'),
              ),
              _sheetDividerNoIcon(ctx),
              _sheetOption(
                ctx,
                label: l10n.displaySettingsPageFontResetLabel,
                onTap: () => Navigator.of(ctx).pop('reset'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (!context.mounted) return;

    final settings = context.read<SettingsProvider>();
    if (choice == 'google') {
      await showGoogleFontsPicker(context, forCode: target == _FontTarget.code);
      return;
    }
    if (choice == 'local') {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      final path = res?.files.singleOrNull?.path;
      if (path == null) return;
      if (!context.mounted) return;
      if (target == _FontTarget.app) {
        await settings.setAppFontFromLocal(path: path);
      } else {
        await settings.setCodeFontFromLocal(path: path);
      }
      return;
    }
    if (choice == 'reset') {
      if (target == _FontTarget.app) {
        await settings.clearAppFont();
      } else {
        await settings.clearCodeFont();
      }
    }
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetOption(
                  ctx,
                  label: l10n.settingsPageSystemMode,
                  onTap: () => Navigator.of(ctx).pop('system'),
                ),
                _sheetDividerNoIcon(ctx),
                _sheetOption(
                  ctx,
                  label: l10n.moruLanguageRussian,
                  onTap: () => Navigator.of(ctx).pop('ru'),
                ),
                _sheetDividerNoIcon(ctx),
                _sheetOption(
                  ctx,
                  label: l10n.displaySettingsPageLanguageChineseLabel,
                  onTap: () => Navigator.of(ctx).pop('zh_CN'),
                ),
                _sheetDividerNoIcon(ctx),
                _sheetOption(
                  ctx,
                  label: l10n.languageDisplayTraditionalChinese,
                  onTap: () => Navigator.of(ctx).pop('zh_Hant'),
                ),
                _sheetDividerNoIcon(ctx),
                _sheetOption(
                  ctx,
                  label: l10n.displaySettingsPageLanguageEnglishLabel,
                  onTap: () => Navigator.of(ctx).pop('en_US'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    if (!context.mounted) return;

    final settings = context.read<SettingsProvider>();
    switch (selected) {
      case 'ru':
        await settings.setAppLocale(const Locale('ru'));
        break;
      case 'system':
        await settings.setAppLocaleFollowSystem();
        break;
      case 'zh_CN':
        await settings.setAppLocale(const Locale('zh', 'CN'));
        break;
      case 'zh_Hant':
        await settings.setAppLocale(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        );
        break;
      case 'en_US':
      default:
        await settings.setAppLocale(const Locale('en', 'US'));
    }
  }

  Future<void> _showChatFontSizeSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final scale = context.watch<SettingsProvider>().chatFontScale;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '50%',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SfSliderTheme(
                            data: SfSliderThemeData(
                              activeTrackHeight: 8,
                              inactiveTrackHeight: 8,
                              overlayRadius: 14,
                              activeTrackColor: cs.primary,
                              inactiveTrackColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.25 : 0.20,
                              ),
                              tooltipBackgroundColor: cs.primary,
                              tooltipTextStyle: TextStyle(
                                color: cs.onPrimary,
                                fontWeight: AppFontWeights.semibold,
                              ),
                              activeTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.45 : 0.35,
                              ),
                              inactiveTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.30 : 0.25,
                              ),
                              activeMinorTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.34 : 0.28,
                              ),
                              inactiveMinorTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.24 : 0.20,
                              ),
                            ),
                            child: SfSlider(
                              value: scale,
                              min: 0.5,
                              max: 1.50001,
                              stepSize: 0.05,
                              showTicks: true,
                              showLabels: true,
                              interval: 0.1,
                              minorTicksPerInterval: 1,
                              enableTooltip: true,
                              shouldAlwaysShowTooltip: false,
                              tooltipShape: const SfPaddleTooltipShape(),
                              labelFormatterCallback: (value, text) =>
                                  (value as double).toStringAsFixed(1),
                              thumbIcon: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: isDark
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: cs.shadow.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                ),
                              ),
                              onChanged: (v) => context
                                  .read<SettingsProvider>()
                                  .setChatFontScale(
                                    (v as double).clamp(0.5, 1.5),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(scale * 100).round()}%',
                          style: TextStyle(color: cs.onSurface, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        l10n.displaySettingsPageChatFontSampleText,
                        style: TextStyle(
                          fontSize:
                              16 *
                              context.watch<SettingsProvider>().chatFontScale,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAutoScrollIdleSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final sp = context.watch<SettingsProvider>();
                final seconds = sp.autoScrollIdleSeconds;
                final enabled = sp.autoScrollEnabled;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.displaySettingsPageAutoScrollEnableTitle,
                          style: TextStyle(fontSize: 15, color: cs.onSurface),
                        ),
                        const Spacer(),
                        IosSwitch(
                          value: enabled,
                          onChanged: (v) => context
                              .read<SettingsProvider>()
                              .setAutoScrollEnabled(v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.moruSecondsShort(2),
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SfSliderTheme(
                            data: SfSliderThemeData(
                              activeTrackHeight: 8,
                              inactiveTrackHeight: 8,
                              overlayRadius: 14,
                              activeTrackColor: cs.primary,
                              inactiveTrackColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.25 : 0.20,
                              ),
                              tooltipBackgroundColor: cs.primary,
                              tooltipTextStyle: TextStyle(
                                color: cs.onPrimary,
                                fontWeight: AppFontWeights.semibold,
                              ),
                              activeTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.45 : 0.35,
                              ),
                              inactiveTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.30 : 0.25,
                              ),
                              activeMinorTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.34 : 0.28,
                              ),
                              inactiveMinorTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.24 : 0.20,
                              ),
                            ),
                            child: SfSlider(
                              value: seconds.toDouble(),
                              min: 2.0,
                              max: 64.0,
                              stepSize: 2.0,
                              showTicks: true,
                              showLabels: true,
                              interval: 10.0,
                              minorTicksPerInterval: 1,
                              enableTooltip: true,
                              shouldAlwaysShowTooltip: false,
                              tooltipShape: const SfPaddleTooltipShape(),
                              labelFormatterCallback: (value, text) =>
                                  value.toInt().toString(),
                              thumbIcon: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: isDark
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: cs.shadow.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                ),
                              ),
                              onChanged: enabled
                                  ? (v) => context
                                        .read<SettingsProvider>()
                                        .setAutoScrollIdleSeconds(
                                          (v as double).round(),
                                        )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          enabled
                              ? AppLocalizations.of(
                                  context,
                                )!.moruSecondsShort(seconds.round())
                              : l10n.displaySettingsPageAutoScrollDisabledLabel,
                          style: TextStyle(
                            color: cs.onSurface.withValues(
                              alpha: enabled ? 1.0 : 0.5,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.displaySettingsPageAutoScrollIdleSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChatBackgroundMaskSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final strength = context
                    .watch<SettingsProvider>()
                    .chatBackgroundMaskStrength;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '0%',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SfSliderTheme(
                            data: SfSliderThemeData(
                              activeTrackHeight: 8,
                              inactiveTrackHeight: 8,
                              overlayRadius: 14,
                              activeTrackColor: cs.primary,
                              inactiveTrackColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.25 : 0.20,
                              ),
                              tooltipBackgroundColor: cs.primary,
                              tooltipTextStyle: TextStyle(
                                color: cs.onPrimary,
                                fontWeight: AppFontWeights.semibold,
                              ),
                              activeTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.45 : 0.35,
                              ),
                              inactiveTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.30 : 0.25,
                              ),
                              activeMinorTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.34 : 0.28,
                              ),
                              inactiveMinorTickColor: cs.onSurface.withValues(
                                alpha: isDark ? 0.24 : 0.20,
                              ),
                            ),
                            child: SfSlider(
                              value: (strength * 100).roundToDouble(),
                              min: 0.0,
                              max: 200.0001,
                              stepSize: 5.0,
                              showTicks: true,
                              showLabels: true,
                              interval: 50,
                              minorTicksPerInterval: 1,
                              enableTooltip: true,
                              shouldAlwaysShowTooltip: false,
                              tooltipShape: const SfPaddleTooltipShape(),
                              labelFormatterCallback: (value, text) =>
                                  '${(value as double).round()}%',
                              thumbIcon: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: isDark
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: cs.shadow.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                ),
                              ),
                              onChanged: (v) => context
                                  .read<SettingsProvider>()
                                  .setChatBackgroundMaskStrength(
                                    ((v as double) / 100.0).clamp(0.0, 2.0),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(strength * 100).round()}%',
                          style: TextStyle(color: cs.onSurface, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChatInputBackgroundOpacitySheet(
    BuildContext context,
  ) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;
                final l10n = AppLocalizations.of(context)!;
                final settings = context.watch<SettingsProvider>();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chatInputOpacitySlider(
                      context,
                      label: l10n.settingsPageLightMode,
                      brightness: Brightness.light,
                      opacity: settings.chatInputBackgroundOpacityLight,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 18),
                    _chatInputOpacitySlider(
                      context,
                      label: l10n.settingsPageDarkMode,
                      brightness: Brightness.dark,
                      opacity: settings.chatInputBackgroundOpacityDark,
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _chatInputOpacitySlider(
    BuildContext context, {
    required String label,
    required Brightness brightness,
    required double opacity,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 13,
            fontWeight: AppFontWeights.semibold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '0%',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SfSliderTheme(
                data: SfSliderThemeData(
                  activeTrackHeight: 8,
                  inactiveTrackHeight: 8,
                  overlayRadius: 14,
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.25 : 0.20,
                  ),
                  tooltipBackgroundColor: cs.primary,
                  tooltipTextStyle: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: AppFontWeights.semibold,
                  ),
                  activeTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.45 : 0.35,
                  ),
                  inactiveTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.30 : 0.25,
                  ),
                  activeMinorTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.34 : 0.28,
                  ),
                  inactiveMinorTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.24 : 0.20,
                  ),
                ),
                child: SfSlider(
                  value: (opacity * 100).roundToDouble(),
                  min: 0.0,
                  max: 100.0001,
                  stepSize: 5.0,
                  showTicks: true,
                  showLabels: true,
                  interval: 25,
                  minorTicksPerInterval: 1,
                  enableTooltip: true,
                  shouldAlwaysShowTooltip: false,
                  tooltipShape: const SfPaddleTooltipShape(),
                  labelFormatterCallback: (value, text) =>
                      '${(value as double).round()}%',
                  thumbIcon: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: cs.shadow.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                    ),
                  ),
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setChatInputBackgroundOpacity(
                        brightness,
                        ((v as double) / 100.0).clamp(0.0, 1.0),
                      ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(opacity * 100).round()}%',
              style: TextStyle(color: cs.onSurface, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

// --- iOS-style helpers ---
