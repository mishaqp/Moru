import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';

/// A mini app the agent built and published: a small web app with its own
/// data, opened inside Moru or from a home screen shortcut.
@immutable
class MiniApp {
  const MiniApp({
    required this.id,
    required this.name,
    required this.directory,
    this.description = '',
    this.entry = 'index.html',
    this.icon,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;

  /// Folder of the installed copy (manifest, app/ and data).
  final String directory;

  /// Entry page, relative to [codeDirectory].
  final String entry;

  /// SVG icon relative to [codeDirectory], or null for the letter icon.
  final String? icon;
  final DateTime updatedAt;

  String get codeDirectory => p.join(directory, 'app');
  String get entryPath => p.join(codeDirectory, entry);
  String? get iconPath => icon == null ? null : p.join(codeDirectory, icon);

  /// Opens the app from a chat reply.
  String get link => MiniAppStore.linkFor(id);

  factory MiniApp.fromJson(String directory, Map<String, dynamic> json) =>
      MiniApp(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        entry: json['entry'] as String? ?? 'index.html',
        icon: json['icon'] as String?,
        directory: directory,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          json['updatedAt'] as int? ?? 0,
        ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'entry': entry,
    'icon': ?icon,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

class MiniAppException implements Exception {
  const MiniAppException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Installed mini apps under the app data directory:
///
/// ```
/// mini_apps/<id>/manifest.json   what Moru knows about the app
/// mini_apps/<id>/app/            copy of the published files
/// mini_apps/<id>/data.json       moru.storage, kept across republishing
/// ```
class MiniAppStore extends ChangeNotifier {
  MiniAppStore({Future<Directory> Function()? root, DateTime Function()? now})
    : _root = root ?? _defaultRoot,
      _now = now ?? DateTime.now;

  static final MiniAppStore instance = MiniAppStore();

  static const String manifestFile = 'moru-app.json';
  static const String bridgeFile = 'moru.js';
  static const int maxFiles = 500;
  static const int maxBytes = 20 * 1024 * 1024;
  static const int maxDataBytes = 5 * 1024 * 1024;
  static const int maxKeyLength = 200;

  /// Folders a build leaves behind that never belong in the published app.
  static const Set<String> skippedDirectories = {
    'node_modules',
    '.git',
    '__pycache__',
  };

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,39}$');

  final Future<Directory> Function() _root;
  final DateTime Function() _now;
  List<MiniApp> _apps = const [];
  bool _loaded = false;
  Future<void>? _loading;
  final Map<String, Future<void>> _writes = {};

  static Future<Directory> _defaultRoot() async {
    final base = await AppDirectories.getAppDataDirectory();
    return Directory(p.join(base.path, 'mini_apps'));
  }

  static String linkFor(String id) => 'kelivo://app/$id';

  /// The app id in a `kelivo://app/<id>` link, or null for other links.
  static String? idFromLink(String url) {
    final match = RegExp(
      r'^kelivo://app/([a-z0-9][a-z0-9-]{0,39})/?$',
      caseSensitive: false,
    ).firstMatch(url.trim());
    return match?.group(1)?.toLowerCase();
  }

  /// Installed apps, most recently updated first.
  List<MiniApp> get apps => _apps;
  bool get loaded => _loaded;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final root = await _root();
    final apps = <MiniApp>[];
    if (await root.exists()) {
      await for (final entry in root.list()) {
        if (entry is! Directory) continue;
        final manifest = File(p.join(entry.path, 'manifest.json'));
        if (!await manifest.exists()) continue;
        try {
          apps.add(
            MiniApp.fromJson(
              entry.path,
              jsonDecode(await manifest.readAsString()) as Map<String, dynamic>,
            ),
          );
        } catch (e) {
          debugPrint('[MiniApps] skipping ${entry.path}: $e');
        }
      }
    }
    _apps = _sorted(apps);
    _loaded = true;
    notifyListeners();
  }

  MiniApp? byId(String id) {
    for (final app in _apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  /// Installs or updates the app in [sourceDir], which holds
  /// `moru-app.json`. Returns the app and whether it replaced an older copy.
  /// Stored data survives an update.
  Future<({MiniApp app, bool updated, int files, int bytes})> install(
    Directory sourceDir,
  ) async {
    await load();
    final manifestSource = File(p.join(sourceDir.path, manifestFile));
    if (!await manifestSource.exists()) {
      throw const MiniAppException(
        'missing_manifest',
        'The folder has no $manifestFile.',
      );
    }
    final Map<String, dynamic> manifest;
    try {
      manifest = Map<String, dynamic>.from(
        jsonDecode(await manifestSource.readAsString()) as Map,
      );
    } catch (e) {
      throw MiniAppException('invalid_manifest', '$manifestFile: $e');
    }
    final id = '${manifest['id'] ?? ''}'.trim();
    final name = '${manifest['name'] ?? ''}'.trim();
    if (!_idPattern.hasMatch(id)) {
      throw const MiniAppException(
        'invalid_id',
        '"id" must be 1-40 lowercase letters, digits or dashes, '
            'starting with a letter or digit.',
      );
    }
    if (name.isEmpty || name.length > 40) {
      throw const MiniAppException(
        'invalid_name',
        '"name" must be 1-40 characters.',
      );
    }
    final entry = _relative(manifest['entry'], fallback: 'index.html')!;
    final icon = _relative(manifest['icon'], fallback: null);

    final files = await _collect(sourceDir);
    final names = files.map((f) => f.relative).toSet();
    if (!names.contains(entry)) {
      throw MiniAppException('missing_entry', 'Entry file "$entry" not found.');
    }
    if (icon != null && !names.contains(icon)) {
      throw MiniAppException('missing_icon', 'Icon file "$icon" not found.');
    }
    if (icon != null && p.extension(icon).toLowerCase() != '.svg') {
      throw const MiniAppException('invalid_icon', 'The icon must be an SVG.');
    }
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);

    final root = await _root();
    final directory = Directory(p.join(root.path, id));
    final previous = byId(id);
    // Build the new copy beside the old one so a failure keeps the old app.
    final staging = Directory(p.join(root.path, '.$id.staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    final code = Directory(p.join(staging.path, 'app'));
    await code.create(recursive: true);
    for (final file in files) {
      final target = File(p.join(code.path, file.relative));
      await target.parent.create(recursive: true);
      await file.file.copy(target.path);
    }
    await File(p.join(code.path, bridgeFile)).writeAsString(moruBridgeScript);
    final entryFile = File(p.join(code.path, entry));
    if (_isHtml(entry)) {
      await entryFile.writeAsString(
        withBridgeScript(await entryFile.readAsString(), entry),
      );
    }

    final app = MiniApp(
      id: id,
      name: name,
      description: '${manifest['description'] ?? ''}'.trim(),
      entry: entry,
      icon: icon,
      directory: directory.path,
      updatedAt: _now(),
    );
    await File(
      p.join(staging.path, 'manifest.json'),
    ).writeAsString(jsonEncode(app.toJson()));

    await directory.create(recursive: true);
    final oldCode = Directory(p.join(directory.path, 'app'));
    if (await oldCode.exists()) await oldCode.delete(recursive: true);
    await code.rename(oldCode.path);
    await File(
      p.join(staging.path, 'manifest.json'),
    ).rename(p.join(directory.path, 'manifest.json'));
    await staging.delete(recursive: true);

    _apps = _sorted([
      for (final other in _apps)
        if (other.id != id) other,
      app,
    ]);
    notifyListeners();
    return (
      app: app,
      updated: previous != null,
      files: files.length,
      bytes: bytes,
    );
  }

  /// Removes the app, its files and its data.
  Future<void> delete(String id) async {
    await load();
    final app = byId(id);
    if (app == null) return;
    await _writes[id];
    final directory = Directory(app.directory);
    if (await directory.exists()) await directory.delete(recursive: true);
    _apps = [
      for (final other in _apps)
        if (other.id != id) other,
    ];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // moru.storage
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _readData(MiniApp app) async {
    final file = File(p.join(app.directory, 'data.json'));
    if (!await file.exists()) return <String, dynamic>{};
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<Object?> storageGet(String id, String key) async =>
      (await _readData(_require(id)))[key];

  Future<List<String>> storageKeys(String id) async =>
      (await _readData(_require(id))).keys.toList();

  Future<void> storageSet(String id, String key, Object? value) {
    if (key.isEmpty || key.length > maxKeyLength) {
      throw const MiniAppException(
        'invalid_key',
        'Keys must be 1-$maxKeyLength characters.',
      );
    }
    return _update(id, (data) => data[key] = value);
  }

  Future<void> storageRemove(String id, String key) =>
      _update(id, (data) => data.remove(key));

  /// Writes are queued per app so two quick saves cannot overwrite each other.
  Future<void> _update(String id, void Function(Map<String, dynamic>) change) {
    final app = _require(id);
    final previous = _writes[id] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      final data = await _readData(app);
      change(data);
      final encoded = jsonEncode(data);
      if (utf8.encode(encoded).length > maxDataBytes) {
        throw const MiniAppException(
          'storage_full',
          'App data may not exceed 5 MB.',
        );
      }
      final file = File(p.join(app.directory, 'data.json'));
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    });
    _writes[id] = next;
    return next;
  }

  MiniApp _require(String id) {
    final app = byId(id);
    if (app == null) {
      throw MiniAppException('not_found', 'No mini app "$id".');
    }
    return app;
  }

  static List<MiniApp> _sorted(List<MiniApp> apps) =>
      apps..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  static bool _isHtml(String path) =>
      const {'.html', '.htm'}.contains(p.extension(path).toLowerCase());

  /// A safe relative path from the manifest, or [fallback] when absent.
  static String? _relative(Object? raw, {required String? fallback}) {
    final value = raw == null ? '' : '$raw'.trim();
    if (value.isEmpty) return fallback;
    final normalized = p.posix.normalize(value.replaceAll(r'\', '/'));
    if (p.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw MiniAppException('invalid_path', '"$value" leaves the app folder.');
    }
    return normalized;
  }

  static Future<List<({File file, String relative, int size})>> _collect(
    Directory sourceDir,
  ) async {
    final files = <({File file, String relative, int size})>[];
    var bytes = 0;
    Future<void> walk(Directory dir) async {
      await for (final entry in dir.list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        if (entry is Directory) {
          if (!skippedDirectories.contains(name)) await walk(entry);
          continue;
        }
        if (entry is! File) continue;
        final relative = p.posix.joinAll(
          p.split(p.relative(entry.path, from: sourceDir.path)),
        );
        if (relative == manifestFile || relative == bridgeFile) continue;
        final size = await entry.length();
        bytes += size;
        files.add((file: entry, relative: relative, size: size));
        if (files.length > maxFiles) {
          throw const MiniAppException(
            'too_many_files',
            'A mini app may have at most $maxFiles files.',
          );
        }
        if (bytes > maxBytes) {
          throw const MiniAppException(
            'too_large',
            'A mini app may be at most 20 MB.',
          );
        }
      }
    }

    await walk(sourceDir);
    return files;
  }

  /// [html] with the bridge script loaded before any app script, unless the
  /// page already includes it.
  @visibleForTesting
  static String withBridgeScript(String html, String entry) {
    if (html.contains(bridgeFile)) return html;
    final depth = p.posix.split(entry).length - 1;
    final src = '${'../' * depth}$bridgeFile';
    final tag = '<script src="$src"></script>';
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    if (head != null) {
      return html.replaceRange(head.end, head.end, tag);
    }
    return '$tag$html';
  }

  /// `window.moru` for the page. Calls go through the `MoruBridge` channel
  /// as `{id, method, args}` and resolve when Moru calls `__moruReply`.
  static const String moruBridgeScript = r'''
(function () {
  if (window.moru) return;
  var pending = {};
  var next = 0;
  function call(method, args) {
    return new Promise(function (resolve, reject) {
      var id = ++next;
      pending[id] = { resolve: resolve, reject: reject };
      MoruBridge.postMessage(JSON.stringify({ id: id, method: method, args: args || {} }));
    });
  }
  window.__moruReply = function (id, ok, value) {
    var request = pending[id];
    if (!request) return;
    delete pending[id];
    if (ok) request.resolve(value);
    else request.reject(new Error(value));
  };
  window.moru = {
    storage: {
      get: function (key) { return call('storage.get', { key: key }); },
      set: function (key, value) { return call('storage.set', { key: key, value: value }); },
      remove: function (key) { return call('storage.remove', { key: key }); },
      keys: function () { return call('storage.keys'); }
    },
    app: {
      info: function () { return call('app.info'); }
    }
  };
})();
''';
}
