import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../keep_alive.dart';
import '../mobile_background.dart';
import '../workspace/workspace_runtime.dart';
import 'mini_app_fetch.dart';
import 'mini_app_store.dart';

/// The Linux environment the servers run in.
class MiniAppServerEnvironment {
  const MiniAppServerEnvironment({
    required this.runtime,
    required this.variables,
  });

  /// The ready runtime, or null when the Linux environment is not set up.
  final Future<WorkspaceRuntime?> Function() runtime;

  /// Environment variables from Moru's environment settings.
  final Future<Map<String, String>> Function() variables;
}

/// Servers of mini apps (`server.command` in moru-app.json). A server runs
/// in the Linux environment while something uses the app, the open page or a
/// background job, and stops with the last of them. It gets a free port in
/// `$PORT`, the app's files read-only at [appMount] and a writable folder
/// kept with the app at [dataMount], and a secret in `$MORU_SERVER_TOKEN`:
/// the page's requests carry it (see [MiniAppServerLease.url]), so the
/// server can refuse other apps of the phone that find its port.
class MiniAppServers {
  MiniAppServers({
    required this.store,
    MiniAppFetch? fetch,
    Future<int> Function()? freePort,
    Future<bool> Function(int port)? probe,
    DateTime Function()? now,
    ProcessKeepAlive? keepAlive,
    this.startTimeout = const Duration(seconds: 120),
    this.restartDelay = const Duration(seconds: 10),
  }) : _fetch = fetch ?? MiniAppFetch(),
       _freePort = freePort ?? _loopbackPort,
       _probe = probe ?? _accepts,
       _now = now ?? DateTime.now,
       _keepAliveOverride = keepAlive;

  static const String appMount = '/app';
  static const String dataMount = '/data';
  static const int maxLogBytes = 16 * 1024;

  /// The query parameter [MiniAppServerLease.url] adds; `moru.server.fetch`
  /// sends the token in [MiniAppFetch.tokenHeader] instead.
  static const String tokenParameter = 'moru_token';

  final MiniAppStore store;
  final MiniAppFetch _fetch;
  final Future<int> Function() _freePort;
  final Future<bool> Function(int port) _probe;
  final Duration startTimeout;

  /// A crashed server starts again on a request only this long after its
  /// last start, so a server that dies at once is not restarted in a loop.
  final Duration restartDelay;
  final DateTime Function() _now;
  final ProcessKeepAlive? _keepAliveOverride;
  ProcessKeepAlive get _keepAlive =>
      _keepAliveOverride ?? ProcessKeepAlive.instance;
  final Map<String, _Server> _servers = {};

  /// Uses the server of [app] until [MiniAppServerLease.release]; starts it
  /// now, so it is warm by the first request.
  MiniAppServerLease lease(MiniApp app, MiniAppServerEnvironment environment) {
    final command = app.serverCommand;
    var server = _servers[app.id];
    if (server != null &&
        (!identical(server.app, app) || app.formatVersion >= 2)) {
      // An updated app cannot inherit a process or its execution mode from
      // a previously installed version (including a legacy root server).
      server.stopping = true;
      unawaited(_stopRun(server.run!).catchError((_) {}));
    }
    if (command == null) return MiniAppServerLease._(this, null);
    if (app.formatVersion >= 2) {
      // PRoot shares Moru's Android UID, /proc and mutable rootfs. It cannot
      // enforce this app's independent device and host-file grants.
      return MiniAppServerLease._(
        this,
        null,
        denial: const MiniAppException(
          'restricted_server_denied',
          'Restricted apps cannot run arbitrary workspace server commands.',
        ),
      );
    }
    if (server == null || server.stopping) {
      server = _servers[app.id] = _Server(
        app,
        command,
        environment,
        store.generationFor(app.id),
      );
      _run(server);
    }
    server.leases++;
    return MiniAppServerLease._(this, server);
  }

