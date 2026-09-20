import 'dart:async';

import 'package:Kelivo/core/database/generation_run.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:Kelivo/features/home/controllers/generation_terminal_event.dart';
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

  // The real `ChatActions.sendMessage` contract: `send()` returns the moment
  // generation *starts*, carrying an empty placeholder message -- never the
  // finished reply. A mock that returned real content straight from `send()`
  // (as this test file used to) exercises a contract production never has,
  // and would hide exactly the bug this suite now guards against. The real
  // answer only ever arrives later, as a [GenerationTerminalEvent] on a
  // separate stream, matched by assistantMessageId.
  ChatMessage placeholderMessage(String id) => ChatMessage(
    id: id,
    conversationId: conversation.id,
    role: 'assistant',
    content: '',
  );

  GenerationTerminalEvent completedEvent(String messageId, String text) =>
      GenerationTerminalEvent(
        conversationId: conversation.id,
        assistantMessageId: messageId,
        generationRunId: 'run-$messageId',
        terminalState: GenerationRunState.completed,
        message: ChatMessage(
          id: messageId,
          conversationId: conversation.id,
          role: 'assistant',
          content: text,
        ),
      );

  GenerationTerminalEvent failedEvent(String messageId, {String? errorCode}) =>
      GenerationTerminalEvent(
        conversationId: conversation.id,
        assistantMessageId: messageId,
        generationRunId: 'run-$messageId',
        terminalState: GenerationRunState.failed,
        message: ChatMessage(
          id: messageId,
          conversationId: conversation.id,
          role: 'assistant',
          content: '',
        ),
        errorCode: errorCode,
      );

  GenerationTerminalEvent cancelledEvent(String messageId) =>
      GenerationTerminalEvent(
        conversationId: conversation.id,
        assistantMessageId: messageId,
        generationRunId: 'run-$messageId',
        terminalState: GenerationRunState.cancelled,
        message: ChatMessage(
          id: messageId,
          conversationId: conversation.id,
          role: 'assistant',
          content: '',
        ),
      );

  test('resolves the conversation and assistant, sends, and reports success '
      'only once the terminal event for this run arrives', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final sentInputs = <ChatInputData>[];
    final sentConversations = <Conversation>[];
    final sentAssistants = <Assistant>[];

    final outcomeFuture = firstOutcome(bridge);
    final runFuture = runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-1', text: 'find flights'),
      currentConversationId: conversation.id,
      getConversation: (id) => id == conversation.id ? conversation : null,
      getAssistantById: (id) => id == assistant.id ? assistant : null,
      currentAssistant: null,
      terminalEvents: terminal.stream,
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
            // Mirrors production: the returned message is the empty
            // placeholder, not the reply.
            return ChatActionResult.success(placeholderMessage('message-1'));
          },
      cancel: (_, {expectedMessageId}) async {},
    );

    // Nothing has been reported yet: send() resolving is not completion.
    await pumpEventQueue();
    terminal.add(completedEvent('message-1', 'Flights found.'));
    await runFuture;

    final outcome = await outcomeFuture;
    expect(outcome.requestId, 'req-1');
    expect(outcome.ok, isTrue);
    expect(outcome.error, isNull);
    expect(outcome.answerText, 'Flights found.');
    expect(sentInputs.single.text, endsWith('find flights'));
    expect(sentInputs.single.text, contains('floating "Ask AI" bar'));
    expect(sentConversations.single.id, conversation.id);
    expect(sentAssistants.single.id, assistant.id);
  });

  test('prepends the page URL when the request carries one', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final sentInputs = <ChatInputData>[];
    final outcomeFuture = firstOutcome(bridge);

    unawaited(
      runBrowserAskAiRequest(
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
        terminalEvents: terminal.stream,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              sentInputs.add(input);
              onGenerationStarted('message-1b');
              return ChatActionResult.success(placeholderMessage('message-1b'));
            },
        cancel: (_, {expectedMessageId}) async {},
      ),
    );

    await pumpEventQueue();
    terminal.add(completedEvent('message-1b', 'Summary.'));
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
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final outcomeFuture = firstOutcome(bridge);

      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-2', text: 'hi'),
        currentConversationId: null,
        getConversation: (_) => null,
        getAssistantById: (_) => null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
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
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final noAssistantConversation = Conversation(id: 'conv-2', title: 'Chat');
      const fallbackAssistant = Assistant(id: 'fallback', name: 'Fallback');
      Assistant? usedAssistant;
      final outcomeFuture = firstOutcome(bridge);

      unawaited(
        runBrowserAskAiRequest(
          bridge: bridge,
          request: const BrowserAskAiRequest(id: 'req-3', text: 'hi'),
          currentConversationId: noAssistantConversation.id,
          getConversation: (id) =>
              id == noAssistantConversation.id ? noAssistantConversation : null,
          getAssistantById: (_) => null,
          currentAssistant: fallbackAssistant,
          terminalEvents: terminal.stream,
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
                  placeholderMessage('message-2'),
                );
              },
          cancel: (_, {expectedMessageId}) async {},
        ),
      );

      await pumpEventQueue();
      terminal.add(completedEvent('message-2', 'ok'));
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
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final outcomeFuture = firstOutcome(bridge);

      await runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-4', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (_) => null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
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

  test('propagates the failed generation error message from a synchronous '
      'send() failure (generation never started)', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final outcomeFuture = firstOutcome(bridge);

    await runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-5', text: 'hi'),
      currentConversationId: conversation.id,
      getConversation: (id) => id == conversation.id ? conversation : null,
      getAssistantById: (id) => id == assistant.id ? assistant : null,
      currentAssistant: null,
      terminalEvents: terminal.stream,
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

  test('reports a failure whose terminal event arrives after a successful '
      'start (error after send() already returned success)', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final outcomeFuture = firstOutcome(bridge);

    unawaited(
      runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-fail', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              onGenerationStarted('message-fail');
              return ChatActionResult.success(
                placeholderMessage('message-fail'),
              );
            },
        cancel: (_, {expectedMessageId}) async {},
      ),
    );

    await pumpEventQueue();
    terminal.add(
      failedEvent('message-fail', errorCode: 'oauth_login_required'),
    );

    final outcome = await outcomeFuture;
    expect(outcome.ok, isFalse);
    expect(outcome.cancelled, isFalse);
    expect(outcome.error, 'oauth_login_required');
    expect(outcome.answerText, isNull);
  });

  test('a cancellation forwards the started message id to cancel', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final cancelledConversationIds = <String>[];
    final cancelledMessageIds = <String?>[];
    final generationStarted = Completer<void>();

    final future = runBrowserAskAiRequest(
      bridge: bridge,
      request: const BrowserAskAiRequest(id: 'req-6', text: 'hi'),
      currentConversationId: conversation.id,
      getConversation: (id) => id == conversation.id ? conversation : null,
      getAssistantById: (id) => id == assistant.id ? assistant : null,
      currentAssistant: null,
      terminalEvents: terminal.stream,
      send:
          ({
            required input,
            required conversation,
            required assistant,
            required onGenerationStarted,
          }) async {
            onGenerationStarted('message-6');
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
    'Stop after send() returns success but before the generation finishes '
    'still resolves once the run\'s own cancelled terminal event arrives',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final cancelledMessageIds = <String?>[];
      final outcomeFuture = firstOutcome(bridge);

      unawaited(
        runBrowserAskAiRequest(
          bridge: bridge,
          request: const BrowserAskAiRequest(id: 'req-stop', text: 'hi'),
          currentConversationId: conversation.id,
          getConversation: (id) => id == conversation.id ? conversation : null,
          getAssistantById: (id) => id == assistant.id ? assistant : null,
          currentAssistant: null,
          terminalEvents: terminal.stream,
          send:
              ({
                required input,
                required conversation,
                required assistant,
                required onGenerationStarted,
              }) async {
                onGenerationStarted('message-stop');
                // Unlike a real send(), this already returned success by the
                // time Stop is tapped -- generation itself is still running
                // in the background, exactly like production.
                return ChatActionResult.success(
                  placeholderMessage('message-stop'),
                );
              },
          cancel: (conversationId, {expectedMessageId}) async {
            cancelledMessageIds.add(expectedMessageId);
          },
        ),
      );

      await pumpEventQueue();
      bridge.cancel('req-stop');
      await pumpEventQueue();
      expect(cancelledMessageIds, ['message-stop']);

      // Still nothing reported: cancellation was requested, but the run's
      // own terminal event has not arrived yet.
      var outcomeReported = false;
      unawaited(outcomeFuture.then((_) => outcomeReported = true));
      await pumpEventQueue();
      expect(outcomeReported, isFalse);

      terminal.add(cancelledEvent('message-stop'));
      final outcome = await outcomeFuture;
      expect(outcome.ok, isFalse);
      expect(outcome.cancelled, isTrue);
    },
  );

  test('a successful outcome carries the assistant reply and its ids from the '
      'terminal event, not from send()\'s placeholder', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final outcomeFuture = firstOutcome(bridge);

    unawaited(
      runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-8', text: 'read this page'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              onGenerationStarted('message-8');
              return ChatActionResult.success(placeholderMessage('message-8'));
            },
        cancel: (_, {expectedMessageId}) async {},
      ),
    );

    await pumpEventQueue();
    terminal.add(
      GenerationTerminalEvent(
        conversationId: conversation.id,
        assistantMessageId: 'message-8',
        generationRunId: 'run-8',
        terminalState: GenerationRunState.completed,
        message: ChatMessage(
          id: 'message-8',
          conversationId: conversation.id,
          role: 'assistant',
          content: 'The page is about flights.',
          reasoningText: 'internal deliberation, never surfaced',
        ),
      ),
    );

    final outcome = await outcomeFuture;
    expect(outcome.ok, isTrue);
    expect(outcome.answerText, 'The page is about flights.');
    expect(outcome.conversationId, conversation.id);
    expect(outcome.assistantMessageId, 'message-8');
    expect(outcome.cancelled, isFalse);
  });

  test(
    'an instant terminal event, added right after send() returns, is never '
    'lost because the subscription is established before send() is called',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final outcomeFuture = firstOutcome(bridge);

      unawaited(
        runBrowserAskAiRequest(
          bridge: bridge,
          request: const BrowserAskAiRequest(id: 'req-instant', text: 'hi'),
          currentConversationId: conversation.id,
          getConversation: (id) => id == conversation.id ? conversation : null,
          getAssistantById: (id) => id == assistant.id ? assistant : null,
          currentAssistant: null,
          terminalEvents: terminal.stream,
          send:
              ({
                required input,
                required conversation,
                required assistant,
                required onGenerationStarted,
              }) async {
                onGenerationStarted('message-instant');
                // Fire the terminal event synchronously, in the same
                // microtask send() itself resolves in -- the tightest
                // possible race between send() returning and the terminal
                // event's own delivery.
                terminal.add(completedEvent('message-instant', 'Fast reply.'));
                return ChatActionResult.success(
                  placeholderMessage('message-instant'),
                );
              },
          cancel: (_, {expectedMessageId}) async {},
        ),
      );

      final outcome = await outcomeFuture;
      expect(outcome.ok, isTrue);
      expect(outcome.answerText, 'Fast reply.');
    },
  );

  test(
    'a late terminal event after the browser has closed (no one reading '
    'bridge.outcomes any more) does not throw and still completes the run',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);

      final future = runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-late', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              onGenerationStarted('message-late');
              return ChatActionResult.success(
                placeholderMessage('message-late'),
              );
            },
        cancel: (_, {expectedMessageId}) async {},
      );

      await pumpEventQueue();
      // Nothing subscribes to bridge.outcomes at all -- simulates the
      // browser page (and its AskAiPanelController) having been disposed.
      terminal.add(completedEvent('message-late', 'Too late to show.'));
      await future; // Must complete without throwing.
    },
  );

  test(
    'a different run\'s terminal event on the shared stream is ignored',
    () async {
      final bridge = BrowserAskAiBridge();
      addTearDown(bridge.dispose);
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      final outcomeFuture = firstOutcome(bridge);

      unawaited(
        runBrowserAskAiRequest(
          bridge: bridge,
          request: const BrowserAskAiRequest(id: 'req-mine', text: 'hi'),
          currentConversationId: conversation.id,
          getConversation: (id) => id == conversation.id ? conversation : null,
          getAssistantById: (id) => id == assistant.id ? assistant : null,
          currentAssistant: null,
          terminalEvents: terminal.stream,
          send:
              ({
                required input,
                required conversation,
                required assistant,
                required onGenerationStarted,
              }) async {
                onGenerationStarted('message-mine');
                return ChatActionResult.success(
                  placeholderMessage('message-mine'),
                );
              },
          cancel: (_, {expectedMessageId}) async {},
        ),
      );

      await pumpEventQueue();
      // A concurrent, unrelated run's own terminal event (e.g. a normal chat
      // send happening in the same conversation at the same time).
      terminal.add(completedEvent('message-someone-elses-run', 'Not mine.'));
      await pumpEventQueue();

      var outcomeReported = false;
      unawaited(outcomeFuture.then((_) => outcomeReported = true));
      await pumpEventQueue();
      expect(outcomeReported, isFalse);

      terminal.add(completedEvent('message-mine', 'Mine.'));
      final outcome = await outcomeFuture;
      expect(outcome.answerText, 'Mine.');
    },
  );

  test('a repeated terminal event for the same run does not report a duplicate '
      'outcome', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    final outcomes = <BrowserAskAiOutcome>[];
    bridge.outcomes.listen(outcomes.add);

    unawaited(
      runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-dup', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              onGenerationStarted('message-dup');
              return ChatActionResult.success(
                placeholderMessage('message-dup'),
              );
            },
        cancel: (_, {expectedMessageId}) async {},
      ),
    );

    await pumpEventQueue();
    terminal.add(completedEvent('message-dup', 'Once.'));
    terminal.add(completedEvent('message-dup', 'Twice.'));
    await pumpEventQueue();

    expect(outcomes, hasLength(1));
    expect(outcomes.single.answerText, 'Once.');
  });

  test('a cancellation that races submit and arrives before the runner even '
      'starts still prevents the run', () async {
    final bridge = BrowserAskAiBridge();
    addTearDown(bridge.dispose);
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
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
      terminalEvents: terminal.stream,
      send:
          ({
            required input,
            required conversation,
            required assistant,
            required onGenerationStarted,
          }) async {
            sendCalled = true;
            onGenerationStarted('message-9');
            return ChatActionResult.success(placeholderMessage('message-9'));
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
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
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
      terminalEvents: terminal.stream,
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
      final terminal = StreamController<GenerationTerminalEvent>.broadcast();
      addTearDown(terminal.close);
      var cancelCalls = 0;
      final generationStarted = Completer<void>();

      final future = runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-11', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
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
    final terminal = StreamController<GenerationTerminalEvent>.broadcast();
    addTearDown(terminal.close);
    var cancelCalls = 0;

    unawaited(
      runBrowserAskAiRequest(
        bridge: bridge,
        request: const BrowserAskAiRequest(id: 'req-7', text: 'hi'),
        currentConversationId: conversation.id,
        getConversation: (id) => id == conversation.id ? conversation : null,
        getAssistantById: (id) => id == assistant.id ? assistant : null,
        currentAssistant: null,
        terminalEvents: terminal.stream,
        send:
            ({
              required input,
              required conversation,
              required assistant,
              required onGenerationStarted,
            }) async {
              onGenerationStarted('message-7');
              return ChatActionResult.success(placeholderMessage('message-7'));
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
