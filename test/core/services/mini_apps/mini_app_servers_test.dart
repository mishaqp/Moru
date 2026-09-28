import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_check.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_servers.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/home/services/mini_app_data_tool.dart';

/// Runs nothing: each request gets a stream the test writes events to.
class _Runtime extends WorkspaceRuntime {
  final requests = <CommandRequest>[];
  final processes = <String, StreamController<CommandEvent>>{};
  final cancelled = <String>[];

  @override
  Future<RuntimeStatus> status() async =>
      const RuntimeStatus(ready: true, engine: 'fake', sandboxed: true);

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    final process = processes[request.runId] = StreamController();
    process.add(const CommandStarted(pid: 1));
    return process.stream;
  }

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    exit(runId, 137);
  }

  void output(String runId, String text) => processes[runId]!.add(
    CommandOutput(OutputStreamKind.stderr, utf8.encode(text)),
  );

  void exit(String runId, int code) {
    final process = processes[runId]!;
    if (process.isClosed) return;
    process.add(
      CommandExited(
        exitCode: code,
        timedOut: false,
        cancelled: code == 137,
        interrupted: false,
        duration: Duration.zero,
      ),
    );
    unawaited(process.close());
  }
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late _Runtime runtime;
  late HttpServer http;
  late MiniAppServers servers;
  late MiniAppServerEnvironment environment;
  var listening = false;
  late DateTime clock;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-servers-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'installed')),
    );
    runtime = _Runtime();
    // Stands in for the app's server: it "listens" once the test says so.
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      if (request.uri.path == '/away') {
        request.response
          ..statusCode = 302
          ..headers.set('location', 'https://example.com/');
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'method': request.method,
              'path': request.uri.toString(),
              'body': await utf8.decodeStream(request),
            }),
          );
      }
      await request.response.close();
    });
    listening = false;
    clock = DateTime(2026, 9, 28, 2);
    servers = MiniAppServers(
      store: store,
      freePort: () async => http.port,
      probe: (_) async => listening,
      now: () => clock,
      startTimeout: const Duration(seconds: 5),
    );
    environment = MiniAppServerEnvironment(
      runtime: () async => runtime,
      variables: () async => {'LANG': 'ru_RU.UTF-8'},
    );
  });
  tearDown(() async {
    await http.close(force: true);
    await temp.delete(recursive: true);
  });

  Future<MiniApp> install({String? command = 'python3 server.py'}) async {
    final src = Directory(p.join(temp.path, 'src'));
    if (await src.exists()) await src.delete(recursive: true);
    await src.create();
    await File(p.join(src.path, MiniAppStore.manifestFile)).writeAsString(
      jsonEncode({
        'id': 'notes',
        'name': 'Notes',
        if (command != null) 'server': {'command': command},
      }),
    );
    await File(p.join(src.path, 'index.html')).writeAsString('<p>');
    await File(p.join(src.path, 'server.py')).writeAsString('print(1)');
    await Directory(p.join(src.path, '.venv', 'bin')).create(recursive: true);
    await File(p.join(src.path, '.venv', 'bin', 'python')).writeAsString('x');
    return (await store.install(src)).app;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  test('the manifest server is kept; bad commands are refused', () async {
    final app = await install();
    expect(app.serverCommand, 'python3 server.py');
    expect(app.toJson()['server'], {'command': 'python3 server.py'});
    // A virtualenv is not published.
    expect(
      File(p.join(app.codeDirectory, '.venv', 'bin', 'python')).existsSync(),
      isFalse,
    );
    for (final bad in ['', '  ', 'x' * 501]) {
      await expectLater(
        install(command: bad),
        throwsA(
          isA<MiniAppException>().having(
            (e) => e.code,
            'code',
            'invalid_server',
          ),
        ),
      );
    }
  });

  test('one server for all users, started with the app files, a data folder '
      'and a port; requests reach it; it stops with the last user', () async {
    final app = await install();
    final page = servers.lease(app, environment);
    final job = servers.lease(app, environment);
    await until(() => runtime.requests.isNotEmpty);
    expect(runtime.requests, hasLength(1));
    final request = runtime.requests.single;
    expect(request.command, 'python3 server.py');
    expect(request.cwd, MiniAppServers.appMount);
    expect(request.timeout, Duration.zero);
    // Without stdin kept open the runtime would stop it at once.
    expect(request.keepStdinOpen, isTrue);
    expect(request.mounts, [
      Mount(host: app.codeDirectory, guest: '/app', readOnly: true),
      Mount(host: p.join(app.directory, 'server-data'), guest: '/data'),
    ]);
    expect(
      Directory(p.join(app.directory, 'server-data')).existsSync(),
      isTrue,
    );
    expect(request.env, {
      'LANG': 'ru_RU.UTF-8',
      'PORT': '${http.port}',
      'HOST': '127.0.0.1',
      'MORU_APP_ID': 'notes',
      'MORU_DATA': '/data',
    });

    // Requests wait until the port answers.
    final pending = page.fetch({
      'path': '/api/items?x=1',
      'method': 'POST',
      'body': '{"a":1}',
    });
    runtime.output(request.runId, 'Serving on 127.0.0.1\n');
    listening = true;
    final response = await pending;
    expect(response['status'], 200);
    expect(jsonDecode(response['body'] as String), {
      'method': 'POST',
      'path': '/api/items?x=1',
      'body': '{"a":1}',
    });
    expect(servers.status('notes'), containsPair('running', true));

    await page.release();
    expect(runtime.cancelled, isEmpty);
    await job.release();
    expect(runtime.cancelled, [request.runId]);
    final status = servers.status('notes');
    expect(status['running'], isFalse);
    expect(status['output'], 'Serving on 127.0.0.1\n');
    // A released lease cannot be used again.
    await expectLater(
      page.fetch({'path': '/'}),
      throwsA(isA<MiniAppException>()),
    );
    // No journal entry for a server Moru stopped itself.
    expect(await store.readErrors('notes'), isEmpty);
  });

  test('a server that crashes goes to the journal and restarts on the next '
      'request', () async {
    final app = await install();
    final lease = servers.lease(app, environment);
    await until(() => runtime.requests.isNotEmpty);
    final first = runtime.requests.single.runId;
    runtime.output(first, 'ModuleNotFoundError: flask\n');
    runtime.exit(first, 1);
    await expectLater(
      lease.fetch({'path': '/'}),
      throwsA(
        isA<MiniAppException>()
            .having((e) => e.code, 'code', 'server_exited')
            .having((e) => e.message, 'message', contains('flask')),
      ),
    );
    final errors = await store.readErrors('notes');
    expect(errors.single.message, contains('server exited with code 1'));
    expect(errors.single.message, contains('ModuleNotFoundError: flask'));

    listening = true;
    // Right after the crash a request does not start it again.
    await expectLater(
      lease.fetch({'path': '/ok'}),
      throwsA(
        isA<MiniAppException>()
            .having((e) => e.code, 'code', 'server_exited')
            .having((e) => e.message, 'message', contains('flask')),
      ),
    );
    expect(runtime.requests, hasLength(1));
    clock = clock.add(servers.restartDelay);
    final response = await lease.fetch({'path': '/ok'});
    expect(response['status'], 200);
    expect(runtime.requests, hasLength(2));
    expect(runtime.requests.last.runId, isNot(first));
    await lease.release();
  });

  test('a server that never listens is stopped and reported', () async {
    servers = MiniAppServers(
      store: store,
      freePort: () async => http.port,
      probe: (_) async => false,
      startTimeout: const Duration(milliseconds: 300),
    );
    final app = await install();
    final lease = servers.lease(app, environment);
    await expectLater(
      lease.fetch({'path': '/'}),
      throwsA(
        isA<MiniAppException>().having((e) => e.code, 'code', 'server_timeout'),
      ),
    );
    expect(runtime.cancelled, [runtime.requests.single.runId]);
    expect(
      (await store.readErrors('notes')).single.message,
      contains('did not open'),
    );
    await lease.release();
  });

  test(
    'without the Linux environment or a server the call explains why',
    () async {
      final app = await install();
      final lease = servers.lease(
        app,
        MiniAppServerEnvironment(
          runtime: () async => null,
          variables: () async => const {},
        ),
      );
      await expectLater(
        lease.fetch({'path': '/'}),
        throwsA(
          isA<MiniAppException>().having(
            (e) => e.code,
            'code',
            'linux_unavailable',
          ),
        ),
      );
      await lease.release();

      final plain = servers.lease(await install(command: null), environment);
      await expectLater(
        plain.fetch({'path': '/'}),
        throwsA(
          isA<MiniAppException>().having((e) => e.code, 'code', 'no_server'),
        ),
      );
      expect(runtime.requests, isEmpty);
    },
  );

  test('requests stay on the server', () async {
    final app = await install();
    listening = true;
    final lease = servers.lease(app, environment);
    for (final path in ['api', '//evil.com/x', 'http://example.com/', null]) {
      await expectLater(
        () async => lease.fetch({'path': path}),
        throwsA(
          isA<MiniAppException>().having((e) => e.code, 'code', 'invalid_path'),
        ),
        reason: '$path',
      );
    }
    await expectLater(
      lease.fetch({'path': '/away'}),
      throwsA(
        isA<MiniAppException>().having(
          (e) => e.code,
          'code',
          'host_not_allowed',
        ),
      ),
    );
    await lease.release();
  });

  test('the mini_apps tool shows the server state and output', () async {
    final app = await install();
    final lease = servers.lease(app, environment);
    await until(() => runtime.requests.isNotEmpty);
    runtime.output(runtime.requests.single.runId, 'started\n');
    listening = true;
    await lease.fetch({'path': '/'});
    final result = jsonDecode(
      await MiniAppDataTool(
        store: store,
        serverStatus: servers.status,
      ).execute({'action': 'server', 'app_id': 'notes'}),
    );
    expect(result, {
      'ok': true,
      'command': 'python3 server.py',
      'running': true,
      'ready': true,
      'port': http.port,
      'output': 'started\n',
    });
    await lease.release();
  });

  test('restart stops the running server and starts it again', () async {
    final app = await install();
    listening = true;
    final lease = servers.lease(app, environment);
    await lease.fetch({'path': '/'});
    final first = runtime.requests.single.runId;
    expect(servers.status('notes')['ready'], isTrue);

    await servers.restart('notes');
    expect(runtime.cancelled, [first]);
    // The new run answers requests.
    await lease.fetch({'path': '/'});
    expect(runtime.requests, hasLength(2));
    expect(servers.status('notes'), containsPair('ready', true));
    expect(servers.status('notes')['output'], contains('--- restarted ---'));
    // A deliberate restart is not a crash.
    expect(await store.readErrors('notes'), isEmpty);
    await lease.release();
    // Nothing to restart once nobody uses it.
    await servers.restart('notes');
    expect(runtime.requests, hasLength(2));
  });

  test('moru.server.fetch goes through the bridge; the publish check skips '
      'it without counting a failure', () async {
    final app = await install();
    listening = true;
    final lease = servers.lease(app, environment);
    final bridge = MiniAppBridge(
      store: store,
      appId: 'notes',
      host: MiniAppHost(server: lease.fetch),
    );
    final script = await bridge.handle(
      jsonEncode({
        'id': 1,
        'method': 'server.fetch',
        'args': {'path': '/hello'},
      }),
    );
    expect(script, startsWith('window.__moruReply(1, true, '));
    expect(script, contains(r'\"path\":\"/hello\"'));
    await lease.release();

    final sandbox = await MiniAppSandbox.create(app);
    addTearDown(sandbox.dispose);
    final checked = await sandbox.bridge.handle(
      jsonEncode({
        'id': 2,
        'method': 'server.fetch',
        'args': {'path': '/'},
      }),
    );
    expect(checked, startsWith('window.__moruReply(2, false, '));
    expect(sandbox.bridge.failedCalls, isEmpty);
  });

  test('the publish check runs a copy of the server with an empty /data and '
      'reports it', () async {
    final app = await install();
    final kept = File(p.join(app.directory, 'server-data', 'db.sqlite'));
    await kept.parent.create(recursive: true);
    await kept.writeAsString('real data');
    // The copy's server really opens its port, as the check probes it.
    final listeners = <HttpServer>[];
    addTearDown(() async {
      for (final l in listeners) {
        await l.close(force: true);
      }
    });
    final check = _ListeningRuntime(listeners);

    final sandbox = await MiniAppSandbox.create(
      app,
      serverEnvironment: MiniAppServerEnvironment(
        runtime: () async => check,
        variables: () async => {},
      ),
    );
    final copy = sandbox.app;
    expect(copy.directory, isNot(app.directory));
    final status = (await sandbox.serverStatus())!;
    expect(
      Directory(p.join(copy.directory, 'server-data')).listSync(),
      isEmpty,
    );
    expect(status['running'], isTrue);
    expect(status['ready'], isTrue);
    expect(status['output'], contains('listening'));
    expect(check.requests.single.keepStdinOpen, isTrue);

    await sandbox.dispose();
    expect(check.cancelled, [check.requests.single.runId]);
    expect(await kept.readAsString(), 'real data');
  });

  test('a check server that exits reports its code and output', () async {
    final app = await install();
    final check = _ListeningRuntime([], exitCode: 1);
    final sandbox = await MiniAppSandbox.create(
      app,
      serverEnvironment: MiniAppServerEnvironment(
        runtime: () async => check,
        variables: () async => {},
      ),
    );
    addTearDown(sandbox.dispose);
    final status = (await sandbox.serverStatus())!;
    expect(status['running'], isFalse);
    expect(status['exit_code'], 1);
    expect(status['output'], contains('ModuleNotFoundError'));
    // Without the Linux environment the check runs no server.
    final plain = await MiniAppSandbox.create(app);
    addTearDown(plain.dispose);
    expect(await plain.serverStatus(), isNull);
  });
}

/// Starts each server for real: it listens on `$PORT`, or with [exitCode]
/// prints an error and exits.
class _ListeningRuntime extends _Runtime {
  _ListeningRuntime(this.listeners, {this.exitCode});

  final List<HttpServer> listeners;
  final int? exitCode;

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    final events = super.run(request);
    final runId = request.runId;
    final code = exitCode;
    if (code != null) {
      output(runId, 'ModuleNotFoundError: flask\n');
      this.exit(runId, code);
    } else {
      unawaited(
        HttpServer.bind(
          InternetAddress.loopbackIPv4,
          int.parse(request.env['PORT']!),
        ).then((server) {
          listeners.add(server);
          server.listen((r) => r.response.close());
          output(runId, 'listening\n');
        }),
      );
    }
    return events;
  }
}
