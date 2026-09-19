import 'dart:async';

import 'package:flutter/foundation.dart';

/// One instruction submitted from the floating "Ask AI" bar in the shared
/// browser. [id] pairs the request with its eventual [BrowserAskAiOutcome].
class BrowserAskAiRequest {
  const BrowserAskAiRequest({required this.id, required this.text});

  final String id;
  final String text;
}

class BrowserAskAiOutcome {
  const BrowserAskAiOutcome({
    required this.requestId,
    required this.ok,
    this.error,
  });

  final String requestId;
  final bool ok;

  /// Set when [ok] is false: `no_conversation`, `no_assistant`, `in_flight`,
  /// or `ChatActionResult.errorMessage` from a failed generation.
  final String? error;
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

  /// Submits [text] and returns the request id to match against [outcomes].
  String submit(String text) {
    final id = 'browser-ask-ai-${_nextId++}';
    _requests.add(BrowserAskAiRequest(id: id, text: text));
    return id;
  }

  /// Asks whoever is running [requestId] to cancel it. A no-op once that
  /// request has already produced an outcome.
  void cancel(String requestId) => _cancellations.add(requestId);

  void reportOutcome(BrowserAskAiOutcome outcome) => _outcomes.add(outcome);

  @override
  void dispose() {
    _requests.close();
    _outcomes.close();
    _cancellations.close();
    super.dispose();
  }
}
