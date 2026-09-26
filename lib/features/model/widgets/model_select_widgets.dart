part of 'model_select_sheet.dart';

class _ProviderChip extends StatefulWidget {
  const _ProviderChip({
    super.key,
    required this.avatar,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.borderColor,
    this.selected = false,
  });
  final Widget avatar;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
  final bool selected;

  @override
  State<_ProviderChip> createState() => _ProviderChipState();
}

class _ProviderChipState extends State<_ProviderChip> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSelected = widget.selected;
    // Subtle background tint when selected (less conspicuous)
    final Color baseBg = isSelected
        ? (isDark
              ? cs.primary.withValues(alpha: 0.08)
              : cs.primary.withValues(alpha: 0.05))
        : sheetTileColor(context);
    final Color overlay = cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.05);
    final Color bg = _pressed ? Color.alphaBlend(overlay, baseBg) : baseBg;
    // Slightly stronger border when selected; keep label color unchanged for subtlety
    final Color borderColor =
        widget.borderColor ?? cs.outlineVariant.withValues(alpha: 0.25);
    final Color labelColor = cs.onSurface;
    return Semantics(
      label: widget.label,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.avatar,
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.medium,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderGroup {
  final String name;
  final List<_ModelItem> items;
  _ProviderGroup({required this.name, required this.items});
}

class _ModelItem {
  final String providerKey;
  final String providerName;
  final String id;
  final ModelInfo info;
  final bool pinned;
  final bool selected;
  final String? asset; // pre-resolved avatar asset for performance
  _ModelItem({
    required this.providerKey,
    required this.providerName,
    required this.id,
    required this.info,
    this.pinned = false,
    this.selected = false,
    this.asset,
  });
  _ModelItem copyWith({bool? pinned, bool? selected}) => _ModelItem(
    providerKey: providerKey,
    providerName: providerName,
    id: id,
    info: info,
    pinned: pinned ?? this.pinned,
    selected: selected ?? this.selected,
    asset: asset,
  );
}

// Virtualization entry: fixed height + lazy builder
// Rows for flattened list
abstract class _ListRow {}

class _HeaderRow extends _ListRow {
  final String title;
  final String? providerKey;
  final bool isFavorites;
  _HeaderRow(this.title, {this.providerKey, this.isFavorites = false});
}

class _ModelRow extends _ListRow {
  final _ModelItem item;
  final bool showProviderLabel;
  _ModelRow(this.item, {this.showProviderLabel = false});
}

/// The "follow the tier above" row. Selecting it clears the override rather
/// than picking a model.
/// The "follow assistant" action. Deliberately not selectable: it undoes a pin
/// rather than being one of the things you can pick.
class _InheritRow extends _ListRow {
  final String label;
  _InheritRow(this.label);
}

// Reuse badges and avatars similar to provider detail
class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20, this.assetOverride});
  final String name;
  final double size;
  final String? assetOverride;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = assetOverride ?? BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint =
            (dark && BrandAssets.assetNeedsDarkInvert(asset))
            ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: isDark ? 0.18 : 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}
