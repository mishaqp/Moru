import '../../../core/models/chat_input_data.dart';

/// FIFO of messages the user submitted while their conversation was busy.
///
/// Kept free of Flutter state and of the send pipeline so the ordering rules —
/// which item is next, what happens when the head is claimed, where an edited
/// item goes back — can be reasoned about (and tested) on their own. Only the
/// conversation on screen may run a generation, so the queue holds items for
/// any number of conversations but always hands out one at a time.
///
/// Ordering is strict by insertion: items of the same conversation keep their
/// relative order, which is the guarantee the user sees.
class QueuedInputQueue {
  QueuedInputQueue({int Function()? idFactory})
    : _idFactory = idFactory ?? _defaultIdFactory;

  final int Function() _idFactory;
  final List<QueuedChatInput> _items = <QueuedChatInput>[];

  static int _serial = 0;

  static int _defaultIdFactory() => ++_serial;

  bool get isEmpty => _items.isEmpty;

  int get length => _items.length;

  /// Every parked item, oldest first, across all conversations.
  List<QueuedChatInput> get items => List<QueuedChatInput>.unmodifiable(_items);

  /// Parked items of one conversation, oldest first.
  List<QueuedChatInput> forConversation(String conversationId) {
    return List<QueuedChatInput>.unmodifiable(
      _items.where((item) => item.conversationId == conversationId),
    );
  }

  /// Oldest parked item of [conversationId], or null when it has none.
  QueuedChatInput? headFor(String conversationId) {
    for (final item in _items) {
      if (item.conversationId == conversationId) return item;
    }
    return null;
  }

  /// Index of [id] among the parked items of its own conversation, or -1.
  int indexOf(String id) {
    final target = _itemOrNull(id);
    if (target == null) return -1;
    final siblings = forConversation(target.conversationId);
    return siblings.indexWhere((item) => item.id == id);
  }

  /// Appends [input] to the back of the queue, as the next message for
  /// [conversationId]. Returns the stored item so callers can address it.
  QueuedChatInput enqueue(String conversationId, ChatInputData input) {
    final item = QueuedChatInput(
      id: 'queued-${_idFactory()}',
      conversationId: conversationId,
      input: cloneInput(input),
    );
    _items.add(item);
    return item;
  }

  /// Removes the item with [id], returning it, or null when it is not parked.
  QueuedChatInput? remove(String id) {
    final index = _indexOf(id);
    if (index < 0) return null;
    return _items.removeAt(index);
  }

  /// Removes and returns the oldest item of [conversationId].
  ///
  /// Claiming is a single synchronous step: the caller gets the item and the
  /// queue no longer holds it, so a second drain cannot pick it up again.
  QueuedChatInput? claimHeadFor(String conversationId) {
    final index = _items.indexWhere(
      (item) => item.conversationId == conversationId,
    );
    if (index < 0) return null;
    return _items.removeAt(index);
  }

  /// Puts an item back at [index] among the items of its conversation.
  ///
  /// [index] counts only items of the same conversation and is clamped, so an
  /// edit that finishes after the item ahead of it was sent still lands in a
  /// valid position instead of being dropped. Returns false when [id] is
  /// already parked, which happens when two edits of the same item race.
  bool reinsert({
    required String id,
    required String conversationId,
    required int index,
    required ChatInputData input,
  }) {
    if (_indexOf(id) >= 0) return false;
    final item = QueuedChatInput(
      id: id,
      conversationId: conversationId,
      input: cloneInput(input),
    );
    _items.insert(_insertionIndex(conversationId, index), item);
    return true;
  }

  /// Drops items whose conversation no longer satisfies [exists].
  ///
  /// Returns true when something was dropped, so the caller only notifies
  /// listeners on a real change.
  bool prune(bool Function(String conversationId) exists) {
    final before = _items.length;
    _items.removeWhere((item) => !exists(item.conversationId));
    return _items.length != before;
  }

  /// Removes every item of [conversationId]. Returns how many were dropped.
  int removeConversation(String conversationId) {
    final before = _items.length;
    _items.removeWhere((item) => item.conversationId == conversationId);
    return before - _items.length;
  }

  /// Rewrites the input of the parked item with [id] in place, keeping its
  /// position. Returns the updated item, or null when it is not parked.
  QueuedChatInput? replaceInput(String id, ChatInputData input) {
    final index = _indexOf(id);
    if (index < 0) return null;
    final updated = _items[index].withInput(cloneInput(input));
    _items[index] = updated;
    return updated;
  }

  void clear() => _items.clear();

  QueuedChatInput? _itemOrNull(String id) {
    final index = _indexOf(id);
    return index < 0 ? null : _items[index];
  }

  int _indexOf(String id) => _items.indexWhere((item) => item.id == id);

  int _insertionIndex(String conversationId, int index) {
    final positions = <int>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i].conversationId == conversationId) i,
    ];
    final clamped = index.clamp(0, positions.length);
    if (clamped >= positions.length) {
      // Behind the last item of this conversation, or the queue holds none of
      // them: fall back to the end of the whole queue.
      return positions.isEmpty ? _items.length : positions.last + 1;
    }
    return positions[clamped];
  }

  /// Copies the input so later edits of the composer draft cannot reach into a
  /// parked message.
  static ChatInputData cloneInput(ChatInputData input) {
    return ChatInputData(
      text: input.text,
      imagePaths: List<String>.of(input.imagePaths),
      documents: List<DocumentAttachment>.of(input.documents),
      allowImagesApiRouting: input.allowImagesApiRouting,
    );
  }
}
