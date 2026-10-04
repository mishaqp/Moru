/// Small, derived sidebar data. Never persisted or included in chat backups.
final class ConversationListMetadata {
  const ConversationListMetadata({
    required this.lastMessageId,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    this.lastMessageModelId,
    this.lastMessageProviderId,
    this.lastAssistantMessageId,
    this.lastAssistantModelId,
    this.lastAssistantProviderId,
  });

  static const int previewMaxLength = 240;

  final String lastMessageId;
  final DateTime lastMessageAt;
  final String lastMessagePreview;
  final String? lastMessageModelId;
  final String? lastMessageProviderId;
  final String? lastAssistantMessageId;
  final String? lastAssistantModelId;
  final String? lastAssistantProviderId;

  static String previewFromText(String text) {
    var end = text.length < previewMaxLength ? text.length : previewMaxLength;
    // A preview must not split a UTF-16 surrogate pair.
    if (end > 0 && end < text.length) {
      final unit = text.codeUnitAt(end - 1);
      if (unit >= 0xd800 && unit <= 0xdbff) end--;
    }
    final bounded = text.substring(0, end);
    final lineEnd = bounded.indexOf(RegExp(r'[\r\n]'));
    return (lineEnd < 0 ? bounded : bounded.substring(0, lineEnd)).trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationListMetadata &&
          lastMessageId == other.lastMessageId &&
          lastMessageAt == other.lastMessageAt &&
          lastMessagePreview == other.lastMessagePreview &&
          lastMessageModelId == other.lastMessageModelId &&
          lastMessageProviderId == other.lastMessageProviderId &&
          lastAssistantMessageId == other.lastAssistantMessageId &&
          lastAssistantModelId == other.lastAssistantModelId &&
          lastAssistantProviderId == other.lastAssistantProviderId;

  @override
  int get hashCode => Object.hash(
    lastMessageId,
    lastMessageAt,
    lastMessagePreview,
    lastMessageModelId,
    lastMessageProviderId,
    lastAssistantMessageId,
    lastAssistantModelId,
    lastAssistantProviderId,
  );
}