  void _run(_Server server) {
    final run = server.run = _ServerRun(_now());
    final started = run.started = _start(server, run);
    // Failures reach whoever calls fetch; this only keeps them handled.
    unawaited(started.then<void>((_) {}, onError: (_) {}));
  }

  /// The app's server as last seen since Moru started: running, exit code
  /// and the last [maxLogBytes] of stdout and stderr.
  Map<String, Object?> status(String appId) {
    final server = _servers[appId];
    if (server == null) return {'running': false};
    final run = server.run!;
    return {
      'running': !run.terminal && !run.stopping && !server.stopping,
      'ready': run.ready && !run.terminal && !run.stopping && !server.stopping,
      'port': ?run.port,
      'exit_code': ?run.exitCode,
      'error': ?run.error,
      'output': utf8.decode(server.log, allowMalformed: true),
    };
  }

  Future<int> _start(_Server server, _ServerRun run) async {
    run.nativeStops = _keepAlive.released.listen((id) {
      if (id != run.id) return;
      // A delayed release for an earlier process must not stop its successor.
      if (identical(server.run, run)) server.stopping = true;
      unawaited(_stopRun(run).catchError((_) {}));
    });
    try {
      run.holdAttempted = true;
      await _keepAlive.hold(
        run.id,
        MobileBackgroundCoordinator.instance.backgroundServerRunningText,
      );
      _checkStopped(server, run);
      return await _launch(server, run);
    } on ProcessKeepAliveException {
      run.error = ProcessKeepAliveException.code;
      await _finishRun(run);
      throw MiniAppException(
        ProcessKeepAliveException.code,
        MobileBackgroundCoordinator
            .instance
            .backgroundProtectionUnavailableText,
      );
    } catch (error) {
      if (error is! MiniAppException || error.code != _stopped.code) {
        run.error = error is MiniAppException
            ? error.code
            : 'server_start_failed';
      }
      await _finishRun(run);
      rethrow;
    }
  }

  void _checkStopped(_Server server, _ServerRun run) {
    if (!identical(store.byId(server.app.id), server.app) ||
        store.generationFor(server.app.id) != server.generation) {
      server.stopping = true;
      if (run.launched && !run.terminal) {
        unawaited(_stopRun(run).catchError((_) {}));
      }
    }
    if (server.stopping || run.stopping) throw _stopped;
  }

  Future<int> _launch(_Server server, _ServerRun run) async {
    final app = server.app;
    final runtime = await server.environment.runtime();
    _checkStopped(server, run);
    if (runtime == null) {
      throw const MiniAppException(
        'linux_unavailable',
        'The app needs the Linux environment: set it up in Moru settings.',
      );
    }
    run.runtime = runtime;
    final data = Directory(p.join(app.directory, 'server-data'));
    await data.create(recursive: true);
    _checkStopped(server, run);
    final port = run.port = await _freePort();
    _checkStopped(server, run);
    final variables = await server.environment.variables();
    _checkStopped(server, run);
    run.launched = true;
    run.events = runtime
        .run(
          CommandRequest(
            runId: run.id,
            isCancelled: () => server.stopping || run.stopping,
            command: server.command,
            cwd: appMount,
            // Unlimited lifetime; the runtime only allows it with stdin kept
            // open, as for protocol servers.
            timeout: Duration.zero,
            keepStdinOpen: true,
            mounts: [
              Mount(host: app.codeDirectory, guest: appMount, readOnly: true),
              Mount(host: data.path, guest: dataMount),
            ],
            env: {
              ...variables,
              'PORT': '$port',
              'HOST': '127.0.0.1',
              'MORU_APP_ID': app.id,
              'MORU_DATA': dataMount,
              'MORU_SERVER_TOKEN': server.token,
            },
          ),
        )
        .listen(
          (event) {
            if (run.terminal) return;
            switch (event) {
              case CommandOutput():
                server.record(event.bytes);
              case CommandExited():
                run.exitCode = event.exitCode;
                if (!server.stopping && !run.stopping) {
                  _log(
                    app.id,
                    server,
                    'server exited with code ${event.exitCode}',
                  );
                }
                unawaited(_finishRun(run));
              case CommandStarted():
            }
          },
          onError: (Object error) {
            server.record(utf8.encode('$error\n'));
            run.error = 'server_failed';
            unawaited(_finishRun(run));
          },
          onDone: () {
            unawaited(_finishRun(run));
          },
        );
    // Released while it was being set up.
    if (server.stopping || run.stopping) await _stopRun(run);
    final deadline = DateTime.now().add(startTimeout);
    while (!run.terminal && !server.stopping && !run.stopping) {
      if (await _probe(port)) {
        _checkStopped(server, run);
        if (run.terminal) break;
        run.ready = true;
        return port;
      }
      if (DateTime.now().isAfter(deadline)) {
        _log(
          app.id,
          server,
          'server did not open \$PORT within '
          '${startTimeout.inSeconds} s',
        );
        await _stopRun(run);
        throw MiniAppException(
          'server_timeout',
          'The server did not listen on \$PORT ($port) within '
              '${startTimeout.inSeconds} s.',
        );
      }
      await Future.any([
        run.exited.future,
        Future<void>.delayed(const Duration(milliseconds: 250)),
      ]);
    }
    _checkStopped(server, run);
    throw MiniAppException(
      'server_exited',
      'The server exited with code ${run.exitCode}: '
          '${_tail(server)}',
    );
  }

