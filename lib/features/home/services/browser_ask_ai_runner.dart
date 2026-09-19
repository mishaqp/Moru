import 'dart:async';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/conversation.dart';
import '../controllers/chat_actions.dart' show ChatActionResult;
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
Future<void> runBrowserAskAiRequest({
  required BrowserAskAiBridge bridge,
  required BrowserAskAiRequest request,
  required String? currentConversationId,
  required Conversation? Function(String id) getConversation,
  required Assistant? Function(String id) getAssistantById,
  required Assistant? currentAssistant,
  required BrowserAskAiSend send,
  required BrowserAskAiCancel cancel,
}) async {
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
  final cancelSub = bridge.cancellations.where((id) => id == request.id).listen(
    (_) {
      final id = messageId;
      if (id != null) {
        unawaited(cancel(conversation.id, expectedMessageId: id));
      }
    },
  );
  try {
    final result = await send(
      input: ChatInputData(
        text: browserAskAiOriginDirective(request) + request.text,
      ),
      conversation: conversation,
      assistant: assistant,
      onGenerationStarted: (id) => messageId = id,
    );
    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: request.id,
        ok: result.success,
        error: result.success ? null : result.errorMessage,
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
