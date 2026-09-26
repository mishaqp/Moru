part of 'model_detail_sheet.dart';

class _SegmentedSingle extends StatelessWidget {
  const _SegmentedSingle({
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<String> options;
  final int value; // index
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sel = isDark
        ? cs.primary.withValues(alpha: 0.20)
        : cs.primary.withValues(alpha: 0.14);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: context.appColors.surfaceFill,
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: i == value ? sel : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i == value)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Lucide.Check,
                            size: 16,
                            color: cs.primary,
                          ),
                        ),
                      Text(
                        options[i],
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentedMulti extends StatelessWidget {
  const _SegmentedMulti({
    required this.options,
    required this.isSelected,
    required this.onChanged,
    this.allowEmpty = false,
  });

  final List<String> options;
  final List<bool> isSelected;
  final ValueChanged<int> onChanged;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    assert(options.length == isSelected.length);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool allSelected =
        isSelected.isNotEmpty && isSelected.every((e) => e);
    final int selectedCount = isSelected.where((e) => e).length;

    final base = context.appColors.surfaceFill;
    final sel = isDark
        ? cs.primary.withValues(alpha: 0.20)
        : cs.primary.withValues(alpha: 0.14);
    final r = BorderRadius.circular(12);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: base, // 外层始终用同一个“底色”
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: ClipRRect(
        // 确保内部遮罩遵守圆角
        borderRadius: r,
        child: Stack(
          children: [
            // 全选时：在“同一个底色”上叠加一层 sel（与单选的叠加路径一致）
            if (allSelected)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(color: sel, borderRadius: r),
                ),
              ),
            Row(
              children: [
                for (int i = 0; i < options.length; i++)
                  Expanded(
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () => onChanged(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          // 全选时子项透明，让上面的整条遮罩生效；
                          // 非全选时按原逻辑逐项着色
                          color: allSelected
                              ? Colors.transparent
                              : (isSelected[i] ? sel : Colors.transparent),
                          borderRadius: selectedCount == 1 && isSelected[i]
                              ? r
                              : i == 0
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                )
                              : (i == options.length - 1
                                    ? const BorderRadius.only(
                                        topRight: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      )
                                    : BorderRadius.zero),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isSelected[i])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Lucide.Check,
                                  size: 16,
                                  color: cs.primary,
                                ),
                              ),
                            Text(
                              options[i],
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: AppFontWeights.semibold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderKV {
  final TextEditingController name = TextEditingController();
  final TextEditingController value = TextEditingController();
}

class _BodyKV {
  final TextEditingController keyCtrl = TextEditingController();
  final TextEditingController valueCtrl = TextEditingController();
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.kv, required this.onDelete});
  final _HeaderKV kv;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: kv.name,
                  decoration: InputDecoration(
                    hintText: l10n.modelDetailSheetHeaderKeyHint,
                    filled: true,
                    fillColor: context.appColors.surfaceCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: cs.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
              IosIconButton(
                icon: Lucide.Trash2,
                size: 20,
                color: cs.onSurface.withValues(alpha: 0.8),
                onTap: onDelete,
                semanticLabel: AppLocalizations.of(context)!.moruDeleteHeader,
                minSize: 40,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: kv.value,
            decoration: InputDecoration(
              hintText: l10n.modelDetailSheetHeaderValueHint,
              filled: true,
              fillColor: context.appColors.surfaceCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  const _BodyRow({required this.kv, required this.onDelete});
  final _BodyKV kv;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: kv.keyCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.modelDetailSheetBodyKeyHint,
                    filled: true,
                    fillColor: context.appColors.surfaceCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
              IosIconButton(
                icon: Lucide.Trash2,
                size: 20,
                color: cs.onSurface.withValues(alpha: 0.8),
                onTap: onDelete,
                semanticLabel: AppLocalizations.of(context)!.moruDeleteEntry,
                minSize: 40,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: kv.valueCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: l10n.modelDetailSheetBodyJsonHint,
              filled: true,
              fillColor: context.appColors.surfaceCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.title,
    required this.desc,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String desc;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isDisabled = onChanged == null;
    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: Material(
        color: context.appColors.surfaceFill,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              IosSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlinedAddButton extends StatelessWidget {
  const _OutlinedAddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = BorderSide(color: cs.primary.withValues(alpha: 0.5));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Lucide.Plus, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

class _CopySuffixButton extends StatefulWidget {
  const _CopySuffixButton({
    required this.onTap,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.hoverColor,
    required this.pressedColor,
  });
  final VoidCallback onTap;
  final String tooltip;
  final IconData icon;
  final Color color;
  final Color hoverColor;
  final Color pressedColor;

  @override
  State<_CopySuffixButton> createState() => _CopySuffixButtonState();
}

class _CopySuffixButtonState extends State<_CopySuffixButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = _pressed
        ? widget.pressedColor
        : (_hover ? widget.hoverColor : Colors.transparent);
    final icon = Icon(widget.icon, size: 18, color: widget.color);

    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: icon,
    );

    child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: child,
      ),
    );

    return Tooltip(message: widget.tooltip, child: child);
  }
}

// Segmented tab bar matching provider add sheet style
class _SegTabBar extends StatelessWidget {
  const _SegTabBar({required this.controller, required this.tabs});
  final TabController controller;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    const double outerHeight = 44;
    const double innerPadding = 4;
    const double gap = 6;
    const double minSegWidth = 88;
    final double pillRadius = 18;
    final double innerRadius = ((pillRadius - innerPadding).clamp(
      0.0,
      pillRadius,
    )).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availWidth = constraints.maxWidth;
        final double innerAvailWidth = availWidth - innerPadding * 2;
        final double segWidth =
            (innerAvailWidth - gap * (tabs.length - 1)) / tabs.length;
        final double rowWidth =
            segWidth * tabs.length + gap * (tabs.length - 1);

        final Color shellBg = isDark
            ? context.appColors.surfaceFill
            : context.appColors.surfaceCard;

        List<Widget> children = [];
        for (int index = 0; index < tabs.length; index++) {
          final bool selected = controller.index == index;
          children.add(
            SizedBox(
              width: segWidth < minSegWidth ? minSegWidth : segWidth,
              height: double.infinity,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.index = index,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(innerRadius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tabs[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.82),
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ),
            ),
          );
          if (index != tabs.length - 1) {
            children.add(const SizedBox(width: gap));
          }
        }

        return Container(
          height: outerHeight,
          decoration: BoxDecoration(
            color: shellBg,
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.all(innerPadding),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: innerAvailWidth),
                child: SizedBox(
                  width: rowWidth,
                  child: Row(children: children),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
