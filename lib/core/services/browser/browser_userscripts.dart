import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../utils/app_directories.dart';

/// A user script, Tampermonkey style: its `==UserScript==` header says where
/// it runs; the body runs in matching pages of the shared browser.
@immutable
class Userscript {
  const Userscript({
    required this.id,
    required this.name,
    required this.code,
    this.matches = const <String>[],
    this.includes = const <String>[],
    this.excludes = const <String>[],
    this.version,
    this.description,
    this.sourceUrl,
    this.enabled = true,
  });

  /// Reads the header of [code]; null when it has none or no name.
  static Userscript? parse(
    String code, {
    required String id,
    String? sourceUrl,
  }) {
    final start = code.indexOf('// ==UserScript==');
    final end = code.indexOf('// ==/UserScript==');
    if (start < 0 || end < start) return null;
    final meta = <String, List<String>>{};
    for (final line in code.substring(start, end).split('\n')) {
      final match = RegExp(r'^\s*//\s*@([\w:-]+)\s+(.+?)\s*$').firstMatch(line);
      if (match == null) continue;
      meta.putIfAbsent(match.group(1)!, () => <String>[]).add(match.group(2)!);
    }
    final name = meta['name']?.first;
    if (name == null || name.isEmpty) return null;
    return Userscript(
      id: id,
      name: name,
      code: code,
      matches: List.unmodifiable(meta['match'] ?? const <String>[]),
      includes: List.unmodifiable(meta['include'] ?? const <String>[]),
      excludes: List.unmodifiable(meta['exclude'] ?? const <String>[]),
      version: meta['version']?.first,
      description: meta['description']?.first,
      sourceUrl: sourceUrl,
    );
  }

  final String id;
  final String name;
  final String code;
  final List<String> matches;
  final List<String> includes;
  final List<String> excludes;
  final String? version;
  final String? description;
  final String? sourceUrl;
  final bool enabled;

  Userscript copyWith({bool? enabled}) => Userscript(
    id: id,
    name: name,
    code: code,
    matches: matches,
    includes: includes,
    excludes: excludes,
    version: version,
    description: description,
    sourceUrl: sourceUrl,
    enabled: enabled ?? this.enabled,
  );

  /// Whether the script runs on [url].
  bool runsOn(String url) {
    if (excludes.any((pattern) => _glob(pattern, url))) return false;
    return matches.any((pattern) => _matchPattern(pattern, url)) ||
        includes.any((pattern) => _glob(pattern, url));
  }

  /// An `@include`/`@exclude` pattern: `*` is any text, or a `/regex/`.
  static bool _glob(String pattern, String url) {
    if (pattern.length > 2 &&
        pattern.startsWith('/') &&
        pattern.endsWith('/')) {
      try {
        return RegExp(pattern.substring(1, pattern.length - 1)).hasMatch(url);
      } on FormatException {
        return false;
      }
    }
    final regex = RegExp.escape(pattern).replaceAll(r'\*', '.*');
    return RegExp('^$regex\$').hasMatch(url);
  }

  /// An `@match` pattern, Chrome's rules: `scheme://host/path`, where the
  /// scheme may be `*` (http or https), the host may start with `*.`, and
  /// `*` in the path is any text.
  static bool _matchPattern(String pattern, String url) {
    if (pattern == '<all_urls>') {
      return url.startsWith('http://') || url.startsWith('https://');
    }
    final parts = RegExp(
      r'^(\*|https?|file)://([^/]*)(/.*)$',
    ).firstMatch(pattern);
    final uri = Uri.tryParse(url);
    if (parts == null || uri == null) return false;
    final scheme = parts.group(1)!;
    if (scheme == '*'
        ? !(uri.isScheme('http') || uri.isScheme('https'))
        : uri.scheme != scheme) {
      return false;
    }
    final host = parts.group(2)!;
    if (host != '*') {
      if (host.startsWith('*.')) {
        final base = host.substring(2);
        if (uri.host != base && !uri.host.endsWith('.$base')) return false;
      } else if (uri.host != host) {
        return false;
      }
    }
    final path = RegExp.escape(parts.group(3)!).replaceAll(r'\*', '.*');
    final full = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    return RegExp('^$path\$').hasMatch(full.isEmpty ? '/' : full);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'enabled': enabled,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
  };
}

