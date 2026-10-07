import '../../../core/models/chat_message.dart';

/// Keeps generation identity independent from the currently loaded timeline.
class ActiveStreamingMessageStore {
  final Map<String, ChatMessage> _messagesByConversation =
      <String, ChatMessage>{};
  final Map<String, String> _executionIdsByConversation = <String, String>{};

  ChatMessage? operator [](String conversationId) {
    return _messagesByConversation[conversationId];
  }

  /// Whether any conversation currently has an in-flight assistant message.
  bool get isNotEmpty => _messagesByConversation.isNotEmpty;

  Set<String> get messageIds => {
    for (final message in _messagesByConversation.values) message.id,
  };

  List<ChatMessage> get messages =>
      List<ChatMessage>.unmodifiable(_messagesByConversation.values);

  void put(ChatMessage message, {String? executionId}) {
    if (!isActive(message)) {
      _executionIdsByConversation.remove(message.conversationId);
    }
    _messagesByConversation[message.conversationId] = message;
    if (executionId != null) {
      _executionIdsByConversation[message.conversationId] = executionId;
    }
  }

  bool isActive(ChatMessage message) {
    return _messagesByConversation[message.conversationId]?.id == message.id;
  }

  bool isExecutionActive(ChatMessage message, String executionId) =>
      isActive(message) &&
      _executionIdsByConversation[message.conversationId] == executionId;

  String? executionIdFor(String conversationId) =>
      _executionIdsByConversation[conversationId];

  void invalidateExecution(String conversationId, {String? executionId}) {
    if (executionId == null ||
        _executionIdsByConversation[conversationId] == executionId) {
      _executionIdsByConversation.remove(conversationId);
    }
  }

  ChatMessage? cancellationTarget(
    String conversationId,
    List<ChatMessage> loadedMessages,
  ) {
    final active = _messagesByConversation[conversationId];
    if (active != null) return active;
    for (var index = loadedMessages.length - 1; index >= 0; index--) {
      final message = loadedMessages[index];
      if (message.conversationId == conversationId &&
          message.role == 'assistant' &&
          message.isStreaming) {
        return message;
      }
    }
    return null;
  }

  void removeIfMatches(ChatMessage message) {
    if (_messagesByConversation[message.conversationId]?.id == message.id) {
      _messagesByConversation.remove(message.conversationId);
      _executionIdsByConversation.remove(message.conversationId);
    }
  }
}
