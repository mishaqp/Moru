// Sidebar pieces ported from OpenOmniBot's home drawer
// (https://github.com/omnimind-ai/OpenOmniBot, ui/lib/features/home/widgets/
// home_drawer*.dart, conversation_slidable.dart), used here under its
// AGPL-3.0 terms for non-commercial personal use. Sizes, type and layout
// follow OmniBot; colors come from the Moru theme.

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// OmniBot's `surfaceSecondary`: the fill of the search field, the round
/// buttons, the shortcut cards and the dock, a step above the panel.
Color sidebarSecondarySurface(BuildContext context, {required bool glass}) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (glass) return cs.surface.withValues(alpha: dark ? 0.34 : 0.55);
  return dark
      ? Color.lerp(cs.surface, cs.onSurface, 0.07)!
      : Color.lerp(cs.surface, cs.onSurface, 0.04)!;
}

/// OmniBot's `surfaceElevated`, one more step up (the focused search field,
/// the quieter swipe buttons).
Color sidebarElevatedSurface(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color.lerp(cs.surface, cs.onSurface, dark ? 0.12 : 0.08)!;
}

/// OmniBot's `textTertiary`, for section headers and hints.
Color sidebarTertiaryText(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);

/// The 36 dp search pill of OmniBot's drawer.
class SidebarSearchField extends StatelessWidget {
  const SidebarSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.glass,
    this.leading,
    this.onLeadingTap,
    this.trailing,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool glass;

  /// The icon at the start; tapping it runs [onLeadingTap] when set.
  final Widget? leading;
  final VoidCallback? onLeadingTap;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  static const double height = 36;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: focusNode, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final cs = Theme.of(context).colorScheme;
    final focused = focusNode.hasFocus;
    final background = focused && !glass
        ? Color.lerp(
            sidebarSecondarySurface(context, glass: glass),
            sidebarElevatedSurface(context),
            0.9,
          )!
        : sidebarSecondarySurface(context, glass: glass);
    final iconColor = focused
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.7);
    final leadingIcon = IconTheme.merge(
      data: IconThemeData(size: 18, color: iconColor),
      child: leading ?? Icon(LucideIcons.search, size: 18, color: iconColor),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(height / 2),
        border: glass
            ? Border.all(
                color: cs.onSurface.withValues(alpha: 0.08),
                width: 0.8,
              )
            : null,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onTapOutside: (_) => focusNode.unfocus(),
        textInputAction: textInputAction ?? TextInputAction.search,
        onSubmitted: onSubmitted,
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurface,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
        cursorColor: cs.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 13,
            color: sidebarTertiaryText(context),
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: height,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: height,
          ),
          prefixIcon: onLeadingTap == null
              ? leadingIcon
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLeadingTap,
                  child: Center(widthFactor: 1, child: leadingIcon),
                ),
          suffixIcon: trailing,
        ),
      ),
    );
  }
}

