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
    servers = MiniAppServers(
      store: store,
      freePort: () async => http.port,
      probe: (_) async => listening,
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
      'port': http.port,
      'output': 'started\n',
    });
    await lease.release();
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
}
