class ChatItem {
  final String id;
  final String title;
  final DateTime created;
  final bool isPinned;

  /// The user folder the chat is in, or null.
  final String? folderId;

  ChatItem({
    required this.id,
    required this.title,
    required this.created,
    this.isPinned = false,
    this.folderId,
  });

  ChatItem copyWith({
    String? id,
    String? title,
    DateTime? created,
    bool? isPinned,
    String? folderId,
  }) => ChatItem(
    id: id ?? this.id,
    title: title ?? this.title,
    created: created ?? this.created,
    isPinned: isPinned ?? this.isPinned,
    folderId: folderId ?? this.folderId,
  );
}