  Future<void> _finishRun(_ServerRun run) {
    if (run.terminal) return run.finished.future;
    run.terminal = true;
    run.exited.complete();
    unawaited(() async {
      try {
        if (run.holdAttempted) await _keepAlive.release(run.id);
      } catch (_) {
        // The process has ended. A platform release failure must not make
        // callers believe the server is still alive.
      } finally {
        await run.nativeStops?.cancel();
        await run.events?.cancel();
        run.finished.complete();
      }
    }());
    return run.finished.future;
  }

  Future<void> _stopRun(_ServerRun run) async {
    run.stopping = true;
    if (run.launched && !run.terminal) {
      // Native cancel acknowledges the signal, not process exit. Keep the
      // owner and event subscription until the runtime actually finishes.
      await (run.cancelling ??= run.runtime!.cancel(run.id));
    }
    await run.finished.future;
  }

  static const MiniAppException _stopped = MiniAppException(
    'server_stopped',
    'The app was closed.',
  );

  void _log(String appId, _Server server, String reason) {
    final tail = _tail(server);
    unawaited(
      store
          .logError(appId, 'server: $reason${tail.isEmpty ? '' : '\n$tail'}')
          .catchError((_) {}),
    );
  }

  static String _tail(_Server server) {
    final text = utf8.decode(server.log, allowMalformed: true).trim();
    return text.length <= 1500 ? text : text.substring(text.length - 1500);
  }

  /// The port of [server] once it listens.
  Future<int> _port(_Server server) async {
    _checkStopped(server, server.run!);
    var run = server.run!;
    // A server that crashed while the app is open starts again, but not
    // right after its last start.
    if (run.terminal) {
      if (_now().difference(run.startedAt) < restartDelay) {
        throw MiniAppException(
          'server_exited',
          'The server exited with code ${run.exitCode}: ${_tail(server)}',
        );
      }
      await run.finished.future;
      _checkStopped(server, run);
      if (identical(server.run, run)) _run(server);
      run = server.run!;
    }
    return run.started;
  }

  Future<Map<String, Object?>> _request(
    _Server server,
    Map<String, dynamic> args,
  ) async => _fetch.fetchLocal(await _port(server), args, token: server.token);

