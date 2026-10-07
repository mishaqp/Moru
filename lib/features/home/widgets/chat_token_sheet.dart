import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/services/model_catalog/model_catalog.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/section_card.dart';
import '../../chat/widgets/token_display_widget.dart';

/// Tokens a chat has spent so far: every reply that reported usage, older
/// versions included, since those requests were paid for too.
class ChatTokenSummary {
  const ChatTokenSummary({
    required this.input,
    required this.output,
    required this.cached,
    required this.replies,
    this.cost,
    this.costComplete = true,
  });

  final int input;
  final int output;

  /// Of [input], read from the provider's prompt cache.
  final int cached;

  /// Replies that reported usage.
  final int replies;

  /// Dollars, for the replies whose model has a price; null for none.
  final double? cost;

  /// False when some replies had no price, so [cost] is a lower bound.
  final bool costComplete;

  static ChatTokenSummary of(
    Iterable<ChatMessage> messages, {
    ModelCatalogEntry? Function(String? providerId, String modelId)? priceFor,
  }) {
    var input = 0, output = 0, cached = 0, replies = 0;
    double? cost;
    var costComplete = true;
    for (final message in messages) {
      if (message.role != 'assistant') continue;
      final prompt = message.promptTokens ?? 0;
      final completion = message.completionTokens ?? 0;
      if (prompt == 0 && completion == 0) continue;
      final fromCache = message.cachedTokens ?? 0;
      input += prompt;
      output += completion;
      cached += fromCache;
      replies++;
      final model = message.modelId;
      final price = model == null
          ? null
          : priceFor
                ?.call(message.providerId, model)
                ?.cost(input: prompt, output: completion, cached: fromCache);
      if (price == null) {
        costComplete = false;
      } else {
        cost = (cost ?? 0) + price;
      }
    }
    return ChatTokenSummary(
      input: input,
      output: output,
      cached: cached,
      replies: replies,
      cost: cost,
      costComplete: costComplete,
    );
  }
}

/// The context ring's details: how full the context is and what the chat
/// has spent.
Future<void> showChatTokenSheet(
  BuildContext context, {
  required int? usedTokens,
  required int? windowTokens,
  required int? maxOutputTokens,
  required ChatTokenSummary summary,
}) {
  final l10n = AppLocalizations.of(context)!;
  String tokens(int value) => TokenStatsRow.compact(value);
  return showCustomBottomSheet<void>(
    context: context,
    title: l10n.chatTokensTitle,
    partialHeightFactor: 0.6,
    builder: (context, scrollController) => ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        IosSectionHeader(text: l10n.chatTokensContext, first: true),
        SectionCard(
          dividers: true,
          children: [
            IosNavRow(
              icon: Lucide.Gauge,
              label: l10n.chatTokensContextUsed,
              detailText: usedTokens == null
                  ? '—'
                  : windowTokens == null || windowTokens <= 0
                  ? tokens(usedTokens)
                  : '${tokens(usedTokens)} · '
                        '${(usedTokens * 100 / windowTokens).round()}%',
            ),
            IosNavRow(
              icon: Lucide.Maximize2,
              label: l10n.chatTokensContextWindow,
              detailText: windowTokens == null ? '—' : tokens(windowTokens),
            ),
            if (maxOutputTokens != null)
              IosNavRow(
                icon: Lucide.ArrowUpToLine,
                label: l10n.chatTokensMaxOutput,
                detailText: tokens(maxOutputTokens),
              ),
          ],
        ),
        IosSectionHeader(text: l10n.chatTokensSpent),
        SectionCard(
          dividers: true,
          children: [
            IosNavRow(
              icon: Lucide.ArrowDownToLine,
              label: l10n.chatTokensInput,
              detailText: tokens(summary.input),
            ),
            IosNavRow(
              icon: Lucide.ArrowUpFromLine,
              label: l10n.chatTokensOutput,
              detailText: tokens(summary.output),
            ),
            IosNavRow(
              icon: Lucide.DatabaseZap,
              label: l10n.chatTokensCached,
              detailText: summary.input == 0
                  ? tokens(summary.cached)
                  : '${tokens(summary.cached)} · '
                        '${(summary.cached * 100 / summary.input).round()}%',
            ),
            IosNavRow(
              icon: Lucide.MessagesSquare,
              label: l10n.chatTokensReplies,
              detailText: '${summary.replies}',
            ),
            if (summary.cost case final cost?)
              IosNavRow(
                icon: Lucide.DollarSign,
                label: l10n.chatTokensCost,
                detailText:
                    '${summary.costComplete ? '' : '≥ '}'
                    '\$${cost < 0.01 ? cost.toStringAsFixed(4) : cost.toStringAsFixed(2)}',
              ),
          ],
        ),
      ],
    ),
  );
}
