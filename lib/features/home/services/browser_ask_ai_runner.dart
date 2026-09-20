import 'dart:async';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/conversation.dart';
import '../controllers/chat_actions.dart' show ChatActionResult;
import '../controllers/generation_terminal_event.dart';
import 'browser_ask_ai_bridge.dart';

typedef BrowserAskAiSend =
    Future<ChatActionResult> Function({
      required ChatInputData input,
      required Conversation conversation,
      required Assistant assistant,
      required void Function(String messageId) onGenerationStarted,
    });

typedef BrowserAskAiCancel =
    Future<void> Function(String conversationId, {String? expectedMessageId});

/// Resolves the current conversation/assistant, sends [request.text] through
/// [send] (`HomeViewModel.sendScheduledMessage` in production), and reports
/// the outcome to [bridge]. A standalone function with its collaborators
/// passed in rather than read from a `BuildContext`, so it can be unit-tested
/// without the full generation pipeline `HomePageController` normally runs
/// against — mirrors `runScheduledTask`'s own shape.
///
/// [send] only confirms that generation *started*: `ChatActions.sendMessage`
/// launches the real work via `unawaited(...)` and returns immediately with
/// an empty placeholder `ChatMessage` so the composer is never blocked on a
/// full reply. The real, finished answer arrives later and separately, on
/// [terminalEvents] — this function subscribes to it *before* calling [send]
/// (so an unusually fast finish can never race past a not-yet-registered
/// listener) and waits for the one event whose `assistantMessageId` matches
/// this run's own id, which [send] reports through [onGenerationStarted].
Future<void> runBrowserAskAiRequest({
  required BrowserAskAiBridge bridge,
  required BrowserAskAiRequest request,
  required String? currentConversationId,
  required Conversation? Function(String id) getConversation,
  required Assistant? Function(String id) getAssistantById,
  required Assistant? currentAssistant,
  required BrowserAskAiSend send,
  required BrowserAskAiCancel cancel,
  required Stream<GenerationTerminalEvent> terminalEvents,
}) async {
  // A cancel racing this call's own start (submitted, then stopped before
  // the request even reached this function — the request and cancellation
  // streams are both async, so a fast-enough cancel can arrive before this
  // function has subscribed to `bridge.cancellations`) must still take
  // effect, and must prevent send() from ever running rather than starting
  // it and cancelling right after. Checked before resolving the
  // conversation/assistant too, so a cancelled request is never reported as
  // some other failure instead, and the early-cancellation record is always
  // consumed regardless of which path this call takes.
  if (bridge.consumeEarlyCancellation(request.id)) {
    bridge.reportOutcome(
      BrowserAskAiOutcome(requestId: request.id, ok: false, cancelled: true),
    );
    return;
  }
  final conversation = currentConversationId == null
      ? null
      : getConversation(currentConversationId);
  if (conversation == null) {
    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: request.id,
        ok: false,
        error: 'no_conversation',
      ),
    );
    return;
  }
  final assistant = conversation.assistantId != null
      ? getAssistantById(conversation.assistantId!)
      : currentAssistant;
  if (assistant == null) {
    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: request.id,
        ok: false,
        error: 'no_assistant',
      ),
    );
    return;
  }
  String? messageId;
  var cancelRequested = false;
  var cancelIssued = false;
  void issueCancelIfPossible() {
    final id = messageId;
    if (id == null || cancelIssued) return;
    cancelIssued = true;
    unawaited(cancel(conversation.id, expectedMessageId: id));
  }

  final cancelSub = bridge.cancellations.where((id) => id == request.id).listen(
    (_) {
      cancelRequested = true;
      issueCancelIfPossible();
    },
  );

  // Subscribed before send() runs at all, so this run's own terminal event
  // — however quickly it arrives — is always observed. Matched by
  // assistantMessageId (known the moment onGenerationStarted fires, always
  // before send() returns), never by conversationId alone: a fast-moving
  // conversation can start and finish another run for the same
  // conversation while this one is still in flight.
  final terminalCompleter = Completer<GenerationTerminalEvent>();
  final terminalSub = terminalEvents.listen((event) {
    final id = messageId;
    if (id == null || event.assistantMessageId != id) return;
    if (!terminalCompleter.isCompleted) terminalCompleter.complete(event);
  });

  try {
    final result = await send(
      input: ChatInputData(
        text: browserAskAiOriginDirective(request) + request.text,
      ),
      conversation: conversation,
      assistant: assistant,
      onGenerationStarted: (id) {
        messageId = id;
        // A cancel that arrived before this callback (so before `id` was
        // known to issueCancelIfPossible above) must fire now instead of
        // being lost — this is the exact bug: cancellation before
        // onGenerationStarted used to be silently dropped.
        if (cancelRequested) issueCancelIfPossible();
      },
    );
    if (!result.success) {
      // A synchronous failure from send() itself (no_model, in_flight, a
      // validation error) — generation never started, so there is no
      // terminal event to wait for.
      bridge.reportOutcome(
        BrowserAskAiOutcome(
          requestId: request.id,
          ok: false,
          error: result.errorMessage,
        ),
      );
      return;
    }
    // send() only confirms the run started; result.assistantMessage is
    // still the empty placeholder ChatActions.sendMessage persists before
    // handing generation off. Wait for this run's own terminal event for
    // the real, finished ChatMessage — the chat's own source of truth,
    // written by the exact same code path that ends the tool loop and every
    // other consumer of a finished reply already reads from.
    final event = await terminalCompleter.future;
    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: request.id,
        ok: event.succeeded,
        error: event.succeeded
            ? null
            : (event.errorCode ?? 'generation_failed'),
        cancelled: event.cancelled,
        answerText: event.succeeded ? event.message.content : null,
        conversationId: event.succeeded ? event.conversationId : null,
        assistantMessageId: event.succeeded ? event.assistantMessageId : null,
      ),
    );
  } catch (error) {
    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: request.id,
        ok: false,
        error: error.toString(),
      ),
    );
  } finally {
    await cancelSub.cancel();
    await terminalSub.cancel();
  }
}

/// Prepended to [BrowserAskAiRequest.text] before it is sent as the user
/// turn. Baked into the turn's own text rather than the system prompt, the
/// same way [scheduledTaskOriginDirective] is -- this fires once per
/// request, not on a long-lived conversation, so there is no repeated-
/// preamble cost to avoid by moving it to a system-prompt injection.
String browserAskAiOriginDirective(BrowserAskAiRequest request) {
  final url = request.pageUrl;
  final where = (url == null || url.isEmpty) ? 'a page in the browser' : url;
  return '[System] This message came from the floating "Ask AI" bar in '
      "Moru's in-app browser, while the user is looking at $where. The "
      'reply is shown in a small overlay above the page -- keep it short.'
      '\n\n';
}
