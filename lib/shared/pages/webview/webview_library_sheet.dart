import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_library.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// The bookmarks ([history] false) or the history, with a search field.
/// Tapping a page calls [onOpen] with its address.
Future<void> showBrowserLibrarySheet(
  BuildContext context, {
  required bool history,
  required ValueChanged<String> onOpen,
}) {
  unawaited(BrowserLibrary.instance.load());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BrowserLibrarySheet(history: history, onOpen: onOpen),
  );
}

class BrowserLibrarySheet extends StatefulWidget {
  const BrowserLibrarySheet({
    super.key,
    required this.history,
    required this.onOpen,
  });

  static const Key searchKey = ValueKey<String>('browser-library-search');
  static const Key clearKey = ValueKey<String>('browser-library-clear');
  static Key removeKey(String url) =>
      ValueKey<String>('browser-library-x-$url');

  final bool history;
  final ValueChanged<String> onOpen;

  @override
  State<BrowserLibrarySheet> createState() => _BrowserLibrarySheetState();
}

class _BrowserLibrarySheetState extends State<BrowserLibrarySheet> {
  String _query = '';

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.browserClearHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.browserClearHistory),
          ),
        ],
      ),
    );
    if (confirmed == true) await BrowserLibrary.instance.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final library = BrowserLibrary.instance;
    final source = widget.history ? library.history : library.bookmarks;
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.history
                          ? l10n.browserHistory
                          : l10n.browserBookmarks,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (widget.history)
                    TextButton(
                      key: BrowserLibrarySheet.clearKey,
                      onPressed: () => unawaited(_confirmClear()),
                      child: Text(l10n.browserClearHistory),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: BrowserLibrarySheet.searchKey,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Lucide.Search, size: 18),
                  hintText: l10n.browserLibrarySearch,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<List<BrowserPageEntry>>(
                  valueListenable: source,
                  builder: (context, entries, _) {
                    final shown = [
                      for (final entry in entries)
                        if (entry.matches(_query)) entry,
                    ];
                    if (shown.isEmpty) {
                      return Center(
                        child: Text(
                          widget.history
                              ? l10n.browserHistoryEmpty
                              : l10n.browserBookmarksEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) => _EntryRow(
                        entry: shown[index],
                        history: widget.history,
                        onOpen: () {
                          Navigator.of(context).pop();
                          widget.onOpen(shown[index].url);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.history,
    required this.onOpen,
  });

  final BrowserPageEntry entry;
  final bool history;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final host = Uri.tryParse(entry.url)?.host ?? entry.url;
    final time = TimeOfDay.fromDateTime(entry.time).format(context);
    final library = BrowserLibrary.instance;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
        child: Row(
          children: [
            Icon(
              history ? Lucide.History : Lucide.Star,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isNotEmpty ? entry.title : host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: AppFontWeights.semibold),
                  ),
                  Text(
                    history ? '$host · $time' : host,
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
              key: BrowserLibrarySheet.removeKey(entry.url),
              tooltip: l10n.browserLibraryRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Lucide.X, size: 18),
              onPressed: () => unawaited(
                history
                    ? library.removeFromHistory(entry.url)
                    : library.removeBookmark(entry.url),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
