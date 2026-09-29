import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A user folder in the sidebar ("Работа", "Игры"): chats put in it leave
/// the date groups and gather under its header. Which chat is in which
/// folder is stored on the chat (see ChatService.folderKey).
@immutable
class ChatFolder {
  const ChatFolder({required this.id, required this.name, required this.icon});

  final String id;
  final String name;

  /// A key of [icons].
  final String icon;

  /// The icons a folder can have, by key; the keys are what is stored.
  static const List<String> icons = <String>[
    'folder',
    'briefcase',
    'code',
    'gamepad',
    'book',
    'star',
    'heart',
    'music',
    'image',
    'plane',
    'home',
    'flask',
  ];

  ChatFolder copyWith({String? name, String? icon}) =>
      ChatFolder(id: id, name: name ?? this.name, icon: icon ?? this.icon);

  Map<String, Object> toJson() => {'id': id, 'name': name, 'icon': icon};

  static ChatFolder? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final icon = json['icon'];
    return ChatFolder(
      id: id,
      name: name,
      icon: icon is String && icons.contains(icon) ? icon : 'folder',
    );
  }

  /// The folders in [raw], skipping damaged entries; empty for bad JSON.
  static List<ChatFolder> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <ChatFolder>[];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const <ChatFolder>[];
      return List.unmodifiable([
        for (final item in data) ?ChatFolder.fromJson(item),
      ]);
    } on FormatException {
      return const <ChatFolder>[];
    }
  }

  static String encodeList(List<ChatFolder> folders) =>
      jsonEncode([for (final folder in folders) folder.toJson()]);

  @override
  bool operator ==(Object other) =>
      other is ChatFolder &&
      other.id == id &&
      other.name == name &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, name, icon);
}
