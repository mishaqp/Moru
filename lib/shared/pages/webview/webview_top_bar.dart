import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

/// The single address surface for the browser page: a close button, one
/// compact address area (domain, plus a short page title only when it says
/// something the domain doesn't), and an overflow menu. No second,
/// separately-visible address bar exists anywhere else in the page.
///
/// [onTapAddress], [onCopyLink] and [onOpenExternally] are null in HTML
/// preview mode (`contentBase64`, no real navigable URL); [onShowActivityLog]
/// and [onOpenSettings] are null when `agentSession` is false, since an
/// activity log and per-action browser settings are agent-only concepts.
class WebViewTopBar extends StatelessWidget implements PreferredSizeWidget {
  const WebViewTopBar({
    super.key,
    required this.currentUrl,
    required this.title,
    required this.onClose,
    this.onMinimize,
    this.onTapAddress,
    this.onCopyLink,
    this.onOpenExternally,
    this.onShowActivityLog,
    this.onOpenSettings,
    required this.onShowConsole,
    this.progress,
    this.tabCount,
    this.onShowTabs,
    this.desktopMode,
    this.onDesktopModeChanged,
    this.onClearSiteData,
    this.bookmarked,
    this.onToggleBookmark,
    this.onShowBookmarks,
    this.onShowHistory,
    this.onShowUserscripts,
  });

  final VoidCallback? onShowUserscripts;

  /// Whether the page is bookmarked; with [onToggleBookmark], the address
  /// shows a star that adds or removes it.
  final bool? bookmarked;
  final VoidCallback? onToggleBookmark;
  final VoidCallback? onShowBookmarks;
  final VoidCallback? onShowHistory;

  /// Open tabs, shown on the tabs button; agent browser only.
  final int? tabCount;
  final VoidCallback? onShowTabs;

  /// Whether the active tab shows the desktop version of sites; with
  /// [onDesktopModeChanged], the menu offers to switch.
  final bool? desktopMode;
  final ValueChanged<bool>? onDesktopModeChanged;

  /// Signs the open site out of this browser (after a confirmation).
  final VoidCallback? onClearSiteData;

  /// Page load progress from 0 to 1 while loading (0: not known yet), null
  /// when the page has loaded.
  final double? progress;

  final String? currentUrl;
  final String? title;
  final VoidCallback onClose;

