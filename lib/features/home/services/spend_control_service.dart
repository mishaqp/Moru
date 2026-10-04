import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/model_context_window.dart';
import '../../../core/models/spend_limits.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_helpers.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/model_catalog/model_catalog.dart';
import '../utils/model_display_helper.dart';
import '../widgets/chat_token_sheet.dart';

class SpendControlStatus {
  const SpendControlStatus({
    required this.chat,
    required this.today,
    required this.limits,
    required this.day,
    this.contextTokens,
    this.contextWindow,
  });

  final ChatTokenSummary chat;
  final ChatTokenSummary today;
  final SpendLimits limits;
  final DateTime day;
  final int? contextTokens;
  final int? contextWindow;

  static int total(ChatTokenSummary usage) => usage.input + usage.output;
  static double? remainingUsd(ChatTokenSummary usage, double? limit) {
    if (limit == null) return null;
    if (usage.replies == 0 && usage.costComplete) return limit;
    return usage.cost == null ? null : (limit - usage.cost!).clamp(0.0, limit);
  }

  static int? remainingTokens(ChatTokenSummary usage, int? limit) =>
      limit == null ? null : (limit - total(usage)).clamp(0, limit);

  bool _reached(
    ChatTokenSummary usage,
    double? usd,
    int? tokens,
    int percent,
  ) =>
      (usd != null &&
          usage.cost != null &&
          usage.cost! >= usd * percent / 100) ||
      (tokens != null && total(usage) >= tokens * percent / 100);
  bool get chatWarning =>
      _reached(chat, limits.chatUsd, limits.chatTokens, limits.warningPercent);
  bool get dailyWarning => _reached(
    today,
    limits.dailyUsd,
    limits.dailyTokens,
    limits.warningPercent,
  );
  bool get exceeded =>
      _reached(chat, limits.chatUsd, limits.chatTokens, 100) ||
      _reached(today, limits.dailyUsd, limits.dailyTokens, 100);
  bool get blocked => limits.hardStop && exceeded;

  Map<String, dynamic> _usage(
    ChatTokenSummary usage,
    double? usd,
    int? tokens,
  ) => {
    'input_tokens': usage.input,
    'output_tokens': usage.output,
    'cached_tokens': usage.cached,
    'total_tokens': total(usage),
    'cost_usd': usage.cost,
    'cost_complete': usage.costComplete,
    'limit_usd': usd,
    'limit_tokens': tokens,
    'remaining_usd': remainingUsd(usage, usd),
    'remaining_tokens': remainingTokens(usage, tokens),
    'remaining_usd_is_upper_bound': usd != null && !usage.costComplete,
  };

  Map<String, dynamic> toJson() => {
    'chat': _usage(chat, limits.chatUsd, limits.chatTokens),
    'today': _usage(today, limits.dailyUsd, limits.dailyTokens),
    'day':
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'context': {
      'tokens': contextTokens,
      'window_tokens': contextWindow,
      'percent':
          contextTokens == null || contextWindow == null || contextWindow! <= 0
          ? null
          : contextTokens! * 100 / contextWindow!,
    },
    'limits': limits.toJson(),
    'threshold_reached': chatWarning || dailyWarning,
    'limit_reached': exceeded,
    'hard_stopped': blocked,
  };

  /// One request-only system line, emitted only for budgets at their threshold.
  String? get systemWarning {
    if (!chatWarning && !dailyWarning) return null;
    String remaining(
      String scope,
      ChatTokenSummary usage,
      double? usd,
      int? tokens,
    ) {
      final dollarLeft = remainingUsd(usage, usd);
      final tokenLeft = remainingTokens(usage, tokens);
      return '$scope: ${[if (usd != null) dollarLeft == null ? 'USD remaining unknown (price incomplete)' : '${usage.costComplete ? '' : 'at most '}\$${dollarLeft.toStringAsFixed(4)}${usage.costComplete ? '' : ' (price incomplete)'}', if (tokenLeft != null) '$tokenLeft tokens'].join(', ')} left';
    }

    return 'Spend control — ${[if (chatWarning) remaining('chat', chat, limits.chatUsd, limits.chatTokens), if (dailyWarning) remaining('today', today, limits.dailyUsd, limits.dailyTokens)].join('; ')}. Keep context/replies small; consider spend_control compact if available (approval; new chat).';
  }
}

/// Reads usage metadata only. Pricing and token accounting stay with the sheet.
class SpendControlService {
  SpendControlService({
    required this.chats,
    required this.settings,
    this.priceFor,
  });

  final ChatService chats;
  final SettingsProvider settings;
  final ModelCatalogEntry? Function(String? providerId, String modelId)?
  priceFor;

  Future<SpendControlStatus> status(
    String conversationId, {
    Assistant? assistant,
    DateTime? now,
    String? providerKey,
    String? modelId,
    bool includeContext = true,
  }) async {
    final localNow = (now ?? DateTime.now()).toLocal();
    final day = DateTime(localNow.year, localNow.month, localNow.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final chatMessages = await chats.loadSpendMessages(
      conversationId: conversationId,
    );
    final dayMessages = await chats.loadSpendMessages(
      start: day,
      endExclusive: end,
    );
    ModelCatalogEntry? price(String? provider, String model) => priceFor != null
        ? priceFor!(provider, model)
        : ModelCatalog.instance.lookup(
            provider == null
                ? model
                : apiModelId(settings.getProviderConfig(provider), model),
          );
    final conversation = chats.getConversation(conversationId);
    final model = resolveChatModel(
      settings,
      conversation: conversation,
      assistant: assistant,
    );
    final pk = providerKey ?? model.providerKey;
    final mid = modelId ?? model.modelId;
    final context = conversation == null || !includeContext
        ? const <ChatMessage>[]
        : await chats.loadSelectedContextMessages(
            conversationId,
            truncateIndex: conversation.truncateIndex,
            limit:
                assistant?.limitContextMessages == true &&
                    assistant!.contextMessageSize > 0
                ? assistant.contextMessageSize
                : ChatService.defaultInitialMessageMax,
          );
    return SpendControlStatus(
      chat: ChatTokenSummary.of(chatMessages, priceFor: price),
      today: ChatTokenSummary.of(dayMessages, priceFor: price),
      limits: settings.spendLimits,
      day: day,
      contextTokens: !includeContext
          ? null
          : context.isEmpty
          ? 0
          : latestContextTokens(context),
      contextWindow: pk == null || mid == null || isAcpModelSource(pk)
          ? null
          : resolveContextWindowTokens(settings, pk, mid),
    );
  }
}
