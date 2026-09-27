part of 'storage_space_page.dart';

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.categories,
    required this.totalBytes,
    required this.colorFor,
  });

  final List<StorageUsageCategory> categories;
  final int totalBytes;
  final Color Function(StorageUsageCategoryKey) colorFor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = categories.where((c) => c.stats.bytes > 0).toList();
    if (items.isEmpty || totalBytes <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 12,
          color: cs.onSurface.withValues(alpha: 0.08),
        ),
      );
    }

    int flexFor(int bytes) {
      final f = ((bytes / totalBytes) * 1000).round();
      return f <= 0 ? 1 : f;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          for (final c in items)
            Expanded(
              flex: flexFor(c.stats.bytes),
              child: Container(height: 12, color: colorFor(c.key)),
            ),
        ],
      ),
    );
  }
}

class _UsageLegend extends StatelessWidget {
  const _UsageLegend({
    required this.categories,
    required this.colorFor,
    required this.titleFor,
  });

  final List<StorageUsageCategory> categories;
  final Color Function(StorageUsageCategoryKey) colorFor;
  final String Function(StorageUsageCategoryKey) titleFor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = categories.where((c) => c.stats.bytes > 0).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final c in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorFor(c.key),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                titleFor(c.key),
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
      ],
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

String _wrapableFilePath(String path) {
  return path.replaceAllMapped(RegExp(r'[/\\]'), (m) => '${m[0]}\u200B');
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

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String detailText,
  Widget? trailing,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return IosCardPress(
    onTap: onTap,
    pressedScale: 1.0,
    borderRadius: BorderRadius.zero,
    baseColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      children: [
        SizedBox(
          width: 36,
          child: Icon(
            icon,
            size: 20,
            color: cs.onSurface.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurface.withValues(alpha: 0.9),
              fontWeight: AppFontWeights.medium,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            detailText,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing,
          const SizedBox(width: 6),
        ],
        Icon(
          Lucide.ChevronRight,
          size: 16,
          color: cs.onSurface.withValues(alpha: 0.75),
        ),
      ],
    ),
  );
}