/// The installed user scripts: files in the app's folder, run in every page
/// of the shared browser they match, once per page.
class BrowserUserscripts {
  BrowserUserscripts({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  /// The app's scripts; tests put them in a temporary folder.
  static BrowserUserscripts instance = BrowserUserscripts();

  final Future<Directory> Function() _directory;
  final ValueNotifier<List<Userscript>> scripts =
      ValueNotifier<List<Userscript>>(const <Userscript>[]);
  Future<void>? _loaded;
  Future<void> _writes = Future<void>.value();

  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await AppDirectories.getAppDataDirectory()).path, 'userscripts'),
  );

  Future<void> load() => _loaded ??= _load();

  Future<void> _load() async {
    final dir = await _directory();
    final index = File(p.join(dir.path, 'index.json'));
    if (!await index.exists()) return;
    final List<Userscript> loaded = [];
    try {
      final entries = jsonDecode(await index.readAsString());
      if (entries is! List) return;
      for (final entry in entries) {
        if (entry is! Map || entry['id'] is! String) continue;
        final id = entry['id'] as String;
        final file = File(p.join(dir.path, '$id.user.js'));
        if (!await file.exists()) continue;
        final script = Userscript.parse(
          await file.readAsString(),
          id: id,
          sourceUrl: entry['sourceUrl'] as String?,
        );
        if (script != null) {
          loaded.add(script.copyWith(enabled: entry['enabled'] != false));
        }
      }
    } on FormatException {
      return;
    }
    scripts.value = List.unmodifiable(loaded);
  }

  Future<void> _saveIndex() {
    final json = jsonEncode([for (final s in scripts.value) s.toJson()]);
    final next = _writes.then((_) async {
      final dir = await _directory();
      await dir.create(recursive: true);
      final temp = File(p.join(dir.path, 'index.json.tmp'));
      await temp.writeAsString(json, flush: true);
      await temp.rename(p.join(dir.path, 'index.json'));
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Installs [code] (from [sourceUrl]); a script with the same name is
  /// replaced (an update). Null when the code has no userscript header.
  Future<Userscript?> install(String code, {String? sourceUrl}) async {
    await load();
    final existing = Userscript.parse(code, id: '_', sourceUrl: sourceUrl);
    if (existing == null) return null;
    final same = scripts.value.where((s) => s.name == existing.name).toList();
    final id = same.isNotEmpty
        ? same.first.id
        : 'us${DateTime.now().microsecondsSinceEpoch}';
    final script = Userscript.parse(code, id: id, sourceUrl: sourceUrl)!;
    final dir = await _directory();
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, '$id.user.js'),
    ).writeAsString(code, flush: true);
    scripts.value = List.unmodifiable([
      for (final s in scripts.value)
        if (s.id != id) s,
      script,
    ]);
    await _saveIndex();
    return script;
  }

  /// Downloads a `.user.js` from [url] and installs it.
  Future<Userscript?> installFrom(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final code = await response.transform(utf8.decoder).join();
      return install(code, sourceUrl: url.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await load();
    scripts.value = List.unmodifiable([
      for (final s in scripts.value)
        s.id == id ? s.copyWith(enabled: enabled) : s,
    ]);
    await _saveIndex();
  }

  Future<void> remove(String id) async {
    await load();
    scripts.value = List.unmodifiable([
      for (final s in scripts.value)
        if (s.id != id) s,
    ]);
    final file = File(p.join((await _directory()).path, '$id.user.js'));
    if (await file.exists()) await file.delete();
    await _saveIndex();
  }

  /// Runs the enabled scripts that match [url] in [controller]'s page, each
  /// once per page, with the small GM_* API most scripts use.
  Future<List<String>> runIn(WebViewController controller, String url) async {
    try {
      await load();
    } catch (_) {
      return const <String>[];
    }
    final ran = <String>[];
    for (final script in scripts.value) {
      if (!script.enabled || !script.runsOn(url)) continue;
      try {
        await controller.runJavaScript(wrap(script));
        ran.add(script.name);
      } catch (error) {
        debugPrint('Userscript ${script.name}: $error');
      }
    }
    return ran;
  }

  /// [script]'s code with GM_addStyle, GM_getValue/GM_setValue (kept in the
  /// page's localStorage per script), GM_info and unsafeWindow, guarded to
  /// run once per page.
  @visibleForTesting
  static String wrap(Userscript script) {
    final id = jsonEncode(script.id);
    final info = jsonEncode({
      'script': {'name': script.name, 'version': script.version ?? ''},
      'scriptHandler': 'Moru',
    });
    return '''
(function () {
  window.__moruUserscripts = window.__moruUserscripts || {};
  if (window.__moruUserscripts[$id]) return;
  window.__moruUserscripts[$id] = true;
  const prefix = 'moru_us_' + $id + '_';
  const GM_info = $info;
  const unsafeWindow = window;
  const GM_addStyle = (css) => {
    const style = document.createElement('style');
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
    return style;
  };
  const GM_getValue = (key, fallback) => {
    try {
      const raw = localStorage.getItem(prefix + key);
      return raw === null ? fallback : JSON.parse(raw);
    } catch (e) { return fallback; }
  };
  const GM_setValue = (key, value) => {
    try { localStorage.setItem(prefix + key, JSON.stringify(value)); } catch (e) {}
  };
  const GM_deleteValue = (key) => {
    try { localStorage.removeItem(prefix + key); } catch (e) {}
  };
  const GM_log = (...args) => console.log(...args);
  const GM = {
    info: GM_info,
    addStyle: GM_addStyle,
    getValue: async (k, d) => GM_getValue(k, d),
    setValue: async (k, v) => GM_setValue(k, v),
    deleteValue: async (k) => GM_deleteValue(k)
  };
  try {
${script.code}
  } catch (e) {
    console.error('Userscript ' + GM_info.script.name + ': ' + e);
  }
})();
''';
  }
}
