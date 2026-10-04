import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/models/token_usage.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/services/model_catalog/model_catalog.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';

class _SpendChats extends ChatService {
  final messages = <ChatMessage>[];
  @override
  Future<List<ChatMessage>> loadSpendMessages({
    String? conversationId,
    DateTime? start,
    DateTime? endExclusive,
  }) async => [
    for (final message in messages)
      if ((conversationId == null ||
              message.conversationId == conversationId) &&
          (start == null || !message.timestamp.isBefore(start)) &&
          (endExclusive == null || message.timestamp.isBefore(endExclusive)))
        message,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'budget and cache percentages keep unknown prices and disabled limits explicit',
    () {
      final status = SpendControlStatus(
        chat: const ChatTokenSummary(
          input: 100,
          output: 20,
          cached: 75,
          replies: 1,
          costComplete: false,
        ),
        today: const ChatTokenSummary(
          input: 200,
          output: 50,
          cached: 100,
          replies: 2,
          cost: 0.5,
        ),
        limits: const SpendLimits(chatTokens: 1000, chatUsd: 1, dailyUsd: 2),
        day: DateTime(2026, 10, 4),
      ).toJson();
      expect((status['chat'] as Map)['used_percent'], {
        'tokens': 12.0,
        'usd': null,
      });
      expect((status['chat'] as Map)['cached_percent'], 75.0);
      expect((status['today'] as Map)['used_percent'], {'usd': 25.0});
      expect((status['today'] as Map)['cached_percent'], 50.0);
      expect(status['current_response'], containsPair('completed_requests', 0));
      expect(
        status['current_response'],
        containsPair('accounting', 'not_included'),
      );
      expect(
        (status['current_response'] as Map)['note'],
        contains('not yet included'),
      );
      expect(
        SpendControlStatus.cachedPercent(
          const ChatTokenSummary(input: 0, output: 10, cached: 0, replies: 1),
        ),
        isNull,
      );
    },
  );

  test(
    'live completed round replaces its checkpoint and repeated usage is counted once',
    () async {
      final chats = _SpendChats();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(chats.dispose);
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setSpendLimits(
        const SpendLimits(chatTokens: 1000, dailyTokens: 1000),
      );
      final now = DateTime.now();
      final continued = ChatMessage(
        id: 'continuation',
        role: 'assistant',
        content: '',
        conversationId: 'c',
        timestamp: now,
        promptTokens: 100,
        completionTokens: 20,
        cachedTokens: 50,
      );
      chats.messages.addAll([
        ChatMessage(
          id: 'paid',
          role: 'assistant',
          content: '',
          conversationId: 'c',
          timestamp: now,
          promptTokens: 720,
        ),
        continued,
      ]);
      final service = SpendControlService(chats: chats, settings: settings);
      final session = service.beginResponse(
        message: continued,
        stopMessage: 'Reply stopped',
      );
      addTearDown(() => service.endResponse(session));
      const usage = TokenUsage(
        promptTokens: 100,
        completionTokens: 10,
        cachedTokens: 80,
      );
      await session.control
          .trackRound(
            Stream.fromIterable([const Usage(usage), const Usage(usage)]),
          )
          .drain<void>();
      // A persisted/live checkpoint already contains these completed rounds.
      chats.messages[1] = session.message;
      final status = await service.status('c', includeContext: false);
      expect(status.chat.input, 920);
      expect(status.chat.output, 30);
      expect(status.chat.cached, 130);
      expect(SpendControlStatus.total(status.chat), 950);
      expect(status.today.input, status.chat.input);
      expect(status.today.output, status.chat.output);
      expect((status.toJson()['chat'] as Map)['used_percent'], {
        'tokens': 95.0,
      });
      expect(
        status.toJson()['current_response'],
        containsPair('completed_requests', 1),
      );
      expect(
        status.toJson()['current_response'],
        containsPair('accounting', 'partial'),
      );
      expect(
        (status.toJson()['current_response'] as Map)['note'],
        contains('request in progress'),
      );
      service.endResponse(session);
      final ended = await service.status('c', includeContext: false);
      expect(SpendControlStatus.total(ended.chat), 950);
      expect(
        ended.toJson()['current_response'],
        containsPair('accounting', 'not_included'),
      );
    },
  );