  Future<String> _url(_Server server, String path) async {
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw const MiniAppException(
        'invalid_path',
        'path must start with "/", e.g. "/stream".',
      );
    }
    final port = await _port(server);
    final uri = Uri.parse('http://127.0.0.1:$port$path');
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParametersAll,
            tokenParameter: server.token,
          },
        )
        .toString();
  }

  /// Stops the app's running server and starts it again, e.g. after its
  /// code changed. Only while something uses it.
  Future<void> restart(String appId) async {
    final server = _servers[appId];
    if (server == null || server.stopping) return;
    final pending = server.restarting;
    if (pending != null) return pending;
    final restarting = server.restarting = _restart(server);
    try {
      await restarting;
    } finally {
      if (identical(server.restarting, restarting)) server.restarting = null;
    }
  }

  Future<void> _restart(_Server server) async {
    final run = server.run!;
    server.record(utf8.encode('\n--- restarted ---\n'));
    await _stopRun(run);
    if (server.stopping || server.leases == 0 || !identical(server.run, run)) {
      return;
    }
    _run(server);
  }

  Future<void> _release(_Server server) async {
    if (--server.leases > 0) return;
    // Stays in the map so [status] still shows its last output.
    server.stopping = true;
    await _stopRun(server.run!);
  }

  static Future<int> _loopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> _accepts(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }
}

class _Server {
  _Server(this.app, this.command, this.environment, this.generation);

  final MiniApp app;
  final String command;
  final MiniAppServerEnvironment environment;
  final int generation;

  /// Kept across restarts, so a page's URLs only change with the port.
  final String token = _newToken();
  int leases = 0;
  bool stopping = false;
  _ServerRun? run;
  Future<void>? restarting;
  List<int> log = const [];

  static String _newToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  void record(List<int> bytes) {
    final joined = [...log, ...bytes];
    log = joined.length <= MiniAppServers.maxLogBytes
        ? joined
        : joined.sublist(joined.length - MiniAppServers.maxLogBytes);
  }
}

/// Every process owns its own callbacks and foreground holder. None of these
/// identities are reused when the same app starts a replacement server.
class _ServerRun {
  _ServerRun(this.startedAt);

  final String id = 'mini-app-server-${const Uuid().v4()}';
  final DateTime startedAt;
  late final Future<int> started;
  final exited = Completer<void>();
  final finished = Completer<void>();
  bool holdAttempted = false;
  bool launched = false;
  bool stopping = false;
  bool terminal = false;
  bool ready = false;
  int? port;
  int? exitCode;
  String? error;
  WorkspaceRuntime? runtime;
  StreamSubscription<CommandEvent>? events;
  StreamSubscription<String>? nativeStops;
  Future<void>? cancelling;
}

/// One user of an app's server: the open page or a background job.
class MiniAppServerLease {
  MiniAppServerLease._(this._servers, this._server, {this._denial});

  final MiniAppServers _servers;
  final _Server? _server;
  final MiniAppException? _denial;
  bool _released = false;

  /// `moru.server.fetch`.
  Future<Map<String, Object?>> fetch(Map<String, dynamic> args) async =>
      _servers._request(_use(), args);

  /// `moru.server.url`: the address of [path] on the server with its token,
  /// for the page to use directly (an `<img>` stream, a WebSocket, fetch),
  /// once the server listens.
  Future<String> url(String path) async => _servers._url(_use(), path);

  _Server _use() {
    if (_denial != null) throw _denial;
    final server = _server;
    if (server == null) {
      throw const MiniAppException(
        'no_server',
        'Add "server": {"command": "..."} to moru-app.json.',
      );
    }
    if (_released) {
      throw const MiniAppException('server_stopped', 'The app was closed.');
    }
    return server;
  }

  /// Completes once the server listens or its start failed; the reason of a
  /// failure is in [MiniAppServers.status].
  Future<void> settled() async {
    try {
      await _server?.run?.started;
    } catch (_) {}
  }

  Future<void> release() async {
    final server = _server;
    if (_released || server == null) return;
    _released = true;
    await _servers._release(server);
  }
}
