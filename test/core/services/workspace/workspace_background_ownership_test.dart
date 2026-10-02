import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_tools_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

class _Runtime extends WorkspaceRuntime {
  final requests = <CommandRequest>[];
  final cancelled = <String>[];
  final streams = <String, StreamController<CommandEvent>>{};
  StreamController<CommandEvent> get events => streams.values.last;
  bool failLaunch = false;
  Completer<void>? cancelAcknowledgement;

  @override
  Future<RuntimeStatus> status() async =>
      const RuntimeStatus(ready: true, engine: 'fake', sandboxed: true);

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (failLaunch) throw StateError('private launch command');
    return (streams[request.runId] = StreamController<CommandEvent>()).stream;
  }

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    await cancelAcknowledgement?.future;
    if (streams[runId]?.isClosed == false) {
      await finish(cancelled: true, runId: runId);
    }
  }

  Future<void> finish({
    bool cancelled = false,
    int code = 0,
    String? runId,
  }) async {
    final stream = runId == null ? events : streams[runId]!;
    stream.add(
      CommandExited(
        exitCode: code,
        timedOut: false,
        cancelled: cancelled,
        interrupted: false,
        duration: Duration.zero,
      ),
    );
    await stream.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.keep_alive');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late _Runtime runtime;
  late ToolRunRegistry registry;
  late WorkspaceToolsService tools;
  late WorkspaceRuntimeProvider provider;
  late WorkspaceToolContext context;
  final calls = <MethodCall>[];
  final results = <Map<String, Object>>[];
  Completer<void>? resultGate;

  Future<void> until(bool Function() ready) async {
    for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue);
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    results.clear();
    resultGate = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'hold' ? true : null;
    });
    temp = await Directory.systemTemp.createTemp('background-shell-owner-');
    final workspace = Directory(p.join(temp.path, 'workspace'))..createSync();
    final session = Directory(p.join(temp.path, 'session'))..createSync();
    final skills = Directory(p.join(temp.path, 'skills'))..createSync();
    runtime = _Runtime();
    registry = ToolRunRegistry();
    provider = WorkspaceRuntimeProvider()..register(runtime);
    tools = WorkspaceToolsService(
      registry: registry,
      runtimeProvider: provider,
      reportBackgroundShellResult:
          ({required id, required conversationId, required succeeded}) async {
            results.add({
              'id': id,
              'conversationId': conversationId,
              'succeeded': succeeded,
            });
            await resultGate?.future;
          },
    );
    context = WorkspaceToolContext(
      workspace: Workspace(
        id: 'workspace',
        name: 'Private workspace',
        kind: WorkspaceKind.managed,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      binding: const WorkspaceBinding(workspaceId: 'workspace', allowAll: true),
      paths: WorkspacePaths.native(
        workspaceHostRoot: workspace.path,
        sessionHostDir: session.path,
        skillsHostDir: skills.path,
      ),
      sessionDir: session,
      outputsDir: Directory(p.join(session.path, 'outputs')),
      conversationId: 'chat',
      runtimeStatus: await runtime.status(),
      runtimeRegistered: true,
    );
  });

  tearDown(() async {
    if (resultGate != null && !resultGate!.isCompleted) resultGate!.complete();
    for (final stream in runtime.streams.entries) {
      if (!stream.value.isClosed) {
        await runtime.finish(cancelled: true, runId: stream.key);
      }
    }
    await until(
      () =>
          calls.where((call) => call.method == 'release').length ==
          calls.where((call) => call.method == 'hold').length,
    );
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await temp.delete(recursive: true);
  });

  Future<ClientToolResult> start() async => ClientToolResult.fromHandler(
    await tools.handle(context, 'shell', {
      'command': 'private command --token=secret',
      'background': true,
    }, toolCallId: 'shell'),
  );

  Future<void> nativeStop(String id) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('released', [id]),
      ),
      (_) {},
    );
  }

  test('a background command waits for foreground service promotion', () async {
    final promoted = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'hold' ? promoted.future : null;
    });
    final starting = start();
    await until(() => calls.isNotEmpty || runtime.requests.isNotEmpty);
    expect(runtime.requests, isEmpty);
    expect(calls.single.method, 'hold');
    promoted.complete(true);
    await starting;
    expect(runtime.requests, hasLength(1));
    expect(calls.single.arguments['text'], isNot(contains('private')));
    await runtime.finish();
    await until(() => calls.any((call) => call.method == 'release'));
    expect(calls.last.arguments['id'], runtime.requests.single.runId);
  });

  test(
    'a rejected hold refuses the background launch with a safe error',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'hold' ? false : null;
      });
      final result = await start();
      expect(result.content, contains('background_protection_unavailable'));
      expect(runtime.requests, isEmpty);
      expect(registry.running, isEmpty);
    },
  );

  test('native Stop cancels the actual background runtime run', () async {
    await start();
    final id = runtime.requests.single.runId;
    await nativeStop(id);
    await until(() => registry.running.isEmpty);
    expect(runtime.cancelled, [id]);
    expect(
      registry.byRuntimeRunId(id, conversationId: 'chat')!.status,
      ToolRunStatus.cancelled,
    );
    expect(calls.last.method, 'release');
    expect(results, isEmpty);
  });

  test('Stop during promotion prevents a late background launch', () async {
    final promoted = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'hold' ? promoted.future : null;
    });
    final starting = start();
    await until(() => calls.isNotEmpty || runtime.requests.isNotEmpty);
    expect(calls, isNotEmpty);
    final id = calls.first.arguments['id'] as String;
    await nativeStop(id);
    promoted.complete(true);
    final result = await starting;
    expect(runtime.requests, isEmpty);
    expect(result.content, contains('cancelled'));
    expect(registry.running, isEmpty);
    expect(calls.last.method, 'release');
  });

  test('a synchronous runtime launch failure releases its owner', () async {
    runtime.failLaunch = true;
    await start();
    await until(() => registry.running.isEmpty);
    expect(registry.all.single.status, ToolRunStatus.failed);
    expect(calls.map((call) => call.method), ['hold', 'release']);
  });

  test(
    'completion reports only its captured identity before releasing ownership',
    () async {
      resultGate = Completer<void>();
      await start();
      final id = runtime.requests.single.runId;
      runtime.events.add(
        CommandOutput(
          OutputStreamKind.stderr,
          utf8.encode('private stderr secret'),
        ),
      );
      await runtime.finish();
      await until(() => results.isNotEmpty);
      expect(registry.all.single.status, ToolRunStatus.succeeded);
      expect(results, [
        {'id': id, 'conversationId': 'chat', 'succeeded': true},
      ]);
      expect(calls.where((call) => call.method == 'release'), isEmpty);
      resultGate!.complete();
      await until(() => calls.any((call) => call.method == 'release'));
    },
  );

  test('a failed job reports a generic failure without runtime text', () async {
    await start();
    runtime.events.addError(StateError('private command and token'));
    await runtime.events.close();
    await until(() => calls.any((call) => call.method == 'release'));
    expect(results.single['succeeded'], isFalse);
    expect(jsonEncode(results), isNot(contains('private')));
  });

  test(
    'shell_output cancels the captured runtime after the provider changes',
    () async {
      await start();
      final id = runtime.requests.single.runId;
      final replacement = _Runtime();
      provider.register(replacement);
      await tools.handle(context, 'shell_output', {
        'job_id': id,
        'stop': true,
      }, toolCallId: 'stop');
      expect(runtime.cancelled, [id]);
      expect(replacement.cancelled, isEmpty);
      expect(results, isEmpty);
    },
  );

  test(
    'ending the originating reply leaves its background command running',
    () async {
      var cancelled = false;
      final ended = Completer<void>();
      await ToolCallCancellation(
        isCancelled: () => cancelled,
        cancelled: ended.future,
      ).run(start);
      cancelled = true;
      ended.complete();
      await pumpEventQueue();
      expect(runtime.cancelled, isEmpty);
      expect(runtime.requests.single.isCancelled?.call(), isFalse);
      expect(registry.all.single.status, ToolRunStatus.running);
      final id = runtime.requests.single.runId;
      final output = ClientToolResult.fromHandler(
        await tools.handle(context, 'shell_output', {
          'job_id': id,
        }, toolCallId: 'after-generation-stop'),
      );
      expect(jsonDecode(output.content)['job_id'], id);
      await tools.handle(context, 'shell_output', {
        'job_id': id,
        'stop': true,
      }, toolCallId: 'stop-preserved-job');
      expect(runtime.cancelled, [id]);
      expect(
        registry.byRuntimeRunId(id, conversationId: 'chat')!.status,
        ToolRunStatus.cancelled,
      );
    },
  );

  test(
    'queued foreground output while Stop awaits native ack stays cancelled',
    () async {
      var stopped = false;
      final ended = Completer<void>();
      runtime.cancelAcknowledgement = Completer<void>();
      final execution =
          ToolCallCancellation(
            isCancelled: () => stopped,
            cancelled: ended.future,
          ).run(
            () => tools.handle(context, 'shell', {
              'command': 'printf progress',
            }, toolCallId: 'foreground'),
          );
      await until(() => runtime.requests.isNotEmpty);
      final run = registry.all.single;
      run.complete(status: ToolRunStatus.cancelled);
      stopped = true;
      ended.complete();
      await until(() => runtime.cancelled.isNotEmpty);
      runtime.events.add(
        CommandOutput(
          OutputStreamKind.stdout,
          utf8.encode('queued after stop\n'),
        ),
      );
      runtime.events.add(
        CommandOutput(OutputStreamKind.stderr, utf8.encode('queued error\n')),
      );
      await pumpEventQueue();
      expect(run.status, ToolRunStatus.cancelled);
      runtime.cancelAcknowledgement!.complete();
      final result = ClientToolResult.fromHandler(await execution);
      expect(result.content, isNot(contains('shell_failed')));
      expect(run.status, ToolRunStatus.cancelled);
    },
  );

  test(
    'reusing a tool ID leaves both jobs stoppable and releases both owners',
    () async {
      await start();
      final first = runtime.requests.single.runId;
      await start();
      final second = runtime.requests.last.runId;
      expect(registry.byRuntimeRunId(first, conversationId: 'chat'), isNotNull);
      await tools.handle(context, 'shell_output', {
        'job_id': first,
        'stop': true,
      }, toolCallId: 'stop-old');
      expect(runtime.cancelled, [first]);
      expect(
        registry.byRuntimeRunId(second, conversationId: 'chat')!.status,
        ToolRunStatus.running,
      );
      await runtime.finish(runId: second);
      await until(
        () => calls.where((call) => call.method == 'release').length == 2,
      );
      expect(
        calls
            .where((call) => call.method == 'release')
            .map((call) => call.arguments['id']),
        unorderedEquals([first, second]),
      );
    },
  );

  test(
    'failure publishing run completion still releases the native owner',
    () async {
      final finished = Completer<void>();
      final failures = <Object>[];
      runZonedGuarded<void>(() {
        unawaited(() async {
          await start();
          // Simulate an observer's owner being disposed while its process is
          // finishing. Cleanup must run even when notification of state fails.
          registry.all.single.dispose();
          await runtime.finish();
          finished.complete();
        }());
      }, (error, _) => failures.add(error));
      await finished.future;
      await until(
        () =>
            failures.isNotEmpty &&
            calls.any((call) => call.method == 'release'),
      );
      expect(failures.single, isA<FlutterError>());
    },
  );

  test(
    'pre-launch Stop releases a late hold even if run publication fails',
    () async {
      final promoted = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'hold' ? promoted.future : null;
      });
      final starting = start();
      await until(() => calls.isNotEmpty);
      final id = calls.single.arguments['id'] as String;
      registry.all.single.dispose();
      await nativeStop(id);
      promoted.complete(true);
      await starting;
      expect(runtime.requests, isEmpty);
      await until(() => calls.any((call) => call.method == 'release'));
      expect(calls.last.arguments['id'], id);
    },
  );
}
