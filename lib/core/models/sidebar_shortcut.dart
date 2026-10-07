import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A card at the bottom of the sidebar: a mini app or a web page, opened
/// with one tap.
@immutable
class SidebarShortcut {
  const SidebarShortcut.miniApp(this.target) : web = false, title = '';

  const SidebarShortcut.webPage(this.target, this.title) : web = true;

  /// True for a web page, false for a mini app.
  final bool web;

  /// The mini app's id, or the page's address.
  final String target;

  /// The page's title when it was added; mini apps show their current name.
  final String title;

  String encode() => jsonEncode({
    'kind': web ? 'web' : 'app',
    'target': target,
    if (web) 'title': title,
  });

  /// The shortcut in [raw], or null when it is damaged.
  static SidebarShortcut? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final target = json['target'];
      if (target is! String || target.isEmpty) return null;
      return switch (json['kind']) {
        'app' => SidebarShortcut.miniApp(target),
        'web' => SidebarShortcut.webPage(
          target,
          json['title'] is String ? json['title'] as String : '',
        ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SidebarShortcut && other.web == web && other.target == target;

  @override
  int get hashCode => Object.hash(web, target);
}
