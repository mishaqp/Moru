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
      expect(sentInputs.single.text, endsWith('find flights'));
      expect(sentInputs.single.text, contains('floating "Ask AI" bar'));
      expect(sentConversations.single.id, conversation.id);
      expect(sentAssistants.single.id, assistant.id);
    },
  );

  test('prepends the page URL when the request carries one', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final sentInputs = <ChatInputData>[];
    final outcomeFuture = firstOutcome(bridge);

    await runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(
        id: 'req-1b',
        text: 'summarize this',
        pageUrl: 'https://example.com/article',
      ),
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
            onGenerationStarted('message-1b');
            return ChatActionResult.success(
              ChatMessage(
                id: 'message-1b',
                conversationId: conversation.id,
                role: 'assistant',
                content: '',
              ),
            );
          },
      cancel: (_, {expectedMessageId}) async {},
    );

    await outcomeFuture;
    expect(sentInputs.single.text, contains('https://example.com/article'));
    expect(sentInputs.single.text, endsWith('summarize this'));
  });

  test(
    'browserAskAiOriginDirective falls back to a generic phrase without a URL',
    () {
      const request = BrowserAskAiRequest(id: 'req-x', text: 'hi');
      expect(
        browserAskAiOriginDirective(request),
        contains('a page in the browser'),
      );
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

  test(
    'a successful outcome carries the assistant reply and its ids',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final outcomeFuture = firstOutcome(bridge);

      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-8', text: 'read this page'),
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
              onGenerationStarted('message-8');
              return ChatActionResult.success(
                ChatMessage(
                  id: 'message-8',
                  conversationId: conversation.id,
                  role: 'assistant',
                  content: 'The page is about flights.',
                  reasoningText: 'internal deliberation, never surfaced',
                ),
              );
            },
        cancel: (_, {expectedMessageId}) async {},
      );

      final outcome = await outcomeFuture;
      expect(outcome.ok, isTrue);
      expect(outcome.answerText, 'The page is about flights.');
      expect(outcome.conversationId, conversation.id);
      expect(outcome.assistantMessageId, 'message-8');
      expect(outcome.cancelled, isFalse);
    },
  );

  test('a cancellation that races submit and arrives before the runner even '
      'starts still prevents the run', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    var sendCalled = false;
    final outcomeFuture = firstOutcome(bridge);

    // The cancel fires before runBrowserAskAiRequest is even invoked, the
    // same way a stream-delivered request and an immediately-following
    // cancel can race in production: nothing has subscribed to
    // `cancellations` yet, so a plain listener would miss this entirely.
    bridge.cancel('req-9');

    await runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-9', text: 'hi'),
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
            sendCalled = true;
            onGenerationStarted('message-9');
            return ChatActionResult.success(
              ChatMessage(
                id: 'message-9',
                conversationId: conversation.id,
                role: 'assistant',
                content: '',
              ),
            );
          },
      cancel: (_, {expectedMessageId}) async {
        fail('cancel must not be called: the run was already prevented');
      },
    );

    final outcome = await outcomeFuture;
    expect(sendCalled, isFalse);
    expect(outcome.ok, isFalse);
    expect(outcome.cancelled, isTrue);
  });

  test('a cancellation that arrives before onGenerationStarted still cancels '
      'the run the moment the message id is known', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final cancelledMessageIds = <String?>[];
    final aboutToStart = Completer<void>();
    final canStart = Completer<void>();

    final future = runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-10', text: 'hi'),
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
            aboutToStart.complete();
            // Simulates real generation start taking a moment (queueing,
            // model setup) after send() begins but before an id exists —
            // exactly the window the original bug lost a cancel in.
            await canStart.future;
            onGenerationStarted('message-10');
            return Completer<ChatActionResult>().future;
          },
      cancel: (conversationId, {expectedMessageId}) async {
        cancelledMessageIds.add(expectedMessageId);
      },
    );

    await aboutToStart.future;
    bridge.cancel('req-10');
    await pumpEventQueue();
    expect(cancelledMessageIds, isEmpty, reason: 'no message id exists yet');

    canStart.complete();
    await pumpEventQueue();

    expect(cancelledMessageIds, ['message-10']);
    unawaited(future);
  });

  test(
    'cancelling the same run twice issues at most one cancel call',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      var cancelCalls = 0;
      final generationStarted = Completer<void>();

      final future = runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-11', text: 'hi'),
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
              onGenerationStarted('message-11');
              generationStarted.complete();
              return Completer<ChatActionResult>().future;
            },
        cancel: (_, {expectedMessageId}) async {
          cancelCalls++;
        },
      );

      await generationStarted.future;
      bridge.cancel('req-11');
      bridge.cancel('req-11');
      await pumpEventQueue();

      expect(cancelCalls, 1);
      unawaited(future);
    },
  );

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