  /// Shrinks the page into the floating mini window; agent sessions only.
  final VoidCallback? onMinimize;
  final VoidCallback? onTapAddress;
  final VoidCallback? onCopyLink;
  final VoidCallback? onOpenExternally;
  final VoidCallback? onShowActivityLog;
  final VoidCallback? onOpenSettings;
  final VoidCallback onShowConsole;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final rawUrl = currentUrl?.trim() ?? '';
    final uri = rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);
    final domain = (uri?.host.isNotEmpty ?? false) ? uri!.host : rawUrl;
    final trimmedTitle = title?.trim() ?? '';
    final showSubtitle = trimmedTitle.isNotEmpty && trimmedTitle != domain;
    final secure = uri?.scheme == 'https';

    final addressContent = Row(
      children: [
        if (domain.isNotEmpty) ...[
          Icon(
            secure ? Lucide.Lock : Lucide.LockOpen,
            key: const ValueKey('browser_address_lock'),
            size: 14,
            color: secure ? cs.onSurface.withValues(alpha: 0.55) : cs.error,
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
              if (showSubtitle)
                Text(
                  trimmedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    // The address pill: lock, domain and title, with the load progress as a
    // thin line along its bottom edge.
    final pill = Container(
      height: 42,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(21),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  Expanded(
                    child: onTapAddress == null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: addressContent,
                          )
                        : InkWell(
                            key: const ValueKey('browser_address_tap_target'),
                            onTap: onTapAddress,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: addressContent,
                            ),
                          ),
                  ),
                  // Beside the address, not on it: a tap on the address
                  // edits it.
                  if (onToggleBookmark != null)
                    InkWell(
                      key: const ValueKey('browser_bookmark_star'),
                      customBorder: const CircleBorder(),
                      onTap: onToggleBookmark,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
                        child: Icon(
                          Lucide.Star,
                          size: 18,
                          semanticLabel: l10n.browserBookmarks,
                          color: bookmarked == true
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                key: const ValueKey('browser_address_progress'),
                minHeight: 2.5,
                value: progress! > 0 ? progress : null,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );

    return AppBar(
      titleSpacing: 0,
      leading: Tooltip(
        message: l10n.commonClose,
        child: IosIconButton(
          icon: Lucide.X,
          color: cs.onSurface,
          size: 20,
          minSize: 44,
          semanticLabel: l10n.commonClose,
          onTap: onClose,
        ),
      ),
      title: pill,
      actions: [
        if (onMinimize != null)
          IosIconButton(
            key: const ValueKey('browser_minimize'),
            icon: Lucide.Minimize2,
            color: cs.onSurface,
            size: 20,
            minSize: 44,
            semanticLabel: l10n.browserMinimize,
            onTap: onMinimize,
          ),
        if (onShowTabs != null)
          IconButton(
            key: const ValueKey('browser_tabs_button'),
            tooltip: l10n.browserTabsTooltip,
            onPressed: onShowTabs,
            icon: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: cs.onSurface, width: 1.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${tabCount ?? 1}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: l10n.browserMenuTooltip,
          icon: Icon(Lucide.MoreVertical, color: cs.onSurface),
          onSelected: (value) {
            switch (value) {
              case 'copy':
                onCopyLink?.call();
                break;
              case 'open':
                onOpenExternally?.call();
                break;
              case 'activity':
                onShowActivityLog?.call();
                break;
              case 'settings':
                onOpenSettings?.call();
                break;
              case 'console':
                onShowConsole();
                break;
              case 'desktop':
                onDesktopModeChanged?.call(!(desktopMode ?? false));
                break;
              case 'clear':
                onClearSiteData?.call();
                break;
              case 'bookmarks':
                onShowBookmarks?.call();
                break;
              case 'history':
                onShowHistory?.call();
                break;
              case 'userscripts':
                onShowUserscripts?.call();
                break;
            }
          },
          itemBuilder: (ctx) => [
            if (onCopyLink != null)
              PopupMenuItem<String>(
                value: 'copy',
                child: _MenuRow(
                  icon: Lucide.Copy,
                  label: l10n.browserMenuCopyLink,
                ),
              ),
            if (onOpenExternally != null)
              PopupMenuItem<String>(
                value: 'open',
                child: _MenuRow(
                  icon: Lucide.ExternalLink,
                  label: l10n.messageWebViewOpenInBrowser,
                ),
              ),
            if (onShowBookmarks != null)
              PopupMenuItem<String>(
                value: 'bookmarks',
                child: _MenuRow(
                  icon: Lucide.Star,
                  label: l10n.browserBookmarks,
                ),
              ),
            if (onShowHistory != null)
              PopupMenuItem<String>(
                value: 'history',
                child: _MenuRow(
                  icon: Lucide.History,
                  label: l10n.browserHistory,
                ),
              ),
            if (onShowUserscripts != null)
              PopupMenuItem<String>(
                value: 'userscripts',
                child: _MenuRow(
                  icon: Lucide.Code,
                  label: l10n.userscriptsTitle,
                ),
              ),
            if (onDesktopModeChanged != null)
              CheckedPopupMenuItem<String>(
                value: 'desktop',
                checked: desktopMode ?? false,
                child: Text(l10n.browserDesktopSite),
              ),
            if (onClearSiteData != null)
              PopupMenuItem<String>(
                value: 'clear',
                child: _MenuRow(
                  icon: Lucide.Eraser,
                  label: l10n.browserClearSiteData,
                ),
              ),
            if (onShowActivityLog != null)
              PopupMenuItem<String>(
                value: 'activity',
                child: _MenuRow(
                  icon: Lucide.History,
                  label: l10n.browserMenuActivityLog,
                ),
              ),
            if (onOpenSettings != null)
              PopupMenuItem<String>(
                value: 'settings',
                child: _MenuRow(
                  icon: Lucide.Settings,
                  label: l10n.browserMenuSettings,
                ),
              ),
            // Deprioritized: below a divider, last item -- the diagnostics
            // console is a debugging tool, not a primary action.
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'console',
              child: _MenuRow(
                icon: Lucide.Terminal,
                label: l10n.messageWebViewConsoleLogs,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: cs.onSurface.withValues(alpha: 0.75)),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
