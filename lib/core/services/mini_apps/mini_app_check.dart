import 'dart:io';

import 'package:path/path.dart' as p;

import 'mini_app_bridge.dart';
import 'mini_app_fetch.dart';
import 'mini_app_reminders.dart';
import 'mini_app_store.dart';

/// What opening a mini app out of sight found, for the agent that just
/// published it.
class MiniAppCheckReport {
  const MiniAppCheckReport({
    required this.loaded,
    this.pageErrors = const [],
    this.console = const [],
    this.failedCalls = const [],
    this.visibleContent,
  });

  /// Whether the entry page finished loading in time.
  final bool loaded;

  /// Script errors, rejected promises and files that failed to load.
  final List<String> pageErrors;

  /// `console.error` and `console.warn` output.
  final List<String> console;

  /// `moru.*` calls that failed.
  final List<String> failedCalls;

  /// Characters of text plus images, canvases and videos on the page after
  /// it settled; 0 means the screen stayed blank.
  final int? visibleContent;

  bool get ok => loaded && pageErrors.isEmpty && failedCalls.isEmpty;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'loaded': loaded,
    if (pageErrors.isNotEmpty) 'page_errors': pageErrors,
    if (failedCalls.isNotEmpty) 'failed_moru_calls': failedCalls,
    if (console.isNotEmpty) 'console': console,
    if (visibleContent == 0) 'blank_page': true,
  };
}

/// A throwaway copy of an installed app for a check run. It has its own
/// data and reminders, and its host sends nothing: no notifications, no
/// model requests, no calendar changes. Network reads go out as usual.
class MiniAppSandbox {
  MiniAppSandbox._(this._root, this.store, this.bridge);

  static const String testAnswer = 'Test answer from Moru.';

  final Directory _root;
  final MiniAppStore store;
  final MiniAppBridge bridge;

  MiniApp get app => store.byId(bridge.appId)!;

  static Future<MiniAppSandbox> create(
    MiniApp app, {
    MiniAppFetch? fetch,
  }) async {
    final root = await Directory.systemTemp.createTemp('mini-app-check-');
    try {
      await _copy(
        Directory(app.directory),
        Directory(p.join(root.path, app.id)),
      );
      final store = MiniAppStore(root: () async => root);
      await store.load();
      if (store.byId(app.id) == null) {
        throw const MiniAppException('not_found', 'The app was not installed.');
      }
      final bridge = MiniAppBridge(
        store: store,
        appId: app.id,
        host: MiniAppHost(
          ask: (prompt, system) async => testAnswer,
          notify: (title, body) async {},
          reminders: MiniAppReminders(
            store: store,
            schedule:
                ({
                  required id,
                  required appId,
                  required title,
                  required body,
                  required hour,
                  required minute,
                  weekday,
                }) async {},
            cancel: (id) async {},
          ),
          fetch: fetch,
          calendar: (method, args) async =>
              method == 'queryCalendar' ? {'events': []} : {'id': 0},
        ),
      );
      return MiniAppSandbox._(root, store, bridge);
    } catch (_) {
      await root.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() => _root.delete(recursive: true);

  static Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: true)) {
      final target = p.join(to.path, p.relative(entity.path, from: from.path));
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}
