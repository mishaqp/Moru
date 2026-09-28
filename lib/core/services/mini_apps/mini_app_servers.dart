import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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
/// kept with the app at [dataMount].
class MiniAppServers {
  MiniAppServers({
    required this.store,
    MiniAppFetch? fetch,
    Future<int> Function()? freePort,
    Future<bool> Function(int port)? probe,
    DateTime Function()? now,
    this.startTimeout = const Duration(seconds: 120),
    this.restartDelay = const Duration(seconds: 10),
  }) : _fetch = fetch ?? MiniAppFetch(),
       _freePort = freePort ?? _loopbackPort,
       _probe = probe ?? _accepts,
       _now = now ?? DateTime.now;

  static const String appMount = '/app';
  static const String dataMount = '/data';
  static const int maxLogBytes = 16 * 1024;

  final MiniAppStore store;
  final MiniAppFetch _fetch;
  final Future<int> Function() _freePort;
  final Future<bool> Function(int port) _probe;
  final Duration startTimeout;

  /// A crashed server starts again on a request only this long after its
  /// last start, so a server that dies at once is not restarted in a loop.
  final Duration restartDelay;
  final DateTime Function() _now;
  final Map<String, _Server> _servers = {};

  /// Uses the server of [app] until [MiniAppServerLease.release]; starts it
  /// now, so it is warm by the first request.
  MiniAppServerLease lease(MiniApp app, MiniAppServerEnvironment environment) {
    final command = app.serverCommand;
    if (command == null) return MiniAppServerLease._(this, null);
    var server = _servers[app.id];
    if (server == null || server.stopping) {
      server = _servers[app.id] = _Server(app, command, environment);
      _run(server);
    }
    server.leases++;
    return MiniAppServerLease._(this, server);
  }

  void _run(_Server server) {
    unawaited(server.events?.cancel());
    server
      ..runId = 'mini-app-server-${const Uuid().v4()}'
      ..startedAt = _now()
      ..ready = false
      ..exitCode = null
      ..killed = false;
    final started = server.started = _start(server);
    // Failures reach whoever calls fetch; this only keeps them handled.
    unawaited(started.then<void>((_) {}, onError: (_) {}));
  }

  /// The app's server as last seen since Moru started: running, exit code
  /// and the last [maxLogBytes] of stdout and stderr.
  Map<String, Object?> status(String appId) {
    final server = _servers[appId];
    if (server == null) return {'running': false};
    return {
      'running': server.exitCode == null && !server.stopping,
      'ready': server.ready && server.exitCode == null && !server.stopping,
      'port': ?server.port,
      'exit_code': ?server.exitCode,
      'output': utf8.decode(server.log, allowMalformed: true),
    };
  }

  Future<int> _start(_Server server) async {
    final app = server.app;
    final runtime = await server.environment.runtime();
    if (runtime == null) {
      throw const MiniAppException(
        'linux_unavailable',
        'The app needs the Linux environment: set it up in Moru settings.',
      );
    }
    server.runtime = runtime;
    if (server.stopping) throw _stopped;
    final data = Directory(p.join(app.directory, 'server-data'));
    await data.create(recursive: true);
    final port = server.port = await _freePort();
    final exited = Completer<void>();
    server.events = runtime
        .run(
          CommandRequest(
            runId: server.runId,
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
              ...await server.environment.variables(),
              'PORT': '$port',
              'HOST': '127.0.0.1',
              'MORU_APP_ID': app.id,
              'MORU_DATA': dataMount,
            },
          ),
        )
        .listen(
          (event) {
            switch (event) {
              case CommandOutput():
                server.record(event.bytes);
              case CommandExited():
                server.exitCode = event.exitCode;
                if (!exited.isCompleted) exited.complete();
                if (!server.stopping && !server.killed) {
                  _log(
                    app.id,
                    server,
                    'server exited with code ${event.exitCode}',
                  );
                }
              case CommandStarted():
            }
          },
          onError: (Object error) {
            server.record(utf8.encode('$error\n'));
            if (!exited.isCompleted) exited.complete();
          },
          onDone: () {
            if (!exited.isCompleted) exited.complete();
          },
        );
    // Released while it was being set up.
    if (server.stopping) await runtime.cancel(server.runId);
    final deadline = DateTime.now().add(startTimeout);
    while (!exited.isCompleted && !server.stopping) {
      if (await _probe(port)) {
        server.ready = true;
        return port;
      }
      if (DateTime.now().isAfter(deadline)) {
        _log(
          app.id,
          server,
          'server did not open \$PORT within '
          '${startTimeout.inSeconds} s',
        );
        server.killed = true;
        await runtime.cancel(server.runId);
        throw MiniAppException(
          'server_timeout',
          'The server did not listen on \$PORT ($port) within '
              '${startTimeout.inSeconds} s.',
        );
      }
      await Future.any([
        exited.future,
        Future<void>.delayed(const Duration(milliseconds: 250)),
      ]);
    }
    if (server.stopping) throw _stopped;
    throw MiniAppException(
      'server_exited',
      'The server exited with code ${server.exitCode}: '
          '${_tail(server)}',
    );
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

  Future<Map<String, Object?>> _request(
    _Server server,
    Map<String, dynamic> args,
  ) async {
    // A server that crashed while the app is open starts again, but not
    // right after its last start.
    if (server.exitCode != null && !server.stopping) {
      if (_now().difference(server.startedAt) < restartDelay) {
        throw MiniAppException(
          'server_exited',
          'The server exited with code ${server.exitCode}: ${_tail(server)}',
        );
      }
      _run(server);
    }
    final port = await server.started!;
    return _fetch.fetchLocal(port, args);
  }

  /// Stops the app's running server and starts it again, e.g. after its
  /// code changed. Only while something uses it.
  Future<void> restart(String appId) async {
    final server = _servers[appId];
    if (server == null || server.stopping) return;
    server
      ..killed = true
      ..record(utf8.encode('\n--- restarted ---\n'));
    await server.runtime?.cancel(server.runId);
    _run(server);
  }

  Future<void> _release(_Server server) async {
    if (--server.leases > 0) return;
    // Stays in the map so [status] still shows its last output.
    server.stopping = true;
    await server.runtime?.cancel(server.runId);
    await server.events?.cancel();
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
  _Server(this.app, this.command, this.environment);

  final MiniApp app;
  final String command;
  final MiniAppServerEnvironment environment;
  String runId = '';
  DateTime startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int leases = 0;
  bool stopping = false;

  /// Moru stopped this run itself, e.g. after a start timeout.
  bool killed = false;

  /// The port answered.
  bool ready = false;
  int? port;
  int? exitCode;
  WorkspaceRuntime? runtime;
  Future<int>? started;
  StreamSubscription<CommandEvent>? events;
  List<int> log = const [];

  void record(List<int> bytes) {
    final joined = [...log, ...bytes];
    log = joined.length <= MiniAppServers.maxLogBytes
        ? joined
        : joined.sublist(joined.length - MiniAppServers.maxLogBytes);
  }
}

/// One user of an app's server: the open page or a background job.
class MiniAppServerLease {
  MiniAppServerLease._(this._servers, this._server);

  final MiniAppServers _servers;
  final _Server? _server;
  bool _released = false;

  /// `moru.server.fetch`.
  Future<Map<String, Object?>> fetch(Map<String, dynamic> args) async {
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
    return _servers._request(server, args);
  }

  Future<void> release() async {
    final server = _server;
    if (_released || server == null) return;
    _released = true;
    await _servers._release(server);
  }
}
