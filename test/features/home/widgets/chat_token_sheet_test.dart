import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/services/model_catalog/model_catalog.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';
import 'package:Kelivo/features/home/widgets/context_usage_ring.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

ChatMessage _reply(
  String id, {
  String? modelId = 'priced',
  int? prompt,
  int? completion,
  int? cached,
}) => ChatMessage(
  id: id,
  role: 'assistant',
  content: 'x',
  conversationId: 'c',
  modelId: modelId,
  providerId: 'p',
  promptTokens: prompt,
  completionTokens: completion,
  cachedTokens: cached,
);

void main() {
  const priced = ModelCatalogEntry(
    inputPrice: 2,
    outputPrice: 10,
    cacheReadPrice: 0.5,
  );

  test('the summary adds up every reply with usage and prices it', () {
    final summary = ChatTokenSummary.of(
      [
        ChatMessage(
          id: 'u',
          role: 'user',
          content: 'hi',
          conversationId: 'c',
          promptTokens: 999,
        ),
        _reply('a', prompt: 1000000, completion: 100000, cached: 500000),
        // An older version of the same answer was paid for too.
        _reply('b', prompt: 1000, completion: 10),
        _reply('no-usage'),
      ],
      priceFor: (providerId, modelId) => modelId == 'priced' ? priced : null,
    );
    expect(summary.input, 1001000);
    expect(summary.output, 100010);
    expect(summary.cached, 500000);
    expect(summary.replies, 2);
    // a: 0.5M × 2 + 0.5M × 0.5 + 0.1M × 10 = 2.25; b: 0.002 + 0.0001.
    expect(summary.cost, closeTo(2.2521, 1e-9));
    expect(summary.costComplete, isTrue);

    final partial = ChatTokenSummary.of(
      [
        _reply('a', prompt: 1000, completion: 10),
        _reply('b', modelId: 'unknown', prompt: 1000, completion: 10),
      ],
      priceFor: (providerId, modelId) => modelId == 'priced' ? priced : null,
    );
    expect(partial.costComplete, isFalse);
    expect(partial.cost, closeTo(0.0021, 1e-9));
    expect(ChatTokenSummary.of(const []).cost, isNull);
  });

  testWidgets('the ring opens the token sheet', (tester) async {
    final summary = ChatTokenSummary.of([
      _reply('a', prompt: 40000, completion: 5200, cached: 20000),
    ], priceFor: (_, __) => priced);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ContextUsageRing(
                usedTokens: 45200,
                windowTokens: 200000,
                onTap: () => showChatTokenSheet(
                  context,
                  usedTokens: 45200,
                  windowTokens: 200000,
                  maxOutputTokens: 64000,
                  summary: summary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ContextUsageRing));
    await tester.pumpAndSettle();
    expect(find.text('Chat tokens'), findsOneWidget);
    expect(find.text('45.2k · 23%'), findsOneWidget);
    expect(find.text('64k'), findsOneWidget);
    expect(find.text('20k · 50%'), findsOneWidget);
    expect(find.text('Replies'), findsOneWidget);
    expect(find.textContaining(r'$'), findsOneWidget);
  });
}
