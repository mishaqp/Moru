import 'dart:io';

import 'package:path/path.dart' as p;

import '../keep_alive.dart';
import 'mini_app_bridge.dart';
import 'mini_app_fetch.dart';
import 'mini_app_jobs.dart';
import 'mini_app_reminders.dart';
import 'mini_app_runtime.dart';
import 'mini_app_servers.dart';
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
    this.server,
    this.scheduledJobs = const [],
  });

  /// Jobs the page set during the check that were scheduled for the
  /// installed app (see [MiniAppSandbox.adoptJobs]).
  final List<String> scheduledJobs;

  /// Whether the entry page finished loading in time.
  final bool loaded;

  /// The app's server in the check (see [MiniAppServers.status]), when it
  /// has one and a Linux environment was available.
  final Map<String, Object?>? server;

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

  /// The WebView hides the details of script errors on file pages ("Script
  /// error."); the console has them, so they take its place.
  List<String> get _pageErrors {
    final details = [
      for (final line in console)
        if (line.startsWith('error: ')) line,
    ];
    var next = 0;
    return [
      for (final error in pageErrors)
        error == _opaqueError && next < details.length
            ? details[next++]
            : error,
    ];
  }

  static const String _opaqueError = 'error: Script error.';

  Map<String, Object?> toJson() => {
    'ok': ok,
    'loaded': loaded,
    if (pageErrors.isNotEmpty) 'page_errors': _pageErrors,
    if (failedCalls.isNotEmpty) 'failed_moru_calls': failedCalls,
    if (console.isNotEmpty) 'console': console,
    if (visibleContent == 0) 'blank_page': true,
    'server': ?server,
    if (scheduledJobs.isNotEmpty) 'jobs_scheduled': scheduledJobs,
  };
}

/// A throwaway copy of an installed app for a check run. It has its own
/// data and reminders, and its host sends nothing: no notifications, no
/// model requests, no calendar changes. Network reads go out as usual.
class MiniAppSandbox {
  MiniAppSandbox._(
    this._root,
    this.store,
    this.bridge,
    this._server,
    this._runtime,
  );

  static const String testAnswer = 'Test answer from Moru.';

  final Directory _root;
  final MiniAppStore store;
  final MiniAppBridge bridge;
  final MiniAppRuntime? _runtime;

  /// Its own copy of the app's server, with an empty `/data`.
  final ({MiniAppServers servers, MiniAppServerLease lease})? _server;

  MiniApp get app => store.byId(bridge.appId)!;

  /// State and output of the check's server once it listens or failed to
  /// start, or null without one.
  Future<Map<String, Object?>?> serverStatus() async {
    final server = _server;
    if (server == null) return null;
    await server.lease.settled();
    final status = server.servers.status(bridge.appId);
    final output = '${status['output'] ?? ''}';
    return {
      ...status,
      // The tail is what explains a failure.
      'output': output.length <= 3000
          ? output
          : output.substring(output.length - 3000),
    };
  }

  /// Sets the jobs the page set during the check on the installed app, as
  /// its first real opening would, so they can be run right away. Returns
  /// their ids.
  Future<List<String>> adoptJobs(MiniAppJobs installed) async {
    final set = await store.readJobs(bridge.appId);
    final ids = set.keys.toList()..sort();
    for (final id in ids) {
      await installed.set(bridge.appId, id, set[id]);
    }
    return ids;
  }

  /// How long the check's server may take to open its port.
  static const Duration serverStartTimeout = Duration(seconds: 20);

  static Future<MiniAppSandbox> create(
    MiniApp app, {
    MiniAppFetch? fetch,
    MiniAppServerEnvironment? serverEnvironment,
    ProcessKeepAlive? keepAlive,
  }) async {
    final root = await Directory.systemTemp.createTemp('mini-app-check-');
    try {
      await _copy(
        Directory(app.directory),
        Directory(p.join(root.path, app.id)),
      );
      final store = MiniAppStore(root: () async => root);
      await store.load();
      final copy = store.byId(app.id);
      if (copy == null) {
        throw const MiniAppException('not_found', 'The app was not installed.');
      }
      ({MiniAppServers servers, MiniAppServerLease lease})? server;
      if (copy.serverCommand != null && serverEnvironment != null) {
        final servers = MiniAppServers(
          store: store,
          fetch: fetch,
          keepAlive: keepAlive,
          startTimeout: serverStartTimeout,
        );
        server = (
          servers: servers,
          lease: servers.lease(copy, serverEnvironment),
        );
      }
      // Host grants live outside the app directory, so a check never inherits
      // device privileges from the installed app.
      final runtime = copy.formatVersion >= 2
          ? MiniAppRuntime(store: store)
          : null;
      final bridge = MiniAppBridge(
        store: store,
        appId: app.id,
        host: MiniAppHost(
          runtime: runtime,
          invocation: runtime == null
              ? null
              : const MiniAppInvocation(
                  source: MiniAppInvocationSource.background,
                ),
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
          vibrate: (pattern) async {},
          haptic: (kind) async {},
          close: () async {},
          jobs: MiniAppJobs(store: store, scheduler: MiniAppJobScheduler.none),
          server:
              server?.lease.fetch ??
              (_) async => throw const MiniAppException(
                MiniAppBridge.notInCheck,
                'The server does not run in the publish check.',
              ),
          serverUrl:
              server?.lease.url ??
              (_) async => throw const MiniAppException(
                MiniAppBridge.notInCheck,
                'The server does not run in the publish check.',
              ),
        ),
      );
      return MiniAppSandbox._(root, store, bridge, server, runtime);
    } catch (_) {
      await root.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    bridge.dispose();
    await _runtime?.dispose();
    await _server?.lease.release();
    await _root.delete(recursive: true);
  }

  /// Not copied: old versions, and the server's data (dependencies can be
  /// large; the check's server starts with an empty `/data`).
  static const Set<String> _skipped = {'versions', 'server-data'};

  static Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: true)) {
      final relative = p.relative(entity.path, from: from.path);
      if (_skipped.contains(p.split(relative).first)) continue;
      final target = p.join(to.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}