  test(
    'daily limits include completed rounds in another active chat exactly once',
    () async {
      final chats = _SpendChats();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(chats.dispose);
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setSpendLimits(
        const SpendLimits(chatTokens: 1000, dailyTokens: 1000, hardStop: true),
      );
      final now = DateTime.now();
      final first = ChatMessage(
        id: 'first-live',
        role: 'assistant',
        content: '',
        conversationId: 'c',
        timestamp: now,
      );
      final second = ChatMessage(
        id: 'second-live',
        role: 'assistant',
        content: '',
        conversationId: 'other',
        timestamp: now,
      );
      chats.messages.addAll([
        ChatMessage(
          id: 'paid',
          role: 'assistant',
          content: '',
          conversationId: 'c',
          timestamp: now,
          promptTokens: 720,
        ),
        first,
        second,
      ]);
      final service = SpendControlService(chats: chats, settings: settings);
      final a = service.beginResponse(
        message: first,
        stopMessage: 'Reply stopped',
      );
      final b = service.beginResponse(
        message: second,
        stopMessage: 'Reply stopped',
      );
      addTearDown(() {
        service.endResponse(a);
        service.endResponse(b);
      });
      a.control.recordInitialUsage(
        const TokenUsage(promptTokens: 100, completionTokens: 10),
      );
      b.control.recordInitialUsage(
        const TokenUsage(promptTokens: 180, completionTokens: 10),
      );
      chats.messages[1] = a.message;
      chats.messages[2] = b.message;
      final status = await service.status('c', includeContext: false);
      expect(SpendControlStatus.total(status.chat), 830);
      expect(SpendControlStatus.total(status.today), 1020);
      expect(status.chatWarning, isTrue);
      expect(status.dailyWarning, isTrue);
      expect(status.blocked, isTrue);
      expect((status.toJson()['today'] as Map)['used_percent'], {
        'tokens': 102.0,
      });
      expect(
        status.toJson()['current_response'],
        containsPair('completed_requests', 1),
      );
    },
  );

  test(
    'reported usage survives a request error without marking the request completed',
    () async {
      final chats = _SpendChats();
      final settings = SettingsProvider(createBusinessTestPreferences());
      addTearDown(chats.dispose);
      addTearDown(settings.dispose);
      await settings.loaded;
      await settings.setSpendLimits(const SpendLimits(chatTokens: 1000));
      final live = ChatMessage(
        id: 'interrupted',
        role: 'assistant',
        content: '',
        conversationId: 'c',
        isStreaming: true,
      );
      chats.messages.add(
        ChatMessage(
          id: 'paid',
          role: 'assistant',
          content: '',
          conversationId: 'c',
          promptTokens: 720,
        ),
      );
      final service = SpendControlService(chats: chats, settings: settings);
      final session = service.beginResponse(
        message: live,
        stopMessage: 'Reply stopped',
      );
      addTearDown(() => service.endResponse(session));
      Stream<StreamChunk> interruptedRound() async* {
        yield const Usage(
          TokenUsage(promptTokens: 100, completionTokens: 10, cachedTokens: 75),
        );
        throw StateError('connection dropped');
      }

      await expectLater(
        session.control.trackRound(interruptedRound()).drain<void>(),
        throwsStateError,
      );
      expect(session.control.completedRounds, 0);
      expect(session.usage.promptTokens, 100);
      expect(session.usage.completionTokens, 10);
      expect(session.usage.cachedTokens, 75);
      expect(session.message.totalTokens, 110);
      final status = await service.status('c', includeContext: false);
      expect(SpendControlStatus.total(status.chat), 830);
      expect(
        status.toJson()['current_response'],
        containsPair('completed_requests', 0),
      );
      expect(
        status.toJson()['current_response'],
        containsPair('accounting', 'partial'),
      );
      expect(
        (status.toJson()['current_response'] as Map)['note'],
        contains('reported usage'),
      );
      expect(
        (status.toJson()['current_response'] as Map)['note'],
        contains('incomplete'),
      );
      // The cancellation checkpoint can retain the reported usage after the
      // transient session is removed, without charging it a second time.
      chats.messages.add(session.message.copyWith(isStreaming: false));
      service.endResponse(session);
      final persisted = await service.status('c', includeContext: false);
      expect(SpendControlStatus.total(persisted.chat), 830);
    },
  );
}
