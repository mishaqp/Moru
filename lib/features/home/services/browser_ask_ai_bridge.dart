import 'dart:async';

import 'package:flutter/foundation.dart';

/// One instruction submitted from the floating "Ask AI" bar in the shared
/// browser. [id] pairs the request with its eventual [BrowserAskAiOutcome].
class BrowserAskAiRequest {
  const BrowserAskAiRequest({
    required this.id,
    required this.text,
    this.pageUrl,
  });

  final String id;
  final String text;

  /// The browser page's URL at submit time, or null if unknown (e.g. a
  /// blank/loading page). Included so the model knows what the user was
  /// looking at when they asked.
  final String? pageUrl;
}

class BrowserAskAiOutcome {
  const BrowserAskAiOutcome({
    required this.requestId,
    required this.ok,
    this.error,
    this.cancelled = false,
    this.answerText,
    this.conversationId,
    this.assistantMessageId,
  });

  final String requestId;
  final bool ok;

  /// Set when [ok] is false: `no_conversation`, `no_assistant`, `in_flight`,
  /// or `ChatActionResult.errorMessage` from a failed generation.
  final String? error;

  /// True when this outcome is a cancellation rather than a failure: [ok] is
  /// still false (nothing was produced), but this was requested, not an error.
  final bool cancelled;

  /// The assistant's finished reply text (`ChatMessage.content` — plain text
  /// only, no reasoning or tool payloads), set only when [ok] is true.
  final String? answerText;

  /// The conversation and message the reply belongs to, set only when [ok]
  /// is true. A browser result card must only ever show an outcome whose
  /// [requestId] (and, defensively, [conversationId]) matches its own
  /// request — never another conversation's or an earlier run's answer.
  final String? conversationId;
  final String? assistantMessageId;
}

/// A human-readable line for a failed [BrowserAskAiOutcome.error], for the
/// floating bar's snackbar. Anything not recognized (an arbitrary
/// `ChatActionResult.errorMessage`) falls back to a generic message rather
/// than surfacing an internal error code.
String askAiErrorMessage(String? error, {required bool ru}) {
  switch (error) {
    case 'no_conversation':
      return ru ? 'Нет активного чата.' : 'No active conversation.';
    case 'no_assistant':
      return ru
          ? 'Не найден ассистент для этого чата.'
          : 'No assistant found for this conversation.';
    case 'in_flight':
      return ru
          ? 'Чат сейчас занят другим ответом.'
          : 'The chat is already generating a reply.';
    default:
      return ru
          ? 'Не удалось выполнить команду.'
          : 'Could not run the command.';
  }
}

/// Decouples the browser page's floating "Ask AI" bar — pushed on the app's
/// root navigator, outside `HomePage`'s own widget subtree — from the home
/// page's message-generation pipeline, the same way
/// `NotificationService.conversationTaps` decouples a system notification
/// tap from it. `HomePageController` listens to [requests] and drives
/// `HomeViewModel.sendScheduledMessage` against the current conversation;
/// the browser page listens to [outcomes] to know when a request finishes.
class BrowserAskAiBridge extends ChangeNotifier {
  final StreamController<BrowserAskAiRequest> _requests =
      StreamController<BrowserAskAiRequest>.broadcast();
  final StreamController<BrowserAskAiOutcome> _outcomes =
      StreamController<BrowserAskAiOutcome>.broadcast();
  final StreamController<String> _cancellations =
      StreamController<String>.broadcast();

  Stream<BrowserAskAiRequest> get requests => _requests.stream;
  Stream<BrowserAskAiOutcome> get outcomes => _outcomes.stream;
  Stream<String> get cancellations => _cancellations.stream;

  int _nextId = 0;

  /// Requests cancelled before their runner ever subscribed to
  /// [cancellations] — the broadcast stream never replays past events to a
  /// late subscriber, so a cancel that races the request's own delivery
  /// would otherwise be silently lost. Consumed (and removed) exactly once
  /// by [consumeEarlyCancellation], so this never grows past the number of
  /// cancels currently racing a not-yet-started run.
  final Set<String> _earlyCancellations = <String>{};

  /// Submits [text] and returns the request id to match against [outcomes].
  /// [pageUrl] is the browser page's current URL, when known.
  String submit(String text, {String? pageUrl}) {
    final id = 'browser-ask-ai-${_nextId++}';
    _requests.add(BrowserAskAiRequest(id: id, text: text, pageUrl: pageUrl));
    return id;
  }

  /// Asks whoever is running [requestId] to cancel it. A no-op once that
  /// request has already produced an outcome. Safe to call more than once,
  /// and safe to call before the request has started running.
  void cancel(String requestId) {
    _earlyCancellations.add(requestId);
    _cancellations.add(requestId);
  }

  /// Called once by a request's runner, right before it would otherwise
  /// start work, to check whether [cancel] already fired for it before the
  /// runner subscribed to [cancellations]. Returns true (and forgets
  /// [requestId]) exactly once per early cancellation.
  bool consumeEarlyCancellation(String requestId) =>
      _earlyCancellations.remove(requestId);

  void reportOutcome(BrowserAskAiOutcome outcome) => _outcomes.add(outcome);

  @override
  void dispose() {
    _requests.close();
    _outcomes.close();
    _cancellations.close();
    _earlyCancellations.clear();
    super.dispose();
  }
}
