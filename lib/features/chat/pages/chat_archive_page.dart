import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../home/controllers/chat_actions.dart';
import '../../home/widgets/swipe_row_action.dart';
import 'chat_history_page.dart';

enum _ArchiveSort { archived, activity }

/// Chats put away from the sidebar. A tap opens one (the page pops with its
/// id, like the history page), a swipe to the right or the button restores
/// it, a long press offers restore and delete.
class ChatArchivePage extends StatefulWidget {
  const ChatArchivePage({super.key, this.assistantId});

  /// The sidebar's assistant: its chats and the ones without an assistant,
  /// the same rows the sidebar shows.
  final String? assistantId;

  static Key rowKey(String id) => ValueKey<String>('archive-row-$id');
  static Key restoreKey(String id) => ValueKey<String>('archive-restore-$id');

  @override
  State<ChatArchivePage> createState() => _ChatArchivePageState();
}

class _ChatArchivePageState extends State<ChatArchivePage> {
  _ArchiveSort _sort = _ArchiveSort.archived;

  Future<void> _restore(Conversation conversation) async {
    final l10n = AppLocalizations.of(context)!;
    Haptics.light();
    await context.read<ChatService>().setConversationsArchived([
      conversation.id,
    ], false);
    if (!mounted) return;
    showAppSnackBar(context, message: l10n.archivePageRestored);
  }

  Future<void> _delete(Conversation conversation) async {
    final l10n = AppLocalizations.of(context)!;
    final chats = context.read<ChatService>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.archivePageDeleteTitle(conversation.title)),
        content: Text(l10n.archivePageDeleteContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.chatHistoryPageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.chatHistoryPageDelete,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ChatActions.cancelActiveGenerationFor(conversation.id);
    await chats.deleteConversation(conversation.id);
  }

  Future<void> _actions(Conversation conversation) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showOptionSheet<String>(
      context,
      title: conversation.title,
      items: [
        OptionSheetItem(
          value: 'restore',
          icon: Lucide.ArchiveRestore,
          label: l10n.archivePageRestore,
        ),
        OptionSheetItem(
          value: 'delete',
          icon: Lucide.Trash2,
          label: l10n.chatHistoryPageDelete,
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'restore':
        await _restore(conversation);
      case 'delete':
        await _delete(conversation);
    }
  }

  Future<void> _chooseSort() async {
    final l10n = AppLocalizations.of(context)!;
    final sort = await showOptionSheet<_ArchiveSort>(
      context,
      title: l10n.archivePageTitle,
      selected: _sort,
      items: [
        OptionSheetItem(
          value: _ArchiveSort.archived,
          icon: Lucide.Archive,
          label: l10n.archivePageSortArchived,
        ),
        OptionSheetItem(
          value: _ArchiveSort.activity,
          icon: Lucide.History,
          label: l10n.archivePageSortActivity,
        ),
      ],
    );
    if (sort != null && mounted) setState(() => _sort = sort);
  }

  Future<void> _openHistory() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChatHistoryPage(assistantId: widget.assistantId),
      ),
    );
    if (id != null && id.isNotEmpty && mounted) {
      Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final chats = context.watch<ChatService>();
    final archived = [
      for (final c in chats.getArchivedConversations())
        if (widget.assistantId == null ||
            c.assistantId == widget.assistantId ||
            c.assistantId == null)
          c,
    ];
    if (_sort == _ArchiveSort.activity) {
      archived.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    final locale = Localizations.localeOf(context);
    final dateFormat = DateFormat.yMMMd(
      DateFormat.localeExists(locale.toLanguageTag())
          ? locale.toLanguageTag()
          : locale.languageCode,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Lucide.ArrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.archivePageTitle),
        actions: [
          IconButton(
            tooltip: _sort == _ArchiveSort.archived
                ? l10n.archivePageSortArchived
                : l10n.archivePageSortActivity,
            icon: const Icon(Lucide.ArrowUpDown),
            onPressed: () => unawaited(_chooseSort()),
          ),
          IconButton(
            tooltip: l10n.chatHistoryPageTitle,
            icon: const Icon(Lucide.History),
            onPressed: () => unawaited(_openHistory()),
          ),
        ],
      ),
      body: archived.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.archivePageEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: archived.length,
              itemBuilder: (context, index) {
                final c = archived[index];
                final when = _sort == _ArchiveSort.archived
                    ? ChatService.archivedAt(c)!
                    : c.updatedAt;
                return Padding(
                  key: ChatArchivePage.rowKey(c.id),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SwipeRowAction(
                    icon: Lucide.ArchiveRestore,
                    label: l10n.archivePageRestore,
                    onSwiped: () => unawaited(_restore(c)),
                    child: IosCardPress(
                      borderRadius: BorderRadius.circular(16),
                      baseColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      haptics: false,
                      onTap: () => Navigator.of(context).pop(c.id),
                      onLongPress: () => unawaited(_actions(c)),
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: AppFontWeights.medium,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateFormat.format(when),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: l10n.archivePageRestore,
                            child: IosIconButton(
                              key: ChatArchivePage.restoreKey(c.id),
                              icon: Lucide.ArchiveRestore,
                              size: 20,
                              color: cs.primary,
                              padding: const EdgeInsets.all(10),
                              onTap: () => unawaited(_restore(c)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
