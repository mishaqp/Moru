part of 'display_settings_page.dart';

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

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
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

class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap, this.haptics = true});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final bool haptics;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics &&
                  context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
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

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  final row = _TactileRow(
    onTap: onTap,
    haptics: true,
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                          // Its own element, so the settings it watches
                          // rebuild only this detail, not the whole page.
                          child: Builder(builder: detailBuilder),
                        ),
                      ),
                    ),
                  )
                else if (detailText != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          detailText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
  return SettingsSearchTarget.wrap(context, label, row);
}

Widget _iosSwitchRow(
  BuildContext context, {
  IconData? icon,
  required String label,
  String? subtitle,
  String? tip,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  final row = Padding(
    padding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: subtitle == null ? 2 : 8,
    ),
    child: Row(
      children: [
        Expanded(
          child: _TactileRow(
            onTap: () => onChanged(!value),
            builder: (pressed) {
              final baseColor = cs.onSurface.withValues(alpha: 0.9);
              return _AnimatedPressColor(
                pressed: pressed,
                base: baseColor,
                builder: (c) {
                  return Row(
                    children: [
                      if (icon != null) ...[
                        SizedBox(
                          width: 36,
                          child: Icon(icon, size: 20, color: c),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(fontSize: 15, color: c),
                            ),
                            if (subtitle != null && subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.2,
                                  color: cs.onSurface.withValues(alpha: 0.56),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (tip != null) MemoryTipIcon(message: tip),
        const SizedBox(width: 12),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
  return SettingsSearchTarget.wrap(context, label, row);
}

Widget _sheetOption(
  BuildContext context, {
  IconData? icon,
  required String label,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _TactileRow(
    onTap: onTap,
    builder: (pressed) {
      final base = cs.onSurface;
      final target = pressed
          ? (Color.lerp(base, cs.surface, 0.55) ?? base)
          : base;
      final bgTarget = pressed
          ? (cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.05))
          : Colors.transparent;
      return TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, color, _) {
          final c = color ?? base;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: bgTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (icon != null) ...[
                  SizedBox(width: 24, child: Icon(icon, size: 20, color: c)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, color: c)),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetDividerNoIcon(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 0.6,
    indent: 16,
    endIndent: 16,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

Future<void> _showMobileMessageNavModeSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final choice = await showModalBottomSheet<MobileMessageNavButtonsMode>(
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
              label: l10n.displaySettingsPageMessageNavButtonsModeAlways,
              onTap: () =>
                  Navigator.of(ctx).pop(MobileMessageNavButtonsMode.always),
            ),
            _sheetDividerNoIcon(ctx),
            _sheetOption(
              ctx,
              label: l10n.displaySettingsPageMessageNavButtonsModeScroll,
              onTap: () =>
                  Navigator.of(ctx).pop(MobileMessageNavButtonsMode.scroll),
            ),
            _sheetDividerNoIcon(ctx),
            _sheetOption(
              ctx,
              label: l10n.displaySettingsPageMessageNavButtonsModeNever,
              onTap: () =>
                  Navigator.of(ctx).pop(MobileMessageNavButtonsMode.never),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return;
  if (!context.mounted) return;
  await context.read<SettingsProvider>().setMobileMessageNavButtonsMode(choice);
}

// --- Subpages ---
