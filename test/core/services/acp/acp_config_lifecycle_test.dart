import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_config_leases.dart';
import 'package:Kelivo/core/services/acp/acp_error_messages.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

import '../../../support/acp_test_process_table.dart';
import '../../../support/business_test_harness.dart';
import '../../../support/fake_workspace_runtime.dart';

const _secret = 'lifecycle-user-agent-secret';
const _provider = AcpProviderInput(
  baseUrl: 'https://provider.test/v1',
  apiKey: 'lifecycle-api-key',
  model: 'model',
  headers: {'User-Agent': _secret, 'X-Private': 'environment-header-secret'},
);

CommandExited _exit(int code) => CommandExited(
  exitCode: code,
  timedOut: false,
  cancelled: false,
  interrupted: false,
  duration: Duration.zero,
);

class _LifecycleRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  _LifecycleRuntime(this.directory) {
    processTable = File('${directory.path}/process-table.cjs')
      ..writeAsStringSync(acpTestProcessTableScript);
  }
  final Directory directory;
  late final File processTable;
  final processes = <String, StreamController<CommandEvent>>{};
  bool failWrite = false;
  bool failStart = false;
  bool failUninstall = false;
  bool rootChroot = false;
  Completer<void>? written;
  Completer<void>? releaseWrite;
  Completer<void>? cancelling;
  Completer<void>? releaseCancel;
  String get configRoot => '${directory.path}/configs';
  String local(String path) => path
      .replaceAll(acpConfigDir, configRoot)
      .replaceAll(acpNpmPrefix, '${directory.path}/npm')
      .replaceAll(acpClaudeTemporaryRoot, '${directory.path}/scratch-claude')
      .replaceAll(acpCodexTemporaryRoot, '${directory.path}/scratch-codex');

  @override
  Future<RuntimeStatus> status() async => RuntimeStatus(
    ready: true,
    engine: 'fake',
    sandboxed: true,
    rootChroot: rootChroot,
  );

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (request.keepStdinOpen) {
      if (failStart) return Stream.error(StateError('start $_secret'));
      final events = StreamController<CommandEvent>();
      processes[request.runId] = events;
      events.add(const CommandStarted());
      if (request.command.contains("'web'")) {
        final port = RegExp(
          r"'--port' '(\d+)'",
        ).firstMatch(request.command)!.group(1);
        events.add(
          CommandOutput(
            OutputStreamKind.stdout,
            Uint8List.fromList(
              utf8.encode('http://127.0.0.1:$port/#token=fake\n'),
            ),
          ),
        );
      }
      return events.stream;
    }
    return _script(request);
  }

  Stream<CommandEvent> _script(CommandRequest request) async* {
    yield const CommandStarted();
    if (request.command.contains('__moru_node=')) {
      yield CommandOutput(
        OutputStreamKind.stdout,
        Uint8List.fromList(utf8.encode('__moru_node=v24.0.0\n')),
      );
      yield _exit(0);
      return;
    }
    if (request.command.contains('npm uninstall') && failUninstall) {
      yield _exit(1);
      return;
    }
    final script = local(
      request.command,
    ).replaceAll(RegExp(r'npm uninstall[^\n]*\n'), 'true\n');
    final environment = {
      ...Platform.environment,
      ...request.env.map((key, value) => MapEntry(key, local(value))),
      // Guest paths are fixtures here; use the host's installed Node.
      'PATH': Platform.environment['PATH']!,
      'MORU_TEST_PROCESS_IDS': '[]',
      'MORU_TEST_PID_FILES': '[]',
    };
    environment['NODE_OPTIONS'] =
        '--require=${jsonEncode(processTable.path)} '
        '${environment['NODE_OPTIONS'] ?? ''}';
    final result = await Process.run('/bin/sh', [
      '-c',
      script,
    ], environment: environment);
    if ((result.stderr as String).isNotEmpty) {
      yield CommandOutput(
        OutputStreamKind.stderr,
        Uint8List.fromList(utf8.encode(result.stderr as String)),
      );
    }
    if (request.command.contains('base64 -d')) {
      if (written?.isCompleted == false) written!.complete();
      await releaseWrite?.future;
    }
    yield _exit(
      failWrite && request.command.contains('base64 -d') ? 1 : result.exitCode,
    );
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    for (final line in const LineSplitter().convert(utf8.decode(data))) {
      final message = jsonDecode(line) as Map;
      if (message['method'] != 'initialize') continue;
      processes[runId]!.add(
        CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(
            utf8.encode(
              '${jsonEncode({
                'jsonrpc': '2.0',
                'id': message['id'],
                'result': {
                  'protocolVersion': 1,
                  'agentInfo': {'name': 'fake'},
                },
              })}\n',
            ),
          ),
        ),
      );
    }
  }

  void exit(String id) {
    final process = processes.remove(id)!;
    process.add(_exit(0));
    unawaited(process.close());
  }

  @override
  Future<void> cancel(String runId) async {
    if (cancelling?.isCompleted == false) cancelling!.complete();
    await releaseCancel?.future;
    final process = processes.remove(runId);
    if (process != null) {
      process.add(_exit(143));
      unawaited(process.close());
    }
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 2000 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'bounded IO condition was not reached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _LifecycleRuntime runtime;
  late AcpAgentManager manager;
  final spec = AcpAgentSpec.byId(AcpAgentSpec.kimiCodeId)!;
  File config() => File('${runtime.configRoot}/kimi-code/config.toml');
  File session() => File('${runtime.configRoot}/kimi-code/sessions/saved.json');
  File webSession() =>
      File('${runtime.configRoot}/web-kimi-code/kimi-code/sessions/saved.json');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('acp_config_lifecycle_');
    runtime = _LifecycleRuntime(directory);
    manager = AcpAgentManager(
      preferences: createBusinessTestPreferences(),
      runtimeProvider: WorkspaceRuntimeProvider()..register(runtime),
      environment: EnvironmentProvider(
        preferences: createBusinessTestPreferences(),
      ),
    );
    session().parent.createSync(recursive: true);
    session().writeAsStringSync('saved session');
    webSession().parent.createSync(recursive: true);
    webSession().writeAsStringSync('saved web session');
  });
  tearDown(() async {
    manager.dispose();
    await _until(() => runtime.processes.isEmpty);
    directory.deleteSync(recursive: true);
  });

  test(
    'concurrent chat leases remove literal headers only after last close',
    () async {
      final first = await manager.start(spec, _provider);
      final second = await manager.start(spec, _provider);
      expect(config().readAsStringSync(), contains(_secret));
      first.close();
      await _until(() => runtime.processes.length == 1);
      expect(config().existsSync(), isTrue);
      second.close();
      await _until(() => !config().existsSync());
      expect(session().readAsStringSync(), 'saved session');
      for (final file
          in directory.listSync(recursive: true).whereType<File>()) {
        expect(file.readAsStringSync(), isNot(contains(_secret)));
        expect(
          file.readAsStringSync(),
          isNot(contains('environment-header-secret')),
        );
        expect(file.readAsStringSync(), isNot(contains('lifecycle-api-key')));
      }
    },
  );

  test('natural ACP exit cleans config and retains sessions', () async {
    final agent = await manager.start(spec, _provider);
    runtime.exit(runtime.processes.keys.single);
    await _until(() => !config().existsSync());
    expect(session().existsSync(), isTrue);
    agent.close();
  });

  test('Claude launches own separate private temporary directories', () async {
    final claude = AcpAgentSpec.byId(AcpAgentSpec.claudeCodeId)!;
    final first = await manager.start(claude, _provider);
    final firstRequest = runtime.requests.lastWhere((r) => r.keepStdinOpen);
    final firstPath = firstRequest.env['CLAUDE_CODE_TMPDIR'];
    expect(firstPath, isNotNull);
    final firstDirectory = Directory(runtime.local(firstPath!));
    expect(firstDirectory.existsSync(), isTrue);
    expect(firstDirectory.statSync().mode & 0x1ff, 0x1c0);
    final second = await manager.start(claude, _provider);
    final secondRequest = runtime.requests.lastWhere((r) => r.keepStdinOpen);
    final secondPath = secondRequest.env['CLAUDE_CODE_TMPDIR']!;
    expect(secondPath, isNot(firstPath));
    expect(secondRequest.env['CLAUDE_CODE_CONTAINER_ID'], isNotEmpty);
    final secondDirectory = Directory(runtime.local(secondPath));
    expect(secondDirectory.existsSync(), isTrue);
    first.close();
    await _until(() => !firstDirectory.existsSync());
    expect(secondDirectory.existsSync(), isTrue);
    second.close();
    await _until(() => !secondDirectory.existsSync());
  });

  for (final phase in ['write', 'start']) {
    test(
      'failed Claude $phase removes its fresh temporary directory',
      () async {
        runtime.failWrite = phase == 'write';
        runtime.failStart = phase == 'start';
        await expectLater(
          manager.start(
            AcpAgentSpec.byId(AcpAgentSpec.claudeCodeId)!,
            _provider,
          ),
          throwsA(anything),
        );
        final prepared = runtime.requests.firstWhere(
          (r) => r.command.contains('base64 -d'),
        );
        final path = prepared.env['CLAUDE_CODE_TMPDIR'];
        expect(path, isNotNull);
        expect(Directory(runtime.local(path!)).existsSync(), isFalse);
      },
    );
  }

  test(
    'Claude reports an inaccessible scratch namespace without changing it',
    () async {
      final root = Directory(runtime.local(acpClaudeTemporaryRoot))
        ..createSync();
      // Reach the missing-marker check regardless of the host's umask.
      final mode = await Process.run('/bin/chmod', ['700', root.path]);
      expect(mode.exitCode, 0);
      final saved = File('${root.path}/user-file')..writeAsStringSync('keep');
      await expectLater(
        manager.start(AcpAgentSpec.byId(AcpAgentSpec.claudeCodeId)!, _provider),
        throwsA(
          predicate<Object>(
            (error) =>
                classifyAcpFailure(error) ==
                    AcpFailureKind.temporaryDirectory &&
                acpErrorDetails(error)!.contains('ENOENT') &&
                !acpErrorDetails(error)!.contains(_secret),
          ),
        ),
      );
      expect(saved.readAsStringSync(), 'keep');
      expect(root.listSync(), hasLength(1));
    },
  );

  test('Codex root launch privately binds its own daemon directory', () async {
    runtime.rootChroot = true;
    final agent = await manager.start(
      AcpAgentSpec.byId(AcpAgentSpec.codexId)!,
      _provider,
    );
    final request = runtime.requests.lastWhere((r) => r.keepStdinOpen);
    final path = request.env['MORU_ACP_TEMP_DIR'];
    expect(path, isNotNull);
    expect(request.expectedRootChroot, isTrue);
    expect(request.command, contains('mount --bind'));
    expect(request.command, contains('/tmp/codex-daemon-0'));
    final scratch = Directory(runtime.local(path!));
    expect(scratch.existsSync(), isTrue);
    expect(scratch.statSync().mode & 0x1ff, 0x1c0);
    agent.close();
    await _until(() => !scratch.existsSync());
  });

  test(
    'Codex PRoot launch retains its existing command without a mount',
    () async {
      final agent = await manager.start(
        AcpAgentSpec.byId(AcpAgentSpec.codexId)!,
        _provider,
      );
      final request = runtime.requests.lastWhere((r) => r.keepStdinOpen);
      expect(request.env['MORU_ACP_TEMP_DIR'], isNull);
      expect(request.expectedRootChroot, isFalse);
      expect(request.command, isNot(contains('mount --bind')));
      agent.close();
    },
  );

  test(
    'existing temporary files become mode 0600 before secret writes',
    () async {
      config().writeAsStringSync('old settings');
      final mode = await Process.run('/bin/chmod', ['644', config().path]);
      expect(mode.exitCode, 0);
      final agent = await manager.start(spec, _provider);
      expect(config().statSync().mode & 0x1ff, 0x180);
      agent.close();
      await _until(() => !config().existsSync());
    },
  );

  test(
    'Kimi without literal headers still owns a temporary config lease',
    () async {
      final agent = await manager.start(
        spec,
        const AcpProviderInput(
          baseUrl: 'https://provider.test/v1',
          apiKey: 'key',
          model: 'model',
          headers: {'X-Private': 'environment-header-secret'},
        ),
      );
      expect(config().existsSync(), isTrue);
      expect(
        config().readAsStringSync(),
        isNot(contains('environment-header-secret')),
      );
      agent.close();
      await _until(() => !config().existsSync());
      expect(session().existsSync(), isTrue);
    },
  );

  test('a new lease waits for the previous last-owner deletion', () async {
    final leases = AcpConfigLeases();
    final deleting = Completer<void>();
    final releaseDeletion = Completer<void>();
    config().writeAsStringSync('first');
    final files = [AcpConfigFile(config().path, 'settings', temporary: true)];
    final first = await leases.acquire(runtime, files, (paths) async {
      deleting.complete();
      await releaseDeletion.future;
      await File(paths.single).delete();
    });
    final closing = first();
    await deleting.future;
    var acquired = false;
    final acquiring = leases
        .acquire(runtime, files, (paths) async {
          await File(paths.single).delete();
        })
        .then((release) {
          acquired = true;
          return release;
        });
    await Future<void>.value();
    expect(acquired, isFalse);
    releaseDeletion.complete();
    await closing;
    final second = await acquiring;
    config().writeAsStringSync('second');
    await first();
    expect(config().readAsStringSync(), 'second');
    await second();
    expect(config().existsSync(), isFalse);
  });

  test(
    'manager disposal closes every chat before cleaning their configs',
    () async {
      await manager.start(spec, _provider);
      await manager.start(spec, _provider);
      manager.dispose();
      await _until(() => !config().existsSync() && runtime.processes.isEmpty);
      expect(session().readAsStringSync(), 'saved session');
    },
  );

  for (final phase in ['write', 'start']) {
    test(
      'failed $phase cleans partially prepared config without secret diagnostics',
      () async {
        runtime.failWrite = phase == 'write';
        runtime.failStart = phase == 'start';
        await expectLater(
          manager.start(spec, _provider),
          throwsA(
            predicate<Object>((error) => !error.toString().contains(_secret)),
          ),
        );
        await _until(() => !config().existsSync());
        expect(session().existsSync(), isTrue);
      },
    );
  }

  test(
    'failed startup retains config until native cancellation finishes',
    () async {
      runtime.failStart = true;
      runtime.cancelling = Completer<void>();
      runtime.releaseCancel = Completer<void>();
      addTearDown(() {
        if (!runtime.releaseCancel!.isCompleted) {
          runtime.releaseCancel!.complete();
        }
      });
      var completed = false;
      final starting = manager.start(spec, _provider).whenComplete(() {
        completed = true;
      });
      final assertion = expectLater(starting, throwsA(anything));
      await runtime.cancelling!.future;
      // A healthy startup supplies independent progress while native stop is
      // held, so this checks ordering without an arbitrary delay.
      runtime.failStart = false;
      final second = await manager.start(spec, _provider);
      expect(completed, isFalse);
      expect(config().readAsStringSync(), contains(_secret));
      runtime.releaseCancel!.complete();
      await assertion;
      expect(config().existsSync(), isTrue);
      second.close();
      await _until(() => !config().existsSync());
      expect(session().existsSync(), isTrue);
    },
  );

  test(
    'cancelled preparation removes written config without starting',
    () async {
      runtime.written = Completer<void>();
      runtime.releaseWrite = Completer<void>();
      var cancelled = false;
      final starting = manager.start(
        spec,
        _provider,
        isCancelled: () => cancelled,
      );
      final assertion = expectLater(starting, throwsA(anything));
      await runtime.written!.future;
      cancelled = true;
      runtime.releaseWrite!.complete();
      await assertion;
      await _until(() => !config().existsSync());
      expect(runtime.requests.where((r) => r.keepStdinOpen), isEmpty);
      expect(session().existsSync(), isTrue);
    },
  );

  test(
    'uninstall stops chats and removes owned ACP/Web legacy files only',
    () async {
      final first = await manager.start(spec, _provider);
      final second = await manager.start(spec, _provider);
      final legacy = File(
        '${runtime.configRoot}/web-kimi-code/kimi-code/config.toml',
      );
      legacy.parent.createSync(recursive: true);
      legacy.writeAsStringSync(_secret);
      await manager.uninstall(spec);
      expect(runtime.processes, isEmpty);
      expect(config().existsSync(), isFalse);
      expect(legacy.existsSync(), isFalse);
      expect(session().readAsStringSync(), 'saved session');
      expect(manager.state(spec.id), AcpInstallState.missing);
      first.close();
      second.close();
    },
  );

  test(
    'uninstall cancels a pending preparation and awaits its cleanup',
    () async {
      runtime.written = Completer<void>();
      runtime.releaseWrite = Completer<void>();
      final starting = manager.start(spec, _provider);
      final assertion = expectLater(starting, throwsA(anything));
      await runtime.written!.future;
      final removing = manager.uninstall(spec);
      runtime.releaseWrite!.complete();
      await assertion;
      await removing;
      expect(config().existsSync(), isFalse);
      expect(runtime.requests.where((r) => r.keepStdinOpen), isEmpty);
      expect(session().existsSync(), isTrue);
    },
  );

  test('failed npm removal keeps installed state and legacy files', () async {
    await manager.start(spec, _provider);
    runtime.failUninstall = true;
    final legacy = File(
      '${runtime.configRoot}/web-kimi-code/kimi-code/config.toml',
    );
    legacy.parent.createSync(recursive: true);
    legacy.writeAsStringSync('legacy');
    await manager.uninstall(spec);
    expect(manager.failure, AcpAgentFailure.remove);
    expect(manager.state(spec.id), isNot(AcpInstallState.missing));
    expect(legacy.existsSync(), isTrue);
    expect(config().existsSync(), isFalse);
    expect(session().existsSync(), isTrue);
  });

  for (final end in ['stop', 'exit', 'detach', 'dispose']) {
    test('Web $end removes temporary config and retains state', () async {
      final servers = manager.webServers;
      await servers.open(
        spec,
        _provider,
        cwd: '/workspace',
        openBrowser: (_) async {},
      );
      final webConfig = File(
        '${runtime.configRoot}/web-kimi-code/kimi-code/config.toml',
      );
      expect(webConfig.readAsStringSync(), contains(_secret));
      if (end == 'stop') await servers.stop(spec.id);
      if (end == 'exit') runtime.exit(runtime.processes.keys.single);
      if (end == 'detach') {
        servers.didChangeAppLifecycleState(AppLifecycleState.detached);
      }
      if (end == 'dispose') manager.dispose();
      await _until(() => !webConfig.existsSync());
      await servers.stop(spec.id);
      expect(
        runtime.requests.where(
          (request) =>
              request.command.startsWith('rm -f --') &&
              request.command.contains('web-kimi-code'),
        ),
        hasLength(1),
      );
      expect(session().existsSync(), isTrue);
      expect(webSession().readAsStringSync(), 'saved web session');
    });
  }

  for (final phase in ['write', 'start']) {
    test('failed Web $phase cleans config and preserves sessions', () async {
      runtime.failWrite = phase == 'write';
      runtime.failStart = phase == 'start';
      await expectLater(
        manager.webServers.open(
          spec,
          _provider,
          cwd: '/workspace',
          openBrowser: (_) async => fail('failed process must not open'),
        ),
        throwsA(
          predicate<Object>((error) => !error.toString().contains(_secret)),
        ),
      );
      final webConfig = File(
        '${runtime.configRoot}/web-kimi-code/kimi-code/config.toml',
      );
      await _until(() => !webConfig.existsSync());
      expect(webSession().readAsStringSync(), 'saved web session');
    });
  }

  test(
    'Web stopped during preparation cleans the late config without launching',
    () async {
      runtime.written = Completer<void>();
      runtime.releaseWrite = Completer<void>();
      final opening = manager.webServers.open(
        spec,
        _provider,
        cwd: '/workspace',
        openBrowser: (_) async => fail('cancelled web must not open'),
      );
      final assertion = expectLater(opening, throwsA(anything));
      await runtime.written!.future;
      await manager.webServers.stop(spec.id);
      runtime.releaseWrite!.complete();
      await assertion;
      final webConfig = File(
        '${runtime.configRoot}/web-kimi-code/kimi-code/config.toml',
      );
      await _until(() => !webConfig.existsSync());
      expect(runtime.requests.where((r) => r.keepStdinOpen), isEmpty);
      expect(session().existsSync(), isTrue);
    },
  );
}
