import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_error_messages.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/agents/pages/agents_page.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_workspace_runtime.dart';

CommandExited _exit(int code) => CommandExited(
  exitCode: code,
  timedOut: false,
  cancelled: false,
  interrupted: false,
  duration: Duration.zero,
);

/// Scripts answer by what they contain; a process kept open is a fake agent
/// that answers `initialize`.
class _AgentRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  String probeOutput = '';
  int installExit = 0;
  bool moruAvailable = true;
  bool agentMissing = false;
  String nodeVersion = 'v24.0.0';
  final _agents = <String, StreamController<CommandEvent>>{};
  final cancelled = <String>[];

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (request.keepStdinOpen && agentMissing) {
      // What the guest shell reports when the command is not installed.
      return Stream.fromIterable([
        const CommandStarted(),
        CommandOutput(
          OutputStreamKind.stderr,
          Uint8List.fromList(
            utf8.encode('kelivo: exec: codex-acp: not found\n'),
          ),
        ),
        _exit(127),
      ]);
    }
    if (request.keepStdinOpen) {
      final events = StreamController<CommandEvent>();
      _agents[request.runId] = events;
      events.add(const CommandStarted());
      return events.stream;
    }
    final script = request.command;
    final String output;
    final int code;
    if (request.env.containsKey('MORU_MCP_TOKEN')) {
      output = moruAvailable ? '__moru_mcp_available__\n' : '';
      code = moruAvailable ? 0 : 1;
    } else if (script.contains('__moru_node=')) {
      output = '__moru_node=$nodeVersion\n$probeOutput';
      code = 0;
    } else if (script.contains('__acp_')) {
      output = probeOutput;
      code = 0;
    } else if (script.contains('npm install')) {
      output = 'added 42 packages in 9s\n';
      code = installExit;
    } else {
      output = '';
      code = 0;
    }
    return Stream.fromIterable([
      const CommandStarted(),
      if (output.isNotEmpty)
        CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(utf8.encode(output)),
        ),
      _exit(code),
    ]);
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    for (final line in const LineSplitter().convert(utf8.decode(data))) {
      final message = jsonDecode(line) as Map;
      if (message['method'] != 'initialize') continue;
      _agents[runId]!.add(
        CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(
            utf8.encode(
              '${jsonEncode({
                'jsonrpc': '2.0',
                'id': message['id'],
                'result': {
                  'protocolVersion': 1,
                  'agentInfo': {'name': 'codex-acp', 'version': '1.10.0'},
                },
              })}\n',
            ),
          ),
        ),
      );
    }
  }

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    final agent = _agents.remove(runId);
    if (agent != null) {
      agent.add(_exit(143));
      await agent.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _AgentRuntime runtime;
  late WorkspaceRuntimeProvider runtimeProvider;
  late EnvironmentProvider environment;

  AcpAgentManager manager({prefs}) => AcpAgentManager(
    preferences: prefs ?? createBusinessTestPreferences(),
    runtimeProvider: runtimeProvider,
    environment: environment,
  );

  setUp(() {
    runtime = _AgentRuntime();
    runtimeProvider = WorkspaceRuntimeProvider()..register(runtime);
    environment = EnvironmentProvider(
      preferences: createBusinessTestPreferences(),
    );
  });

  const provider = AcpProviderInput(
    baseUrl: 'https://api.openai.com/v1',
    apiKey: 'sk-test',
    model: 'gpt-5',
    responsesApi: true,
  );

  test('new agents reject old Node before any npm installation', () async {
    runtime.nodeVersion = 'v18.19.1';
    final agents = manager();
    final spec = AcpAgentSpec.byId('deepseek-harness')!;
    await agents.install(spec);
    expect(agents.nodeIssueFor(spec), isNotNull);
    expect(agents.state(spec.id), isNot(AcpInstallState.installed));
    expect(
      runtime.requests.any((r) => r.command.contains('npm install')),
      isFalse,
    );
    agents.dispose();
  });

  test(
    'DSH rejects Node 23 and unreadable versions; Kimi accepts Node 23',
    () async {
      final agents = manager();
      final dsh = AcpAgentSpec.byId('deepseek-harness')!;
      runtime.nodeVersion = 'v23.11.0';
      await agents.install(dsh);
      expect(agents.nodeIssueFor(dsh), isNotNull);
      await agents.install(AcpAgentSpec.byId('kimi-code')!);
      expect(agents.failure, isNull);
      runtime.nodeVersion = '';
      await agents.install(dsh);
      expect(agents.nodeIssueFor(dsh), isNotNull);
      agents.dispose();
    },
  );

  test(
    'fresh Node probe gates agent start even after a previous good refresh',
    () async {
      final agents = manager();
      runtime.probeOutput = '__acp_deepseek-harness=1\n';
      await agents.refresh();
      final dsh = AcpAgentSpec.byId('deepseek-harness')!;
      expect(agents.nodeIssueFor(dsh), isNull);
      runtime.nodeVersion = 'v22.18.0';
      await expectLater(agents.start(dsh, provider), throwsA(isA<Exception>()));
      expect(agents.nodeIssueFor(dsh), isNotNull);
      expect(runtime.requests.any((r) => r.keepStdinOpen), isFalse);
      agents.dispose();
    },
  );

  for (final id in ['kimi-code', 'deepseek-harness']) {
    test('$id check includes the actual Moru tools probe', () async {
      final agents = manager();
      final result = await agents.check(AcpAgentSpec.byId(id)!, provider);
      expect(result.ok, isTrue);
      expect(result.moruToolsAvailable, isTrue);
      expect(
        runtime.requests.any((r) => r.env.containsKey('MORU_MCP_TOKEN')),
        isTrue,
      );
      agents.dispose();
    });
  }

  test(
    'Web output including the login token never enters the agent log',
    () async {
      final agents = manager();
      final opening = agents.webServers.open(
        AcpAgentSpec.byId('opencode')!,
        provider,
        cwd: '/workspace',
        openBrowser: (_) async {},
      );
      await Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        return !runtime.requests.any((r) => r.keepStdinOpen);
      });
      final request = runtime.requests.last;
      runtime._agents[request.runId]!.add(
        CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(
            utf8.encode('http://127.0.0.1:12345/#token=private-web-token\n'),
          ),
        ),
      );
      await opening;
      expect(agents.log, isEmpty);
      expect(request.command, isNot(contains('private-web-token')));
      await agents.webServers.stopAll();
      agents.dispose();
    },
  );

  test('refresh finds which agents are installed', () async {
    runtime.probeOutput =
        '__acp_claude-code=1\n__acp_codex=0\n__acp_opencode=0\n';
    final agents = manager();
    await agents.refresh();
    expect(agents.state('claude-code'), AcpInstallState.installed);
    expect(agents.state('codex'), AcpInstallState.missing);
    expect(agents.state('opencode'), AcpInstallState.missing);
    // The probe looks on the npm prefix too.
    expect(
      runtime.requests.single.env['PATH'],
      startsWith('$acpNpmPrefix/bin:'),
    );
  });

  test('install runs the npm script, keeps its log and marks the agent '
      'installed', () async {
    final agents = manager();
    final spec = AcpAgentSpec.byId('codex')!;
    await agents.install(spec);
    expect(agents.failure, isNull);
    expect(agents.state('codex'), AcpInstallState.installed);
    expect(agents.log, contains('added 42 packages'));
    expect(runtime.requests.single.command, spec.installScript);
    expect(agents.busy, isFalse);
  });

  test('a failed install says so and keeps the log', () async {
    runtime.installExit = 1;
    final agents = manager();
    await agents.install(AcpAgentSpec.byId('codex')!);
    expect(agents.failure, AcpAgentFailure.install);
    expect(agents.failedAgentId, 'codex');
    expect(agents.state('codex'), isNot(AcpInstallState.installed));
    expect(agents.log, contains('added 42 packages'));
  });

  test('without the Linux environment nothing starts', () async {
    runtimeProvider = WorkspaceRuntimeProvider();
    final agents = manager();
    await agents.install(AcpAgentSpec.byId('codex')!);
    expect(agents.failure, AcpAgentFailure.noEnvironment);
    expect(agents.environmentAvailable, isFalse);
  });

  test('check writes the agent settings, starts it with the provider and '
      'greets it', () async {
    final agents = manager();
    final result = await agents.check(AcpAgentSpec.byId('codex')!, provider);
    expect(result.ok, isTrue, reason: result.error);
    expect(result.info!.name, 'codex-acp');
    expect(result.moruToolsAvailable, isTrue);
    expect(agents.lastCheck('codex')?.info?.version, '1.10.0');
    expect(agents.state('codex'), AcpInstallState.installed);

    final write = runtime.requests.singleWhere(
      (r) => r.command.contains('base64 -d'),
    );
    expect(write.command, contains('base64 -d'));
    // The key stays out of the settings file and the script.
    expect(write.command, isNot(contains('sk-test')));
    final launch = runtime.requests.singleWhere((r) => r.keepStdinOpen);
    expect(launch.keepStdinOpen, isTrue);
    expect(launch.command, "exec 'codex-acp'");
    expect(launch.env['MORU_CODEX_API_KEY'], 'sk-test');
    expect(launch.env['CODEX_HOME'], '$acpConfigDir/codex');
    // The check stops the agent again.
    expect(runtime.cancelled, contains(launch.runId));
  });

  test(
    'a check whose command is gone marks the agent as not installed',
    () async {
      runtime.probeOutput = '__acp_codex=1\n';
      final agents = manager();
      await agents.refresh();
      expect(agents.state('codex'), AcpInstallState.installed);
      // A switched distribution no longer has the agent.
      runtime
        ..agentMissing = true
        ..probeOutput = '__acp_codex=0\n';
      final result = await agents.check(AcpAgentSpec.byId('codex')!, provider);
      expect(result.ok, isFalse);
      expect(isAcpCommandMissing(result.error!), isTrue, reason: result.error);
      expect(agents.state('codex'), AcpInstallState.missing);
    },
  );

  test(
    'a new check reports unavailable instead of keeping the previous result',
    () async {
      final agents = manager();
      final spec = AcpAgentSpec.byId('codex')!;
      expect((await agents.check(spec, provider)).moruToolsAvailable, isTrue);
      runtime.moruAvailable = false;
      final result = await agents.check(spec, provider);
      expect(result.ok, isTrue);
      expect(result.moruToolsAvailable, isFalse);
      expect(agents.lastCheck(spec.id)!.moruToolsAvailable, isFalse);
      final probes = runtime.requests
          .where((r) => r.env.containsKey('MORU_MCP_TOKEN'))
          .toList();
      expect(probes, hasLength(2));
      expect(
        probes[0].env['MORU_MCP_TOKEN'],
        isNot(probes[1].env['MORU_MCP_TOKEN']),
      );
      for (final probe in probes) {
        expect(probe.command, isNot(contains(probe.env['MORU_MCP_TOKEN'])));
      }
    },
  );

  test('your own agents are kept and can be deleted', () async {
    final prefs = createBusinessTestPreferences();
    final first = manager(prefs: prefs);
    await first.loaded;
    final spec = await first.saveCustomAgent(
      name: 'Goose',
      command: 'goose',
      arguments: const ['acp'],
    );
    expect(first.agents.last.name, 'Goose');

    final second = manager(prefs: prefs);
    await second.loaded;
    final kept = second.agent(spec.id)!;
    expect(kept.command, 'goose');
    expect(kept.arguments, ['acp']);
    expect(kept.isCustom, isTrue);

    await second.deleteCustomAgent(spec.id);
    final third = manager(prefs: prefs);
    await third.loaded;
    expect(third.customAgents, isEmpty);
  });

  test('the settings script writes files byte for byte', () async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final dir = await Directory.systemTemp.createTemp('acp-config-');
    addTearDown(() => dir.delete(recursive: true));
    const content = 'model = "gpt\'s \$HOME"\né中 `x`\n';
    final path = '${dir.path}/deep/it\'s/config.toml';
    final result = await Process.run('/bin/sh', [
      '-c',
      AcpAgentManager.writeFilesScript([AcpConfigFile(path, content)]),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await File(path).readAsString(), content);
  });

  test('a command line is split into words, honouring quotes', () {
    expect(splitCommandLine('goose acp'), ['goose', 'acp']);
    expect(splitCommandLine('  my-agent --dir "a b" \'c d\' '), [
      'my-agent',
      '--dir',
      'a b',
      'c d',
    ]);
    expect(splitCommandLine('agent ""'), ['agent', '']);
    expect(splitCommandLine('   '), isEmpty);
  });
}
