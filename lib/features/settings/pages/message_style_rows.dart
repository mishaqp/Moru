part of 'message_style_settings_page.dart';

class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.style,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final ChatMessageBackgroundStyle style;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _StyleSwatch(style: style),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: cs.onSurface.withValues(alpha: 0.52),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Lucide.Check, size: 18, color: cs.primary)
            else
              const SizedBox(width: 18, height: 18),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: cs.onSurface.withValues(alpha: 0.52),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IosSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.style});

  final ChatMessageBackgroundStyle style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fill;
    final Color border;
    switch (style) {
      case ChatMessageBackgroundStyle.defaultStyle:
        fill = cs.primary.withValues(alpha: isDark ? 0.22 : 0.14);
        border = cs.primary.withValues(alpha: 0.18);
      case ChatMessageBackgroundStyle.frosted:
        fill = cs.surfaceContainerHigh.withValues(alpha: 0.62);
        border = cs.outlineVariant.withValues(alpha: 0.42);
      case ChatMessageBackgroundStyle.solid:
        fill = cs.surfaceContainerHigh;
        border = cs.outlineVariant.withValues(alpha: 0.55);
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.8),
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  const _SegmentedToggle({
    required this.leftLabel,
    required this.leftIcon,
    required this.rightLabel,
    required this.rightIcon,
    required this.rightSelected,
    required this.onChanged,
  });

  final String leftLabel;
  final IconData leftIcon;
  final String rightLabel;
  final IconData rightIcon;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.hairline, width: 0.6),
      ),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: rightSelected
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.appColors.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isDark
                          ? const []
                          : [
                              BoxShadow(
                                color: cs.shadow.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SegmentedToggleHit(
                      label: leftLabel,
                      icon: leftIcon,
                      selected: !rightSelected,
                      onTap: () => onChanged(false),
                    ),
                  ),
                  Expanded(
                    child: _SegmentedToggleHit(
                      label: rightLabel,
                      icon: rightIcon,
                      selected: rightSelected,
                      onTap: () => onChanged(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedToggleHit extends StatelessWidget {
  const _SegmentedToggleHit({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                size: 16,
                color: selected
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.52),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 1.1,
                fontWeight: selected
                    ? AppFontWeights.semibold
                    : AppFontWeights.regular,
                color: selected
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.child,
  });

  final String label;
  final String valueText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _ThemedSlider extends StatelessWidget {
  const _ThemedSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.stepSize,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double stepSize;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return SfSliderTheme(
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
        activeTickColor: cs.onSurface.withValues(alpha: isDark ? 0.45 : 0.35),
        inactiveTickColor: cs.onSurface.withValues(alpha: isDark ? 0.30 : 0.25),
        activeMinorTickColor: cs.onSurface.withValues(
          alpha: isDark ? 0.34 : 0.28,
        ),
        inactiveMinorTickColor: cs.onSurface.withValues(
          alpha: isDark ? 0.24 : 0.20,
        ),
      ),
      child: SfSlider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        stepSize: stepSize,
        enableTooltip: true,
        shouldAlwaysShowTooltip: false,
        tooltipShape: const SfPaddleTooltipShape(),
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
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
        ),
        onChanged: (v) => onChanged((v as double).clamp(min, max)),
      ),
    );
  }
}

Widget _iosDivider(BuildContext context, {double indent = 14}) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: indent,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}
