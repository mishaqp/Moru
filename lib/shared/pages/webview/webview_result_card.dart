import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// Compact "Ask AI" answer card, shown when a
/// `BrowserAskAiOutcome(ok: true)` arrives for the request this browser
/// page is tracking.
///
/// Deliberately dumb: it renders whatever [answerText] it is given and
/// nothing else -- the caller (`webview_page.dart`) is responsible for only
/// ever constructing this with an outcome whose `requestId` (and,
/// defensively, `conversationId`) matches the request this page's own
/// composer is tracking, and for keeping it on screen across later,
/// unrelated `browser_use` activity (a `done` activity must never dismiss
/// this on its own -- only the user's own dismiss, or a new outcome,
/// should).
class BrowserAskAiResultCard extends StatelessWidget {
  const BrowserAskAiResultCard({
    super.key,
    required this.answerText,
    required this.onExpand,
    required this.onCopy,
    required this.onDismiss,
  });

  final String answerText;
  final VoidCallback onExpand;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final preview = answerText.trim();
    return Material(
      key: const ValueKey('browser_ask_ai_result_card'),
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Lucide.MessageSquare, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.browserResultTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.primary,
                    ),
                  ),
                ),
                Tooltip(
                  message: l10n.browserResultCopyTooltip,
                  child: Semantics(
                    button: true,
                    label: l10n.browserResultCopyTooltip,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(Lucide.Copy, size: 16),
                      onPressed: onCopy,
                    ),
                  ),
                ),
                Tooltip(
                  message: l10n.browserResultCloseTooltip,
                  child: Semantics(
                    button: true,
                    label: l10n.browserResultCloseTooltip,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(Lucide.X, size: 16),
                      onPressed: onDismiss,
                    ),
                  ),
                ),
              ],
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 8, 4),
                child: Text(
                  preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onExpand,
                child: Text(l10n.browserResultExpandAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full-text bottom sheet opened from [BrowserAskAiResultCard]'s expand
/// action.
Future<void> showBrowserAskAiResultSheet(BuildContext context, String text) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ResultSheet(text: text),
  );
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.browserResultSheetTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.commonClose,
                  icon: const Icon(Lucide.X, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(child: SingleChildScrollView(child: SelectableText(text))),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Lucide.Copy, size: 16),
                label: Text(l10n.browserResultCopyTooltip),
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
