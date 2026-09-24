import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
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
  });

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

    final addressContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (domain.isNotEmpty) ...[
              Icon(
                secure ? Lucide.Lock : Lucide.LockOpen,
                size: 13,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        if (showSubtitle)
          Text(
            trimmedTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
      ],
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
      title: onTapAddress == null
          ? addressContent
          : InkWell(
              key: const ValueKey('browser_address_tap_target'),
              borderRadius: BorderRadius.circular(10),
              onTap: onTapAddress,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: addressContent,
              ),
            ),
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
