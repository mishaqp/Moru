import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_web_servers.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

import '../../../support/fake_workspace_runtime.dart';

class _WebRuntime extends FakeWorkspaceRuntime {
  final events = StreamController<CommandEvent>.broadcast();
  final cancelled = <String>[];
  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    return events.stream;
  }

  void output(String text) => events.add(
    CommandOutput(
      OutputStreamKind.stdout,
      Uint8List.fromList(utf8.encode(text)),
    ),
  );
  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = AcpProviderInput(
    baseUrl: 'https://provider.test/v1',
    apiKey: 'secret',
    model: 'model',
  );
  final spec = AcpAgentSpec.byId('opencode')!;

  test(
    'opens only the complete printed loopback address and stops the process',
    () async {
      final runtime = _WebRuntime();
      final launched = Completer<void>();
      final opened = <String>[];
      final servers = AcpAgentWebServers(
        freePort: () async => 4321,
        prepare: (spec, input, port, directory) async {
          expect(input, same(provider));
          expect(port, 4321);
          expect(directory, startsWith('/root/.config/moru-agents/web-'));
          launched.complete();
          return (
            runtime,
            AcpLaunch(
              command: 'opencode',
              arguments: ['web', '--hostname', '127.0.0.1', '--port', '$port'],
              environment: {'KEY': input.apiKey},
              files: const [],
            ),
          );
        },
      );
      final opening = servers.open(
        spec,
        provider,
        cwd: '/workspace',
        mounts: const [Mount(host: '/tmp/example', guest: '/workspace')],
        openBrowser: (url) async => opened.add(url),
      );
      await launched.future;
      // Wait for the condition that the persistent process has been subscribed.
      await Future.doWhile(() async {
        await Future<void>.value();
        return runtime.requests.isEmpty;
      });
      runtime.output('http://0.0.0.0:4321/#token=bad\n');
      runtime.output('Local: http://127.0.0.1:4322/#token=se');
      expect(opened, isEmpty);
      runtime.output('cret\n');
      await opening;
      expect(opened, ['http://127.0.0.1:4322/#token=secret']);
      expect(servers.running(spec.id), isTrue);
      expect(runtime.requests.single.cwd, '/workspace');
      expect(runtime.requests.single.mounts.single.guest, '/workspace');
      expect(runtime.requests.single.timeout, Duration.zero);
      expect(runtime.requests.single.keepStdinOpen, isTrue);
      await servers.open(
        spec,
        provider,
        cwd: '/workspace',
        mounts: const [Mount(host: '/tmp/example', guest: '/workspace')],
        openBrowser: (url) async => opened.add(url),
      );
      expect(runtime.requests, hasLength(1));
      await servers.stop(spec.id);
      expect(runtime.cancelled, [runtime.requests.single.runId]);
      expect(servers.running(spec.id), isFalse);
      servers.dispose();
      await runtime.events.close();
    },
  );

  test(
    'timeout cancels server and exposes a typed error without its output',
    () async {
      final runtime = _WebRuntime();
      final servers = AcpAgentWebServers(
        freePort: () async => 4321,
        startTimeout: Duration.zero,
        prepare: (_, input, port, directory) async => (
          runtime,
          AcpLaunch(
            command: 'dsh',
            arguments: const ['web'],
            environment: const {},
            files: const [],
          ),
        ),
      );
      await expectLater(
        servers.open(
          spec,
          provider,
          cwd: '/workspace',
          openBrowser: (_) async => fail('not ready'),
        ),
        throwsA(
          isA<AcpWebException>().having(
            (e) => e.failure,
            'failure',
            AcpWebFailure.timeout,
          ),
        ),
      );
      expect(runtime.cancelled, hasLength(1));
      expect(servers.failure(spec.id), AcpWebFailure.timeout);
      servers.dispose();
      await runtime.events.close();
    },
  );

  test('stop during preparation prevents launching and opening', () async {
    final runtime = _WebRuntime();
    final preparation = Completer<(WorkspaceRuntime, AcpLaunch)>();
    final preparing = Completer<void>();
    final servers = AcpAgentWebServers(
      freePort: () async => 4321,
      prepare: (_, input, port, directory) {
        preparing.complete();
        return preparation.future;
      },
    );
    final opening = servers.open(
      spec,
      provider,
      cwd: '/workspace',
      openBrowser: (_) async => fail('stopped'),
    );
    final rejected = expectLater(opening, throwsA(isA<AcpWebException>()));
    await preparing.future;
    await servers.stop(spec.id);
    preparation.complete((
      runtime,
      AcpLaunch(
        command: 'opencode',
        arguments: const ['web'],
        environment: const {},
        files: const [],
      ),
    ));
    await rejected;
    expect(runtime.requests, isEmpty);
    servers.dispose();
    await runtime.events.close();
  });

  test('application detach stops all servers', () async {
    final runtime = _WebRuntime();
    final servers = AcpAgentWebServers(
      freePort: () async => 4321,
      prepare: (_, input, port, directory) async => (
        runtime,
        AcpLaunch(
          command: 'opencode',
          arguments: const ['web'],
          environment: const {},
          files: const [],
        ),
      ),
    );
    final opening = servers.open(
      spec,
      provider,
      cwd: '/workspace',
      openBrowser: (_) async {},
    );
    await Future.doWhile(() async {
      await Future<void>.value();
      return runtime.requests.isEmpty;
    });
    runtime.output('http://127.0.0.1:4321/\n');
    await opening;
    servers.didChangeAppLifecycleState(AppLifecycleState.detached);
    await Future.doWhile(() async {
      await Future<void>.value();
      return runtime.cancelled.isEmpty;
    });
    expect(runtime.cancelled, hasLength(1));
    expect(servers.running(spec.id), isFalse);
    servers.dispose();
    await runtime.events.close();
  });

  test('changed provider and workspace restart the Web process', () async {
    final runtime = _WebRuntime();
    final inputs = <AcpProviderInput>[];
    final servers = AcpAgentWebServers(
      freePort: () async => 4321,
      prepare: (_, input, port, directory) async {
        inputs.add(input);
        return (
          runtime,
          AcpLaunch(
            command: 'opencode',
            arguments: const ['web'],
            environment: {'MODEL': input.model},
            files: const [],
          ),
        );
      },
    );
    final first = servers.open(
      spec,
      provider,
      cwd: '/workspace',
      openBrowser: (_) async {},
    );
    await Future.doWhile(() async {
      await Future<void>.value();
      return runtime.requests.isEmpty;
    });
    runtime.output('http://127.0.0.1:4321/\n');
    await first;
    const next = AcpProviderInput(
      baseUrl: 'https://second.test/v1',
      apiKey: 'second',
      model: 'next',
    );
    final second = servers.open(
      spec,
      next,
      cwd: '/different',
      openBrowser: (_) async {},
    );
    // The new settings must trigger a replacement process before opening.
    await Future<void>.delayed(Duration.zero);
    expect(runtime.requests, hasLength(2));
    runtime.output('http://127.0.0.1:4321/?token=second\n');
    await second;
    expect(inputs, [provider, next]);
    expect(runtime.requests.last.cwd, '/different');
    expect(runtime.requests.last.env['MODEL'], 'next');
    expect(runtime.cancelled, hasLength(1));
    await servers.stopAll();
    servers.dispose();
    await runtime.events.close();
  });

  for (final id in ['kimi-code', 'deepseek-harness']) {
    test('$id waits for its authenticated printed address', () async {
      final runtime = _WebRuntime();
      final opened = <String>[];
      final servers = AcpAgentWebServers(
        freePort: () async => 4321,
        prepare: (_, input, port, directory) async =>
            (runtime, const AcpLaunch(command: 'agent', arguments: ['web'])),
      );
      final opening = servers.open(
        AcpAgentSpec.byId(id)!,
        provider,
        cwd: '/workspace',
        openBrowser: (url) async => opened.add(url),
      );
      await Future.doWhile(() async {
        await Future<void>.value();
        return runtime.requests.isEmpty;
      });
      runtime.output('Listening: http://127.0.0.1:4321/\n');
      await Future<void>.delayed(Duration.zero);
      expect(opened, isEmpty);
      final url = id == 'kimi-code'
          ? 'http://127.0.0.1:4321#token=secret'
          : 'http://127.0.0.1:4321/?token=secret';
      runtime.output('\u001b[32mLocal: $url\u001b[0m\n');
      await opening;
      expect(opened, [url]);
      await servers.stopAll();
      servers.dispose();
      await runtime.events.close();
    });
  }
}