/// The 32 dp round buttons next to OmniBot's search (archive, new chat).
class SidebarRoundButton extends StatelessWidget {
  const SidebarRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.glass,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool glass;
  final bool primary;

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: primary
                  ? cs.primary
                  : sidebarSecondarySurface(context, glass: glass),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 16,
              color: primary ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// A section header of OmniBot's list: a small icon, the label, the count;
/// a tap folds the section.
class SidebarSectionHeader extends StatelessWidget {
  const SidebarSectionHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tertiary = sidebarTertiaryText(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: cs.primary.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: Semantics(
            button: true,
            toggled: expanded,
            child: Container(
              constraints: const BoxConstraints(minHeight: 28),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 14,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(icon, size: 14, color: tertiary),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: tertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: tertiary.withValues(alpha: 0.82 * tertiary.a),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// OmniBot's date header icons: a stable, playful Lucide icon per day.
const List<IconData> _dateIcons = <IconData>[
  LucideIcons.amphora,
  LucideIcons.apple,
  LucideIcons.banana,
  LucideIcons.barrel,
  LucideIcons.bean,
  LucideIcons.beef,
  LucideIcons.beer,
  LucideIcons.bird,
  LucideIcons.birdhouse,
  LucideIcons.blender,
  LucideIcons.bone,
  LucideIcons.bottleWine,
  LucideIcons.broccoli,
  LucideIcons.bugPlay,
  LucideIcons.bug,
  LucideIcons.cakeSlice,
  LucideIcons.cake,
  LucideIcons.candyCane,
  LucideIcons.candy,
  LucideIcons.carrot,
  LucideIcons.cat,
  LucideIcons.chefHat,
  LucideIcons.cherry,
  LucideIcons.citrus,
  LucideIcons.coffee,
  LucideIcons.cookie,
  LucideIcons.cookingPot,
  LucideIcons.croissant,
  LucideIcons.cuboid,
  LucideIcons.cupSoda,
  LucideIcons.dessert,
  LucideIcons.dog,
  LucideIcons.donut,
  LucideIcons.drumstick,
  LucideIcons.eggFried,
  LucideIcons.egg,
  LucideIcons.fishSymbol,
  LucideIcons.fish,
  LucideIcons.glassWater,
  LucideIcons.grape,
  LucideIcons.ham,
  LucideIcons.hamburger,
  LucideIcons.handPlatter,
  LucideIcons.hop,
  LucideIcons.iceCreamBowl,
  LucideIcons.iceCreamCone,
  LucideIcons.leafyGreen,
  LucideIcons.lollipop,
  LucideIcons.martini,
  LucideIcons.microwave,
  LucideIcons.milk,
  LucideIcons.nut,
  LucideIcons.origami,
  LucideIcons.panda,
  LucideIcons.pawPrint,
  LucideIcons.pizza,
  LucideIcons.popcorn,
  LucideIcons.popsicle,
  LucideIcons.rabbit,
  LucideIcons.rat,
  LucideIcons.refrigerator,
  LucideIcons.salad,
  LucideIcons.sandwich,
  LucideIcons.shell,
  LucideIcons.shrimp,
  LucideIcons.snail,
  LucideIcons.soup,
  LucideIcons.squirrel,
  LucideIcons.torus,
  LucideIcons.tractor,
  LucideIcons.turtle,
  LucideIcons.utensilsCrossed,
  LucideIcons.utensils,
  LucideIcons.vegan,
  LucideIcons.wheat,
  LucideIcons.wine,
  LucideIcons.worm,
];

/// Picks the icon of the section [key], the same one every time, and a
/// different one from each key already in [used] while any are left.
IconData sidebarSectionIcon(String key, Set<int> used) {
  var index = _stableHash(key) % _dateIcons.length;
  if (used.length < _dateIcons.length) {
    while (!used.add(index)) {
      index = (index + 1) % _dateIcons.length;
    }
  }
  return _dateIcons[index];
}

/// FNV-1a, so the icon of a day survives restarts (String.hashCode may not).
int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// A chat row that swipes to the left, as in OmniBot: delete, pin, copy and
/// archive buttons behind it, and a full swipe archives.
class SidebarChatSlidable extends StatelessWidget {
  const SidebarChatSlidable({
    super.key,
    required this.itemKey,
    required this.enabled,
    required this.pinned,
    required this.onDelete,
    required this.onPin,
    required this.onCopy,
    required this.onArchive,
    required this.child,
  });

  final String itemKey;
  final bool enabled;
  final bool pinned;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onCopy;
  final VoidCallback onArchive;
  final Widget child;

  static const Object groupTag = 'sidebar-conversations';
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final cs = Theme.of(context).colorScheme;
    final elevated = sidebarElevatedSurface(context);
    CustomSlidableAction action({
      required VoidCallback onPressed,
      required Color color,
      required IconData icon,
      BorderRadius radius = BorderRadius.zero,
    }) => CustomSlidableAction(
      onPressed: (_) => onPressed(),
      backgroundColor: color,
      borderRadius: radius,
      padding: EdgeInsets.zero,
      child: Center(
        child: Icon(icon, size: _iconSize, color: Colors.white),
      ),
    );
    const actions = 4;
    const extent = 0.24 * actions;
    return Slidable(
      key: ValueKey<String>(itemKey),
      groupTag: groupTag,
      closeOnScroll: true,
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: extent,
        dismissible: DismissiblePane(
          dismissThreshold: 0.95,
          closeOnCancel: true,
          motion: const InversedDrawerMotion(),
          onDismissed: onArchive,
        ),
        children: [
          action(
            onPressed: onDelete,
            color: const Color(0xFFE05252),
            icon: LucideIcons.trash2,
          ),
          action(
            onPressed: onPin,
            color: Color.lerp(elevated, cs.primary, 0.18)!,
            icon: pinned ? LucideIcons.pinOff : LucideIcons.pin,
          ),
          action(onPressed: onCopy, color: elevated, icon: LucideIcons.copy),
          action(
            onPressed: onArchive,
            color: Color.lerp(elevated, cs.primary, 0.3)!,
            icon: LucideIcons.archive,
            radius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
        ],
      ),
      child: child,
    );
  }
}
