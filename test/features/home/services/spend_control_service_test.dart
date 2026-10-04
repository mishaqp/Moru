import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/services/model_catalog/model_catalog.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';

void main() {
  const price = ModelCatalogEntry(
    inputPrice: 2,
    outputPrice: 10,
    cacheReadPrice: 0.5,
  );
  final messages = [
    ChatMessage(
      id: 'old-version',
      role: 'assistant',
      content: 'old',
      conversationId: 'c',
      promptTokens: 1000000,
      completionTokens: 100000,
      cachedTokens: 500000,
      modelId: 'priced',
    ),
    ChatMessage(
      id: 'new-version',
      groupId: 'old-version',
      version: 1,
      role: 'assistant',
      content: 'new',
      conversationId: 'c',
      promptTokens: 1000,
      completionTokens: 10,
      modelId: 'priced',
    ),
    ChatMessage(
      id: 'unknown',
      role: 'assistant',
      content: 'unknown price',
      conversationId: 'c',
      promptTokens: 100,
      completionTokens: 10,
      modelId: 'unknown',
    ),
  ];
  final summary = ChatTokenSummary.of(
    messages,
    priceFor: (_, model) => model == 'priced' ? price : null,
  );

  test('status reports the token sheet totals and marks partial prices', () {
    final status = SpendControlStatus(
      chat: summary,
      today: summary,
      limits: const SpendLimits(chatUsd: 3, dailyTokens: 2000000),
      day: DateTime(2026, 10, 4),
      contextTokens: 45200,
      contextWindow: 200000,
    ).toJson();
    final chat = status['chat'] as Map;
    expect(chat['input_tokens'], 1001100);
    expect(chat['output_tokens'], 100020);
    expect(chat['cached_tokens'], 500000);
    expect(chat['total_tokens'], 1101120); // cache is part of input
    expect(chat['cost_usd'], closeTo(2.2521, 1e-9));
    expect(chat['cost_complete'], isFalse);
    expect(chat['remaining_usd'], closeTo(0.7479, 1e-9));
    expect(chat['remaining_usd_is_upper_bound'], isTrue);
    expect((status['today'] as Map)['remaining_tokens'], 898880);
    expect((status['context'] as Map)['percent'], 22.6);
  });

  test('warnings start exactly at threshold and hard stop is opt-in', () {
    SpendControlStatus status(
      int tokens, {
      bool hardStop = false,
    }) => SpendControlStatus(
      chat: ChatTokenSummary(input: tokens, output: 0, cached: 0, replies: 1),
      today: const ChatTokenSummary(input: 0, output: 0, cached: 0, replies: 0),
      limits: SpendLimits(chatTokens: 100, hardStop: hardStop),
      day: DateTime(2026, 10, 4),
    );
    expect(status(79).systemWarning, isNull);
    expect(status(80).systemWarning, contains('20 tokens'));
    expect(status(80).systemWarning!.split('\n'), hasLength(1));
    expect(status(100).blocked, isFalse);
    expect(status(100, hardStop: true).blocked, isTrue);
    expect(status(80, hardStop: true).blocked, isFalse);
    expect(status(120).systemWarning, contains('0 tokens'));
  });

  test(
    'daily dollars can trigger alone and unknown price does not invent a cost',
    () {
      final partial = SpendControlStatus(
        chat: summary,
        today: summary,
        limits: const SpendLimits(dailyUsd: 2.5),
        day: DateTime(2026, 10, 4),
      );
      expect(partial.systemWarning, contains('today'));
      expect(partial.systemWarning, contains('price incomplete'));
      final unknown = SpendControlStatus(
        chat: const ChatTokenSummary(
          input: 50,
          output: 10,
          cached: 0,
          replies: 1,
          costComplete: false,
        ),
        today: summary,
        limits: const SpendLimits(chatUsd: 1),
        day: DateTime(2026, 10, 4),
      );
      expect((unknown.toJson()['chat'] as Map)['cost_usd'], isNull);
      expect((unknown.toJson()['chat'] as Map)['remaining_usd'], isNull);
      expect(unknown.systemWarning, isNull);
      expect(unknown.blocked, isFalse);
    },
  );
  test('a chat with no reported spending has its whole dollar budget left', () {
    final status = SpendControlStatus(
      chat: ChatTokenSummary.of(const []),
      today: ChatTokenSummary.of(const []),
      limits: const SpendLimits(chatUsd: 1, dailyUsd: 2),
      day: DateTime(2026, 10, 4),
    );
    expect((status.toJson()['chat'] as Map)['remaining_usd'], 1);
    expect((status.toJson()['today'] as Map)['remaining_usd'], 2);
  });
}
