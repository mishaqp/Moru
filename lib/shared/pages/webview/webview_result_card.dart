import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';
import '../../widgets/browser_ask_ai_preview_text.dart';
import '../../widgets/custom_bottom_sheet.dart';
import '../../widgets/markdown_with_highlight.dart';

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
///
/// The preview is a plain-text rendering of [answerText] -- Markdown
/// markers (`**bold**`, backticks, `#` headings, ...) never leak into it --
/// clamped to two visual lines. The full, unmodified Markdown source is
/// only ever shown (and copied) via [onExpand]'s full-answer sheet.
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
    final preview = browserAskAiPreviewPlainText(answerText);
    return Material(
      key: const ValueKey('browser_ask_ai_result_card'),
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Lucide.MessageSquare, size: 13, color: cs.primary),
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
                        minWidth: 44,
                        minHeight: 44,
                        maxWidth: 44,
                        maxHeight: 44,
                      ),
                      visualDensity: VisualDensity.standard,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Lucide.Copy, size: 15),
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
                        minWidth: 44,
                        minHeight: 44,
                        maxWidth: 44,
                        maxHeight: 44,
                      ),
                      visualDensity: VisualDensity.standard,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Lucide.X, size: 15),
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
                padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                child: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.3),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 32),
                  foregroundColor: cs.primary,
                  alignment: Alignment.centerLeft,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onExpand,
                child: Text(
                  l10n.browserResultExpandAction,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full-text bottom sheet opened from [BrowserAskAiResultCard]'s expand
/// action. Renders [text] through the app's own chat Markdown renderer
/// (bold/italic, lists, links, inline code, fenced code, blockquotes) --
/// the same one chat messages use -- rather than a plain [Text]/
/// [SelectableText], so the answer reads the way the model actually
/// formatted it. Deliberately does not wire up the heavier parts of a real
/// chat message this answer never needs (regenerate menu, tool cards,
/// reasoning, version switching): it is one fixed block of finished text.
/// Images never auto-fetch here ([MarkdownWithCodeHighlight.renderImages]
/// is false) -- opening this sheet must never trigger a surprise network
/// request just to preview an answer.
Future<void> showBrowserAskAiResultSheet(
  BuildContext context,
  String text, {
  String? conversationId,
}) {
  return showCustomBottomSheet<void>(
    context: context,
    title: AppLocalizations.of(context)!.browserResultSheetTitle,
    partialHeightFactor: 0.85,
    expandedHeightFactor: 0.85,
    headerBuilder: (context, onClose) => Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.browserResultSheetTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: CustomBottomSheet.closeButtonKey,
            tooltip: AppLocalizations.of(context)!.commonClose,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            visualDensity: VisualDensity.standard,
            icon: const Icon(Lucide.X, size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    ),
    builder: (ctx, scrollController) => _ResultSheet(
      text: text,
      conversationId: conversationId,
      scrollController: scrollController,
    ),
  );
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.text,
    this.conversationId,
    required this.scrollController,
  });

  final String text;
  final String? conversationId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        SelectionArea(
          child: MarkdownWithCodeHighlight(
            text: text,
            conversationId: conversationId,
            renderImages: false,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            icon: const Icon(Lucide.Copy, size: 16),
            label: Text(l10n.browserResultCopyTooltip),
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          ),
        ),
      ],
    );
  }
}
