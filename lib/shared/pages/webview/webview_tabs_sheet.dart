import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_tabs.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// The page a tab the user opens starts with.
const String browserStartPage = 'https://www.google.com';

/// Opens the list of the shared browser's tabs: switch, close, open a new
/// one or close them all. It follows the tabs live while open.
Future<void> showBrowserTabsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const BrowserTabsSheet(),
  );
}

class BrowserTabsSheet extends StatelessWidget {
  const BrowserTabsSheet({super.key});

  static const Key newTabKey = ValueKey<String>('browser-tabs-new');
  static const Key closeAllKey = ValueKey<String>('browser-tabs-close-all');
  static Key tabKey(String id) => ValueKey<String>('browser-tab-$id');
  static Key closeKey(String id) => ValueKey<String>('browser-tab-close-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = BrowserAgentSession.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ValueListenableBuilder<List<BrowserTabInfo>>(
          valueListenable: session.tabs,
          builder: (context, tabs, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                child: Text(
                  l10n.browserTabsTitle(tabs.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final tab in tabs) _TabRow(tab: tab)],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: closeAllKey,
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(session.close());
                      },
                      icon: const Icon(Lucide.X, size: 18),
                      label: Text(l10n.browserCloseAllTabs),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: newTabKey,
                      onPressed: tabs.length >= BrowserAgentSession.maxTabs
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              unawaited(session.newTab(url: browserStartPage));
                            },
                      icon: const Icon(Lucide.Plus, size: 18),
                      label: Text(l10n.browserNewTab),
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

class _TabRow extends StatelessWidget {
  const _TabRow({required this.tab});

  final BrowserTabInfo tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final session = BrowserAgentSession.instance;
    final uri = Uri.tryParse(tab.url ?? '');
    final host = (uri?.host.isNotEmpty ?? false)
        ? uri!.host.replaceFirst(RegExp(r'^www\.'), '')
        : l10n.browserNewTab;
    final title = (tab.title?.trim().isNotEmpty ?? false) ? tab.title! : host;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: tab.active
            ? cs.primaryContainer.withValues(alpha: 0.7)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: BrowserTabsSheet.tabKey(tab.id),
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).pop();
            unawaited(session.switchTab(tab.id));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  tab.desktop ? Lucide.Monitor : Lucide.Globe,
                  size: 18,
                  color: tab.active ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        tab.byAgent
                            ? '$host · ${l10n.browserTabByAssistant}'
                            : host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: BrowserTabsSheet.closeKey(tab.id),
                  tooltip: l10n.commonClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Lucide.X, size: 18),
                  onPressed: () {
                    // The last tab closes the browser page under the sheet.
                    if (session.tabs.value.length == 1) {
                      Navigator.of(context).pop();
                    }
                    unawaited(session.closeTab(tab.id));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
