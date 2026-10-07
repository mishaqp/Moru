import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/spend_limits.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/services/message_builder_service.dart';
import 'package:Kelivo/features/home/services/spend_control_service.dart';
import 'package:Kelivo/features/home/widgets/chat_token_sheet.dart';

class _Context extends Fake implements BuildContext {}

void main() {
  final service = MessageBuilderService(
    chatService: ChatService(),
    contextProvider: _Context(),
  );
  SpendControlStatus status(SpendLimits limits, int tokens) =>
      SpendControlStatus(
        chat: ChatTokenSummary(input: tokens, output: 0, cached: 0, replies: 1),
        today: const ChatTokenSummary(
          input: 0,
          output: 0,
          cached: 0,
          replies: 0,
        ),
        limits: limits,
        day: DateTime(2026, 10, 4),
      );

  test(
    'disabled budgets and below-threshold spend leave the request byte-for-byte unchanged',
    () {
      for (final snapshot in [
        status(const SpendLimits(), 1000),
        status(const SpendLimits(chatTokens: 100), 79),
      ]) {
        final request = <Map<String, dynamic>>[
          {'role': 'system', 'content': 'base'},
          {'role': 'user', 'content': 'hello'},
        ];
        final original = jsonEncode(request);
        service.injectSpendWarning(request, snapshot);
        expect(jsonEncode(request), original);
      }
    },
  );
  test('warning is one system line and never a history message', () {
    final saved = ChatMessage(
      role: 'user',
      content: 'hello',
      conversationId: 'c',
    );
    final request = service.buildApiMessages(
      messages: [saved],
      versionSelections: {},
      currentConversation: null,
    );
    service.injectSpendWarning(
      request,
      status(const SpendLimits(chatTokens: 100), 80),
    );
    expect(request.where((m) => m['role'] == 'system'), hasLength(1));
    expect(request.first['content'], contains('20 tokens'));
    expect((request.first['content'] as String).split('\n'), hasLength(1));
    expect(request.last['content'], 'hello');
    expect(saved.content, 'hello');
    expect(jsonEncode(saved.toJson()), isNot(contains('Spend control')));
  });
}
