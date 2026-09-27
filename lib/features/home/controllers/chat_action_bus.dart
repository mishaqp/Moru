import 'dart:async';

enum ChatAction { enterGlobalSearch, exitGlobalSearch }

class ChatActionBus {
  ChatActionBus._();
  static final ChatActionBus instance = ChatActionBus._();

  final _controller = StreamController<ChatAction>.broadcast();
  Stream<ChatAction> get stream => _controller.stream;
  void fire(ChatAction action) => _controller.add(action);
  void dispose() => _controller.close();
}
