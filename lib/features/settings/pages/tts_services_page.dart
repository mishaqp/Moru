import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/tts_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/services/tts/network_tts.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../core/services/haptics.dart';
import 'tts_settings_page.dart';
import '../widgets/asr_services_section.dart';
import '../widgets/voice_service_widgets.dart';
import '../widgets/mimo_reference_audio_picker.dart';
import '../../../theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';

part 'tts_network_editor.dart';
part 'tts_network_list.dart';
part 'tts_system_config_sheet.dart';

class TtsServicesPage extends StatelessWidget {
  const TtsServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.ttsServicesPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.ttsServicesPageTitle),
        actions: [
          Tooltip(
            message: l10n.ttsServicesPageSettingsTooltip,
            child: _TactileIconButton(
              icon: Lucide.Settings2,
              color: cs.onSurface,
              size: 22,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TtsSettingsPage(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Consumer2<TtsProvider, SettingsProvider>(
        builder: (context, tts, sp, _) {
          final services = sp.ttsServices;
          final available = tts.isAvailable && (tts.error == null);
          final titleText = l10n.ttsServicesPageSystemTtsTitle;
          final subText = available
              ? l10n.ttsServicesPageSystemTtsAvailableSubtitle
              : l10n.ttsServicesPageSystemTtsUnavailableSubtitle(
                  tts.error ??
                      l10n.ttsServicesPageSystemTtsUnavailableNotInitialized,
                );
          final systemLetter =
              (titleText.trim().isEmpty
                      ? '?'
                      : titleText.trim().substring(0, 1))
                  .toUpperCase();
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: VoiceServiceSectionHeader(
                        title: l10n.ttsServicesSectionTitle,
                        addTooltip: l10n.ttsServicesPageAddTooltip,
                        onAdd: () => _handleAddNetworkTts(context),
                        first: true,
                      ),
                    ),
                    VoiceServiceCardSliver(
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: _TactileRow(
                              pressedScale: 0.98,
                              haptics: false,
                              onTap: available
                                  ? () async {
                                      await sp.setSelectedTtsServiceId(null);
                                    }
                                  : null,
                              builder: (pressed) {
                                final cs2 = Theme.of(context).colorScheme;
                                final base = cs2.onSurface.withValues(
                                  alpha: 0.9,
                                );
                                return _AnimatedPressColor(
                                  pressed: pressed,
                                  base: base,
                                  builder: (c) {
                                    final isDark =
                                        Theme.of(context).brightness ==
                                        Brightness.dark;
                                    final overlay = pressed
                                        ? cs2.surface.withValues(
                                            alpha: isDark ? 0.06 : 0.05,
                                          )
                                        : Colors.transparent;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 11,
                                      ),
                                      child: Row(
                                        children: [
                                          _AvatarBadge(
                                            letter: systemLetter,
                                            overlay: overlay,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  titleText,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    color: c,
                                                    fontWeight:
                                                        AppFontWeights.semibold,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  subText,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.withValues(
                                                      alpha: 0.7,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _SmallTactileIcon(
                                            icon: Lucide.Volume2,
                                            baseColor: c,
                                            onTap: available
                                                ? () async {
                                                    final demo = l10n
                                                        .ttsServicesPageTestSpeechText;
                                                    await tts.speakSystem(demo);
                                                  }
                                                : () {},
                                            enabled: available,
                                          ),
                                          const SizedBox(width: 6),
                                          _SmallTactileIcon(
                                            icon: Lucide.Settings2,
                                            baseColor: c,
                                            onTap: available
                                                ? () => _showSystemTtsConfig(
                                                    context,
                                                  )
                                                : () {},
                                            enabled: available,
                                          ),
                                          const SizedBox(width: 8),
                                          // right indicator: show check only when selected
                                          Builder(
                                            builder: (_) {
                                              final sp2 = context
                                                  .watch<SettingsProvider>();
                                              final sel = sp2.usingSystemTts;
                                              return sel
                                                  ? Icon(
                                                      Lucide.Check,
                                                      size: 16,
                                                      color: c,
                                                    )
                                                  : const SizedBox(width: 16);
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (services.isNotEmpty)
                            SliverToBoxAdapter(child: _iosDivider(context)),
                          if (services.isNotEmpty)
                            _MobileNetworkTtsList(services: services),
                        ],
                      ),
                    ),
                    const AsrServicesSection(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --- iOS-style widgets and helpers ---

Widget _header(BuildContext context, String text, {bool first = false}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: EdgeInsets.fromLTRB(12, first ? 6 : 18, 12, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: cs.onSurface.withValues(alpha: 0.8),
      ),
    ),
  );
}

Future<void> _handleAddNetworkTts(BuildContext context) async {
  final sp = context.read<SettingsProvider>();
  final created = await _showAddNetworkTtsSheet(context);
  if (created == null) {
    return;
  }

  final list = List<TtsServiceOptions>.from(sp.ttsServices)..add(created);
  await sp.setTtsServices(list);
  if (sp.usingSystemTts) {
    await sp.setSelectedTtsServiceId(created.id);
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.pressedScale = 1.00,
    this.haptics = true,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics &&
                  context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.builder(_pressed),
      ),
    );
  }
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color c) builder;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = pressed
        ? (Color.lerp(base, cs.surface, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

class _SmallTactileIcon extends StatefulWidget {
  const _SmallTactileIcon({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.baseColor,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final Color? baseColor;
  @override
  State<_SmallTactileIcon> createState() => _SmallTactileIconState();
}

class _SmallTactileIconState extends State<_SmallTactileIcon> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = widget.baseColor ?? cs.onSurface;
    final c = widget.enabled
        ? base.withValues(alpha: _pressed ? 0.6 : 0.9)
        : base.withValues(alpha: 0.3);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _pressed = false)
          : null,
      onTap: widget.enabled
          ? () {
              Haptics.soft();
              widget.onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(widget.icon, size: 18, color: c),
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.letter, required this.overlay});
  final String letter;
  final Color overlay;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: baseBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: TextStyle(
              color: cs.primary,
              fontWeight: AppFontWeights.emphasis,
              fontSize: 14,
            ),
          ),
        ),
        if (overlay != Colors.transparent)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: overlay, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

class _AvatarBrandBadge extends StatelessWidget {
  const _AvatarBrandBadge({required this.name, required this.overlay});
  final String name;
  final Color overlay;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    final asset =
        BrandAssets.assetForName(name) ??
        BrandAssets.assetForName(name.split(' ').first);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: baseBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: asset == null
              ? Text(
                  (name.isEmpty ? '?' : name[0]).toUpperCase(),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: AppFontWeights.emphasis,
                    fontSize: 14,
                  ),
                )
              : (asset.endsWith('.svg')
                    ? SvgPicture.asset(
                        asset,
                        width: 20,
                        height: 20,
                        colorFilter:
                            isDark && BrandAssets.assetNeedsDarkInvert(asset)
                            ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
                            : null,
                      )
                    : Image.asset(
                        asset,
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                      )),
        ),
        if (overlay != Colors.transparent)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: overlay, shape: BoxShape.circle),
          ),
      ],
    );
  }
}
