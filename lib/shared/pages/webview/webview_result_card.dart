import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';
import '../../widgets/browser_ask_ai_preview_text.dart';
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
/// clamped to three visual lines. The full, unmodified Markdown source is
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
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      visualDensity: VisualDensity.compact,
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
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      visualDensity: VisualDensity.compact,
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
                  maxLines: 3,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(48, 32),
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
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ResultSheet(text: text, conversationId: conversationId),
  );
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.text, this.conversationId});

  final String text;
  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                  Semantics(
                    button: true,
                    label: l10n.commonClose,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: l10n.commonClose,
                      icon: const Icon(Lucide.X, size: 20),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: MarkdownWithCodeHighlight(
                      text: text,
                      conversationId: conversationId,
                      renderImages: false,
                    ),
                  ),
                ),
              ),
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
      ),
    );
  }
}
