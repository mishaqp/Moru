import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import '../../../utils/authentication_uri.dart';

/// A page in the bookmarks or the history.
@immutable
class BrowserPageEntry {
  const BrowserPageEntry({
    required this.url,
    required this.title,
    required this.time,
  });

  factory BrowserPageEntry.fromJson(Map<String, dynamic> json) =>
      BrowserPageEntry(
        url: json['url'] as String,
        title: json['title'] as String? ?? '',
        time: DateTime.fromMillisecondsSinceEpoch(
          (json['time'] as num?)?.toInt() ?? 0,
        ),
      );

  final String url;
  final String title;

  /// When it was bookmarked or last visited.
  final DateTime time;

  Map<String, Object?> toJson() => {
    'url': url,
    'title': title,
    'time': time.millisecondsSinceEpoch,
  };

  /// Whether [query] (any case) is in the title or the address.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        title.toLowerCase().contains(q) ||
        url.toLowerCase().contains(q);
  }
}

/// The shared browser's bookmarks and history, kept on the phone only. The
/// history holds each address once, newest first, for [historyDays] days.
class BrowserLibrary {
  BrowserLibrary({
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : _directory = directory ?? _defaultDirectory,
       _clock = clock ?? DateTime.now;

  /// The app's library; tests put one in a temporary folder.
  static BrowserLibrary instance = BrowserLibrary();

  static const int historyDays = 7;
  static const int maxHistory = 2000;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  final ValueNotifier<List<BrowserPageEntry>> bookmarks =
      ValueNotifier<List<BrowserPageEntry>>(const <BrowserPageEntry>[]);
  final ValueNotifier<List<BrowserPageEntry>> history =
      ValueNotifier<List<BrowserPageEntry>>(const <BrowserPageEntry>[]);

  Future<void>? _loaded;
  Future<void> _writes = Future<void>.value();

  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await AppDirectories.getAppDataDirectory()).path, 'browser'),
  );

  /// Reads the saved lists once; every other method waits for it.
  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    bookmarks.value = await _read('bookmarks.json');
    final cutoff = _clock().subtract(const Duration(days: historyDays));
    history.value = [
      for (final entry in await _read('history.json'))
        if (entry.time.isAfter(cutoff)) entry,
    ];
  }

  Future<List<BrowserPageEntry>> _read(String name) async {
    try {
      final file = File(p.join((await _directory()).path, name));
      if (!await file.exists()) return const <BrowserPageEntry>[];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return const <BrowserPageEntry>[];
      return List.unmodifiable([
        for (final item in data)
          if (item is Map<String, dynamic> && item['url'] is String)
            BrowserPageEntry.fromJson(item),
      ]);
    } on FormatException {
      // A damaged file starts over rather than breaking the browser.
      return const <BrowserPageEntry>[];
    } on FileSystemException {
      return const <BrowserPageEntry>[];
    }
  }

  /// Saves [entries] as [name]; writes run one at a time, each through a
  /// temporary file, so a crash never leaves half a file.
  Future<void> _save(String name, List<BrowserPageEntry> entries) {
    final json = jsonEncode([for (final entry in entries) entry.toJson()]);
    final next = _writes.then((_) async {
      final dir = await _directory();
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, name));
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json, flush: true);
      await temp.rename(file.path);
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static bool _web(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  /// Notes a visit to [url]: it moves to the top of the history.
  Future<void> recordVisit(String url, String? title) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        isAuthenticationUri(uri)) {
      return;
    }
    await load();
    final now = _clock();
    final cutoff = now.subtract(const Duration(days: historyDays));
    final next = <BrowserPageEntry>[
      BrowserPageEntry(url: url, title: title?.trim() ?? '', time: now),
      for (final entry in history.value)
        if (entry.url != url && entry.time.isAfter(cutoff)) entry,
    ];
    history.value = List.unmodifiable(next.take(maxHistory));
    await _save('history.json', history.value);
  }

  bool isBookmarked(String? url) =>
      url != null && bookmarks.value.any((entry) => entry.url == url);

  /// Bookmarks [url], or removes its bookmark; true when it is bookmarked
  /// afterwards.
  Future<bool> toggleBookmark(String url, String? title) async {
    await load();
    if (isBookmarked(url)) {
      await removeBookmark(url);
      return false;
    }
    if (!_web(url)) return false;
    bookmarks.value = List.unmodifiable([
      BrowserPageEntry(url: url, title: title?.trim() ?? '', time: _clock()),
      ...bookmarks.value,
    ]);
    await _save('bookmarks.json', bookmarks.value);
    return true;
  }

  Future<void> removeBookmark(String url) async {
    await load();
    bookmarks.value = List.unmodifiable([
      for (final entry in bookmarks.value)
        if (entry.url != url) entry,
    ]);
    await _save('bookmarks.json', bookmarks.value);
  }

  Future<void> removeFromHistory(String url) async {
    await load();
    history.value = List.unmodifiable([
      for (final entry in history.value)
        if (entry.url != url) entry,
    ]);
    await _save('history.json', history.value);
  }

  Future<void> clearHistory() async {
    await load();
    history.value = const <BrowserPageEntry>[];
    await _save('history.json', history.value);
  }
}
