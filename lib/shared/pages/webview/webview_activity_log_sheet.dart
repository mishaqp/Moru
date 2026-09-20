import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../features/home/services/browser_agent_actions.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';

/// Opens the browser activity log as a modal sheet, reactive for as long as
/// it stays open: it reads [BrowserAgentSession.recentActivityNotifier]
/// directly (already reactive at the session level since Phase A), so newly
/// recorded or resolved activity appears without the user closing and
/// reopening the sheet.
///
/// Reachable at any time from the bottom panel's activity-log button, not
/// only while the agent is currently busy -- the log stays useful to review
/// after a task finishes.
Future<void> showActivityLogSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const ActivityLogSheet(),
  );
}

class ActivityLogSheet extends StatelessWidget {
  const ActivityLogSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.browserActivityLogTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ValueListenableBuilder<List<BrowserActivity>>(
                valueListenable:
                    BrowserAgentSession.instance.recentActivityNotifier,
                builder: (context, activities, _) {
                  if (activities.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        l10n.browserActivityLogEmpty,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  final entries = activities.reversed.toList();
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (c, i) =>
                        _ActivityRow(activity: entries[i], ru: ru),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.ru});

  final BrowserActivity activity;
  final bool ru;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (activity.outcome) {
      BrowserActivityOutcome.running => (Lucide.RefreshCw, cs.primary),
      BrowserActivityOutcome.ok => (Lucide.CheckCircle, cs.primary),
      BrowserActivityOutcome.failed => (Lucide.CircleX, cs.error),
      BrowserActivityOutcome.notFound => (
        Lucide.SearchX,
        cs.onSurface.withValues(alpha: 0.6),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              browserActivityLabel(activity, ru: ru),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
