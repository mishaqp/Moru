import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/mini_apps/mini_app_servers.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

class _Runtime extends WorkspaceRuntime {
  final requests = <CommandRequest>[];
  final events = <String, StreamController<CommandEvent>>{};
  final cancelled = <String>[];
  bool autoExit = true;
  bool failLaunch = false;

  @override
  Future<RuntimeStatus> status() async =>
      const RuntimeStatus(ready: true, engine: 'fake', sandboxed: true);

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (failLaunch) throw StateError('private server secret');
    final stream = events[request.runId] = StreamController<CommandEvent>();
    stream.add(const CommandStarted());
    return stream.stream;
  }

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    if (autoExit) exit(runId, 137);
  }

  void exit(String runId, int code) {
    final stream = events[runId]!;
    if (stream.isClosed) return;
    stream.add(
      CommandExited(
        exitCode: code,
        timedOut: false,
        cancelled: code == 137,
        interrupted: false,
        duration: Duration.zero,
      ),
    );
    unawaited(stream.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.keep_alive');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late MiniAppStore store;
  late MiniApp app;
  late MiniAppServers servers;
  late MiniAppServerEnvironment environment;
  late _Runtime runtime;
  final calls = <MethodCall>[];

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'hold' ? true : null;
    });
    temp = await Directory.systemTemp.createTemp('mini-app-server-owner-');
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'app',
        'name': 'Private app',
        'server': {'command': 'private server --secret=value'},
      }),
    );
    File(p.join(source.path, 'index.html')).writeAsStringSync('<p>');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    app = (await store.install(source)).app;
    runtime = _Runtime();
    environment = MiniAppServerEnvironment(
      runtime: () async => runtime,
      variables: () async => const {},
    );
    servers = MiniAppServers(
      store: store,
      freePort: () async => 12345,
      probe: (_) async => true,
    );
  });

  tearDown(() async {
    for (final entry in runtime.events.entries) {
      if (!entry.value.isClosed) runtime.exit(entry.key, 137);
    }
    await pumpEventQueue();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await temp.delete(recursive: true);
  });

  Future<void> until(bool Function() ready) async {
    for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue);
  }

  Future<void> nativeStop(String id) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('released', [id]),
      ),
      (_) {},
    );
  }

  test('a server waits for service promotion before launching', () async {
    final promoted = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'hold' ? promoted.future : null;
    });
    final lease = servers.lease(app, environment);
    await until(() => calls.isNotEmpty || runtime.requests.isNotEmpty);
    expect(runtime.requests, isEmpty);
    expect(calls.single.method, 'hold');
    promoted.complete(true);
    await lease.url('/');
    expect(calls.single.arguments['text'], isNot(contains('private')));
    await lease.release();
    expect(calls.last.arguments['id'], runtime.requests.single.runId);
  });

  test(
    'last client keeps ownership until the process actually exits',
    () async {
      runtime.autoExit = false;
      final page = servers.lease(app, environment);
      final job = servers.lease(app, environment);
      await page.url('/');
      final id = runtime.requests.single.runId;
      await page.release();
      expect(runtime.cancelled, isEmpty);
      var released = false;
      final stopping = job.release().then((_) => released = true);
      await until(() => runtime.cancelled.isNotEmpty);
      expect(released, isFalse);
      expect(calls.where((call) => call.method == 'release'), isEmpty);
      runtime.exit(id, 137);
      await stopping;
      expect(calls.map((call) => call.method), ['hold', 'release']);
    },
  );

  test(
    'native Stop prevents the open client from reviving the server',
    () async {
      final lease = servers.lease(app, environment);
      await lease.url('/');
      final id = runtime.requests.single.runId;
      await nativeStop(id);
      await until(() => servers.status(app.id)['running'] == false);
      expect(runtime.cancelled, [id]);
      await expectLater(lease.url('/'), throwsA(isA<MiniAppException>()));
      await servers.restart(app.id);
      expect(runtime.requests, hasLength(1));
      await lease.release();
    },
  );

  test('Stop during promotion prevents a late server launch', () async {
    final promoted = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'hold' ? promoted.future : null;
    });
    final lease = servers.lease(app, environment);
    await until(() => calls.isNotEmpty || runtime.requests.isNotEmpty);
    expect(calls, isNotEmpty);
    final id = calls.first.arguments['id'] as String;
    await nativeStop(id);
    promoted.complete(true);
    await expectLater(lease.url('/'), throwsA(isA<MiniAppException>()));
    expect(runtime.requests, isEmpty);
    expect(calls.last.method, 'release');
    await lease.release();
  });

  test(
    'a rejected hold refuses launch and reports safe failure status',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'hold' ? false : null;
      });
      final lease = servers.lease(app, environment);
      await expectLater(
        lease.url('/'),
        throwsA(
          isA<MiniAppException>().having(
            (error) => error.code,
            'code',
            'background_protection_unavailable',
          ),
        ),
      );
      expect(runtime.requests, isEmpty);
      expect(servers.status(app.id)['running'], isFalse);
      expect(
        servers.status(app.id)['error'],
        'background_protection_unavailable',
      );
      await lease.release();
    },
  );

  test('a runtime launch failure releases its foreground owner', () async {
    runtime.failLaunch = true;
    final lease = servers.lease(app, environment);
    await expectLater(lease.url('/'), throwsStateError);
    expect(servers.status(app.id)['running'], isFalse);
    expect(calls.map((call) => call.method), ['hold', 'release']);
    await lease.release();
  });

  test(
    'restart waits for the old process before acquiring the next owner',
    () async {
      runtime.autoExit = false;
      final lease = servers.lease(app, environment);
      await lease.url('/');
      final first = runtime.requests.single.runId;
      final restarting = servers.restart(app.id);
      await until(() => runtime.cancelled.isNotEmpty);
      expect(runtime.requests, hasLength(1));
      runtime.exit(first, 137);
      await restarting;
      await lease.url('/');
      expect(runtime.requests, hasLength(2));
      expect(calls.map((call) => call.method), ['hold', 'release', 'hold']);
      expect(servers.status(app.id)['running'], isTrue);
      runtime.autoExit = true;
      await lease.release();
      expect(calls.last.arguments['id'], runtime.requests.last.runId);
    },
  );

  test(
    'last client leaving during restart prevents the replacement launch',
    () async {
      runtime.autoExit = false;
      final lease = servers.lease(app, environment);
      await lease.url('/');
      final first = runtime.requests.single.runId;
      final restarting = servers.restart(app.id);
      await until(() => runtime.cancelled.isNotEmpty);
      final leaving = lease.release();
      runtime.exit(first, 137);
      await Future.wait([restarting, leaving]);
      expect(runtime.requests, hasLength(1));
      expect(servers.status(app.id)['running'], isFalse);
      expect(calls.map((call) => call.method), ['hold', 'release']);
    },
  );
}
