import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/model_context_window.dart';
import '../../../core/models/spend_limits.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_helpers.dart';
import '../../../core/services/api/generation/spend_round_control.dart';
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
    this.completedResponseRounds = 0,
    this.hasPendingResponseUsage = false,
  });

  final ChatTokenSummary chat;
  final ChatTokenSummary today;
  final SpendLimits limits;
  final DateTime day;
  final int? contextTokens;
  final int? contextWindow;
  final int completedResponseRounds;
  final bool hasPendingResponseUsage;

  static int total(ChatTokenSummary usage) => usage.input + usage.output;
  static double? cachedPercent(ChatTokenSummary usage) =>
      usage.input == 0 ? null : usage.cached * 100 / usage.input;
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
    'cached_percent': cachedPercent(usage),
    'total_tokens': total(usage),
    'cost_usd': usage.cost,
    'cost_complete': usage.costComplete,
    'limit_usd': usd,
    'limit_tokens': tokens,
    'used_percent': {
      if (usd != null)
        'usd': usage.replies == 0 && usage.costComplete
            ? 0.0
            : usage.cost == null
            ? null
            : usage.cost! * 100 / usd,
      if (tokens != null) 'tokens': total(usage) * 100 / tokens,
    },
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
    'current_response': {
      'completed_requests': completedResponseRounds,
      'accounting': completedResponseRounds > 0 || hasPendingResponseUsage
          ? 'partial'
          : 'not_included',
      'note': hasPendingResponseUsage
          ? 'Includes reported usage of this response; the request in progress may still be incomplete.'
          : completedResponseRounds > 0
          ? 'Includes completed requests of this response; the request in progress and later requests are not yet included.'
          : 'The current response is not yet included; usage becomes available after a model request completes.',
    },
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

    return 'Spend control — ${[if (chatWarning) remaining('chat', chat, limits.chatUsd, limits.chatTokens), if (dailyWarning) remaining('today', today, limits.dailyUsd, limits.dailyTokens)].join('; ')}. Monitor spending during long tasks; reply briefly near the limit and offer compact (approval) or a new chat.';
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

  static final _responses = Expando<Map<String, SpendControlSession>>();

  SpendControlSession beginResponse({
    required ChatMessage message,
    Assistant? assistant,
    String? initialWarning,
    required String stopMessage,
    void Function()? onRoundCompleted,
  }) {
    final session = SpendControlSession._(message);
    session.control = SpendRoundControl(
      initialWarning: initialWarning,
      onRoundCompleted: onRoundCompleted,
      beforeRequest: (_, _) async {
        final current = await status(
          message.conversationId,
          assistant: assistant,
          includeContext: false,
        );
        if (current.blocked) throw SpendLimitExceeded(stopMessage);
        return current.systemWarning;
      },
    );
    (_responses[chats] ??= {})[message.conversationId] = session;
    return session;
  }

  void endResponse(SpendControlSession session) {
    final responses = _responses[chats];
    if (identical(responses?[session.baseline.conversationId], session)) {
      responses!.remove(session.baseline.conversationId);
    }
  }

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
    final chatMessages = List<ChatMessage>.of(
      await chats.loadSpendMessages(conversationId: conversationId),
    );
    final dayMessages = List<ChatMessage>.of(
      await chats.loadSpendMessages(start: day, endExclusive: end),
    );
    final response = _responses[chats]?[conversationId];
    // Live checkpoints already overlay DB rows. Replace the current row rather
    // than adding it again, and retain earlier usage when continuing a reply.
    if (response != null) {
      chatMessages.removeWhere((message) => message.id == response.baseline.id);
      chatMessages.add(response.message);
    }
    for (final active
        in _responses[chats]?.values ?? const <SpendControlSession>[]) {
      dayMessages.removeWhere((message) => message.id == active.baseline.id);
      final time = active.baseline.timestamp.toLocal();
      if (!time.isBefore(day) && time.isBefore(end)) {
        dayMessages.add(active.message);
      }
    }
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
      completedResponseRounds: response?.control.completedRounds ?? 0,
      hasPendingResponseUsage: response?.control.pendingUsage != null,
      contextTokens: !includeContext
          ? null
          : context.isEmpty
          ? 0
          : response != null && response.control.completedRounds > 0
          ? response.control.lastUsage.totalTokens
          : latestContextTokens(context),
      contextWindow: pk == null || mid == null || isAcpModelSource(pk)
          ? null
          : resolveContextWindowTokens(settings, pk, mid),
    );
  }
}

class SpendControlSession {
  SpendControlSession._(this.baseline);
  final ChatMessage baseline;
  late final SpendRoundControl control;
  TokenUsage get usage => TokenUsage(
    promptTokens:
        (baseline.promptTokens ?? 0) +
        control.completedUsage.promptTokens +
        (control.pendingUsage?.promptTokens ?? 0),
    completionTokens:
        (baseline.completionTokens ?? 0) +
        control.completedUsage.completionTokens +
        (control.pendingUsage?.completionTokens ?? 0),
    cachedTokens:
        (baseline.cachedTokens ?? 0) +
        control.completedUsage.cachedTokens +
        (control.pendingUsage?.cachedTokens ?? 0),
  );
  ChatMessage get message => baseline.copyWith(
    promptTokens: usage.promptTokens,
    completionTokens: usage.completionTokens,
    cachedTokens: usage.cachedTokens,
    totalTokens:
        control.pendingUsage?.totalTokens ??
        (control.completedRounds > 0
            ? control.lastUsage.totalTokens
            : baseline.totalTokens),
  );
}
