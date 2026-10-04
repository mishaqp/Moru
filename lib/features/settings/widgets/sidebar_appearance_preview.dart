import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/models/sidebar_appearance.dart';
import '../../../core/models/sidebar_shortcut.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive/breakpoints.dart';
import '../../home/widgets/sidebar_bottom_bar.dart';
import '../../home/widgets/sidebar_glass.dart';
import '../../home/widgets/sidebar_omni_parts.dart';

/// Uses the same backdrop, cards, headers and dock as the live sidebar.
class SidebarAppearancePreview extends StatefulWidget {
  const SidebarAppearancePreview({
    super.key,
    required this.appearance,
    required this.backgroundConfiguration,
    required this.theme,
    required this.height,
    required this.showThumbnails,
    required this.shortcuts,
    required this.glass,
  });

  final SidebarAppearanceSettings appearance;
  final ChatBackgroundSettings backgroundConfiguration;
  final ThemeData theme;
  final double height;
  final bool showThumbnails;
  final List<SidebarShortcut> shortcuts;
  final bool glass;

  @override
  State<SidebarAppearancePreview> createState() =>
      _SidebarAppearancePreviewState();
}

class _SidebarAppearancePreviewState extends State<SidebarAppearancePreview> {
  final _search = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= AppBreakpoints.tablet;
    final preview = Theme(
      data: widget.theme,
      child: Builder(
        builder: (context) {
          final l = AppLocalizations.of(context)!;
          final cs = Theme.of(context).colorScheme;
          final appearance = widget.appearance;
          final timestamp = MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(const TimeOfDay(hour: 10, minute: 42));
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: widget.height,
              child: ColoredBox(
                color: cs.surfaceContainerLow,
                child: LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      key: const ValueKey('appearanceSidebarPreviewPanel'),
                      width:
                          appearance.widthFor(screenWidth, wide: wide) *
                          constraints.maxWidth /
                          screenWidth,
                      child: IgnorePointer(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SidebarGlassBackdrop(
                              configuration: appearance,
                              backgroundConfiguration:
                                  widget.backgroundConfiguration,
                              viewportSize: constraints.biggest,
                            ),
                            widget.height < 180
                                ? _compactScene(l, cs, timestamp)
                                : Column(
                                    children: [
                                      if (widget.height >= 180)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            12,
                                            12,
                                            8,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: SidebarSearchField(
                                                  controller: _search,
                                                  focusNode: _focus,
                                                  hint: l.sideDrawerSearchHint,
                                                  glass: widget.glass,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SidebarRoundButton(
                                                icon: LucideIcons.plus,
                                                tooltip: l.sideDrawerNewChat,
                                                onTap: () {},
                                                glass: widget.glass,
                                                primary: true,
                                              ),
                                            ],
                                          ),
                                        ),
                                      Expanded(
                                        child: LayoutBuilder(
                                          builder: (context, constraints) => ClipRect(
                                            key: const ValueKey(
                                              'appearanceSidebarPreviewCardViewport',
                                            ),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.topLeft,
                                              child: SizedBox(
                                                width: constraints.maxWidth,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (constraints
                                                                  .maxHeight >=
                                                              120 &&
                                                          appearance.grouping !=
                                                              SidebarGrouping
                                                                  .none)
                                                        SidebarSectionHeader(
                                                          icon:
                                                              appearance
                                                                      .grouping ==
                                                                  SidebarGrouping
                                                                      .date
                                                              ? LucideIcons
                                                                    .calendar
                                                              : LucideIcons.bot,
                                                          label:
                                                              appearance
                                                                      .grouping ==
                                                                  SidebarGrouping
                                                                      .date
                                                              ? l.sideDrawerDateToday
                                                              : l.settingsPageAssistant,
                                                          count:
                                                              constraints
                                                                      .maxHeight >=
                                                                  180
                                                              ? 2
                                                              : 1,
                                                          expanded: true,
                                                          onTap: () {},
                                                        ),
                                                      _currentCard(
                                                        context,
                                                        l,
                                                        timestamp,
                                                      ),
                                                      if (constraints
                                                              .maxHeight >=
                                                          180)
                                                        SidebarConversationCard(
                                                          appearance:
                                                              appearance,
                                                          title: l
                                                              .appearanceSidebarPreviewOtherTitle,
                                                          preview: l
                                                              .appearanceSidebarPreviewMessage,
                                                          timestamp: timestamp,
                                                          assistantName: l
                                                              .settingsPageAssistant,
                                                          modelName: l
                                                              .appearanceSidebarPreviewModel,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (widget.shortcuts.isNotEmpty &&
                                          widget.height >= 220)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            8,
                                            12,
                                            8,
                                          ),
                                          child: LayoutBuilder(
                                            builder: (context, box) => Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                for (final shortcut
                                                    in widget.shortcuts.take(2))
                                                  SizedBox(
                                                    width:
                                                        (box.maxWidth - 8) / 2,
                                                    child: SidebarShortcutCard(
                                                      glass: widget.glass,
                                                      leading: Icon(
                                                        shortcut.web
                                                            ? LucideIcons.globe
                                                            : LucideIcons
                                                                  .layoutGrid,
                                                        size: 20,
                                                      ),
                                                      label:
                                                          sidebarShortcutPreviewLabel(
                                                            l,
                                                            shortcut,
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      _dock(l, cs),
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
      ),
    );
    return SidebarSurfaceScope(
      clear:
          widget.glass ||
          widget.backgroundConfiguration.type != ChatBackgroundType.none ||
          widget.appearance.opacity < 1,
      child: preview,
    );
  }

  Widget _compactScene(AppLocalizations l, ColorScheme cs, String timestamp) =>
      LayoutBuilder(
        builder: (context, constraints) => ClipRect(
          key: const ValueKey('appearanceSidebarPreviewCardViewport'),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _currentCard(context, l, timestamp),
                  ),
                  _dock(l, cs),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _currentCard(
    BuildContext context,
    AppLocalizations l,
    String timestamp,
  ) {
    final appearance = widget.appearance;
    return SidebarConversationCard(
      key: const ValueKey('appearanceSidebarPreviewCurrentCard'),
      appearance: appearance,
      title: l.appearanceSidebarPreviewTitle,
      isCurrent: true,
      preview: l.appearanceSidebarPreviewMessage,
      timestamp: timestamp,
      assistantName: l.settingsPageAssistant,
      modelName: l.appearanceSidebarPreviewModel,
      thumbnails: widget.showThumbnails ? _thumbnail(context) : null,
    );
  }

  Widget _dock(AppLocalizations l, ColorScheme cs) {
    final appearance = widget.appearance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SidebarDockCapsule(
        glass: widget.glass,
        children: [
          for (final item in appearance.dockItems)
            Tooltip(
              message: sidebarDockLabel(l, item),
              child: Icon(sidebarDockIcon(item), size: 17, color: cs.onSurface),
            ),
        ],
      ),
    );
  }

  Widget _thumbnail(BuildContext context) => Container(
    key: const ValueKey('appearanceSidebarPreviewThumbnail'),
    width: 44,
    height: 32,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: Icon(
      LucideIcons.image,
      size: 18,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    ),
  );
}

String sidebarShortcutPreviewLabel(
  AppLocalizations l,
  SidebarShortcut shortcut,
) {
  if (!shortcut.web) {
    return MiniAppStore.instance.byId(shortcut.target)?.name ?? l.miniAppsTitle;
  }
  if (shortcut.title.trim().isNotEmpty) return shortcut.title.trim();
  return Uri.tryParse(shortcut.target)?.host ?? l.browserBookmarks;
}
