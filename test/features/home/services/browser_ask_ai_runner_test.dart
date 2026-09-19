import 'dart:async';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assistant = Assistant(id: 'assistant-1', name: 'Assistant');
  final conversation = Conversation(
    id: 'conv-1',
    title: 'Chat',
    assistantId: assistant.id,
  );

  Future<BrowserAskAiOutcome> firstOutcome(BrowserAskAiBridge bridge) =>
      bridge.outcomes.first;

  test(
    'resolves the conversation and assistant, sends, and reports success',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final sentInputs = <ChatInputData>[];
      final sentConversations = <Conversation>[];
      final sentAssistants = <Assistant>[];

      final outcomeFuture = firstOutcome(bridge);
      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-1', text: 'find flights'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              sentInputs.add(input);
              sentConversations.add(conversation);
              sentAssistants.add(assistant);
              onGenerationStarted('message-1');
              return ChatActionResult.success(
                ChatMessage(
                  id: 'message-1',
                  conversationId: conversation.id,
                  role: 'assistant',
                  content: '',
                ),
              );
            },
        cancel: (_, {expectedMessageId}) async {},
      );

      final outcome = await outcomeFuture;
      expect(outcome.requestId, 'req-1');
      expect(outcome.ok, isTrue);
      expect(outcome.error, isNull);
      expect(sentInputs.single.text, 'find flights');
      expect(sentConversations.single.id, conversation.id);
      expect(sentAssistants.single.id, assistant.id);
    },
  );

  test(
    'reports no_conversation when there is no current conversation',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final outcomeFuture = firstOutcome(bridge);

      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-2', text: 'hi'),
        currentConversationId: null,
        getConversation: (_) => null,
        getAssistantById: (_) => null,
        currentAssistant: null,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) => fail('send must not be called'),
        cancel: (_, {expectedMessageId}) => fail('cancel must not be called'),
      );

      final outcome = await outcomeFuture;
      expect(outcome.ok, isFalse);
      expect(outcome.error, 'no_conversation');
    },
  );

  test(
    'falls back to currentAssistant when the conversation has no assistantId',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final noAssistantConversation = Conversation(id: 'conv-2', title: 'Chat');
      const fallbackAssistant = Assistant(id: 'fallback', name: 'Fallback');
      Assistant? usedAssistant;
      final outcomeFuture = firstOutcome(bridge);

      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-3', text: 'hi'),
        currentConversationId: noAssistantConversation.id,
        getConversation: (id) =>
            id == noAssistantConversation.id ? noAssistantConversation : null,
        getAssistantById: (_) => null,
        currentAssistant: fallbackAssistant,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              usedAssistant = assistant;
              onGenerationStarted('message-2');
              return ChatActionResult.success(
                ChatMessage(
                  id: 'message-2',
                  conversationId: conversation.id,
                  role: 'assistant',
                  content: '',
                ),
              );
            },
        cancel: (_, {expectedMessageId}) async {},
      );

      final outcome = await outcomeFuture;
      expect(outcome.ok, isTrue);
      expect(usedAssistant?.id, fallbackAssistant.id);
    },
  );

  test(
    'reports no_assistant when the conversation assistant cannot be found',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final outcomeFuture = firstOutcome(bridge);

      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-4', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (_) => null,
        currentAssistant: null,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) => fail('send must not be called'),
        cancel: (_, {expectedMessageId}) => fail('cancel must not be called'),
      );

      final outcome = await outcomeFuture;
      expect(outcome.ok, isFalse);
      expect(outcome.error, 'no_assistant');
    },
  );

  test('propagates the failed generation error message', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final outcomeFuture = firstOutcome(bridge);

    await runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-5', text: 'hi'),
      currentConversationId: conversation.id,
      getConversation: (id) => id == conversation.id ? conversation : null,
      getAssistantById: (id) => id == assistant.id ? assistant : null,
      currentAssistant: null,
      send:
          ({
            required input,
            required conversation,
            required assistant,
            required onGenerationStarted,
          }) async => ChatActionResult.inFlight(),
      cancel: (_, {expectedMessageId}) async {},
    );

    final outcome = await outcomeFuture;
    expect(outcome.ok, isFalse);
    expect(outcome.error, 'in_flight');
  });

  test('a cancellation forwards the started message id to cancel', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final cancelledConversationIds = <String>[];
    final cancelledMessageIds = <String?>[];
    final generationStarted = Completer<void>();
    late void Function(String) onStarted;

    final future = runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-6', text: 'hi'),
      currentConversationId: conversation.id,
      getConversation: (id) => id == conversation.id ? conversation : null,
      getAssistantById: (id) => id == assistant.id ? assistant : null,
      currentAssistant: null,
      send:
          ({
            required input,
            required conversation,
            required assistant,
            required onGenerationStarted,
          }) async {
            onStarted = onGenerationStarted;
            onStarted('message-6');
            generationStarted.complete();
            // Never resolves on its own; only the cancellation below ends it.
            return Completer<ChatActionResult>().future;
          },
      cancel: (conversationId, {expectedMessageId}) async {
        cancelledConversationIds.add(conversationId);
        cancelledMessageIds.add(expectedMessageId);
      },
    );

    await generationStarted.future;
    bridge.cancel('req-6');
    await pumpEventQueue();

    expect(cancelledConversationIds, [conversation.id]);
    expect(cancelledMessageIds, ['message-6']);

    // The request's own send() future never completes, so runBrowserAskAiRequest
    // is still awaiting it; unblock the test without asserting on that hang.
    unawaited(future);
  });

  test('a cancellation for a different request id is ignored', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    var cancelCalls = 0;

    unawaited(
      runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-7', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              onGenerationStarted('message-7');
              return ChatActionResult.success(
                ChatMessage(
                  id: 'message-7',
                  conversationId: conversation.id,
                  role: 'assistant',
                  content: '',
                ),
              );
            },
        cancel: (_, {expectedMessageId}) async {
          cancelCalls++;
        },
      ),
    );

    bridge.cancel('some-other-request');
    await pumpEventQueue();

    expect(cancelCalls, 0);
  });
}
