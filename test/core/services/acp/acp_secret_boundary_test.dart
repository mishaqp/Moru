import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/environment_variable.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_error_messages.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk_handler.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_workspace_runtime.dart';

const _provider = AcpProviderInput(
  baseUrl: 'https://example.invalid/v1',
  apiKey: 'fake-api-key-sentinel',
  model: 'test-model',
  headers: {
    'Authorization': 'Bearer fake-header-sentinel',
    'X-Ordinary': 'ordinary-header-sentinel',
    'X-Empty': '',
  },
);
const _password = 'fake-web-password-sentinel';
const _secrets = [
  'fake-api-key-sentinel',
  'Bearer fake-header-sentinel',
  'ordinary-header-sentinel',
  _password,
];

CommandExited _exit() => const CommandExited(
  exitCode: 42,
  timedOut: false,
  cancelled: false,
  interrupted: false,
  duration: Duration.zero,
);

// Echoes only values actually supplied to the fake process, never a fixture
// copied directly into an error. STDIO framing/decoding remain production code.
class _DiagnosticRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  String? failAt;
  int errorCode = -32042;
  String reason = 'Unrecognized frobnicator failure';
  bool echoSecrets = true;
  final _pipes = <String, StreamController<CommandEvent>>{};
  final _env = <String, Map<String, String>>{};
  final messages = <Map>[];

  String diagnostic(Map<String, String> env) => echoSecrets
      ? [
          reason,
          env['MORU_AGENT_API_KEY'],
          env['ANTHROPIC_CUSTOM_HEADERS'],
          env['OPENCODE_SERVER_PASSWORD'],
          ...env.entries
              .where((entry) => entry.key.startsWith('MORU_AGENT_HEADER_'))
              .map((entry) => entry.value),
        ].whereType<String>().join(' | ')
      : reason;

  CommandOutput output(
    String text, [
    OutputStreamKind kind = OutputStreamKind.stdout,
  ]) => CommandOutput(kind, Uint8List.fromList(utf8.encode(text)));

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (request.keepStdinOpen && failAt == 'socket') {
      return Stream.error(SocketException(diagnostic(request.env)));
    }
    if (request.keepStdinOpen && failAt == 'startup') {
      return Stream.error(StateError(diagnostic(request.env)));
    }
    if (request.keepStdinOpen) {
      _env[request.runId] = request.env;
      final pipe = StreamController<CommandEvent>();
      _pipes[request.runId] = pipe;
      pipe.add(const CommandStarted());
      if (failAt == 'stderr') {
        final text = diagnostic(request.env);
        // A secret split between byte chunks must still be removed.
        final split = text.indexOf('sentinel');
        pipe.add(output(text.substring(0, split), OutputStreamKind.stderr));
        pipe.add(output(text.substring(split), OutputStreamKind.stderr));
        pipe.add(_exit());
      }
      return pipe.stream;
    }
    if (failAt == 'setup' && request.env.containsKey('MORU_AGENT_API_KEY')) {
      return Stream.fromIterable([
        const CommandStarted(),
        output(diagnostic(request.env), OutputStreamKind.stderr),
        _exit(),
      ]);
    }
    if (failAt == 'node' && request.command.contains('__moru_node=')) {
      return Stream.fromIterable([
        const CommandStarted(),
        output('__moru_node=${diagnostic(request.env)}\n'),
        _exit(),
      ]);
    }
    return Stream.fromIterable([
      const CommandStarted(),
      if (request.command.contains('__moru_node='))
        output('__moru_node=v24.0.0\n'),
      const CommandExited(
        exitCode: 0,
        timedOut: false,
        cancelled: false,
        interrupted: false,
        duration: Duration.zero,
      ),
    ]);
  }

  void emit(String runId, Map<String, Object?> value) =>
      _pipes[runId]!.add(output('${jsonEncode(value)}\n'));

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    if (failAt == 'stderr') return;
    final env = _env[runId]!;
    for (final line in const LineSplitter().convert(utf8.decode(data))) {
      final request = jsonDecode(line) as Map;
      messages.add(request);
      final method = request['method'];
      if (method == null) continue;
      if (failAt == 'malformed' && method == 'initialize') {
        _pipes[runId]!.add(output('bad JSON: ${diagnostic(env)}\n'));
        continue;
      }
      if (failAt == method) {
        _pipes[runId]!.add(output(diagnostic(env), OutputStreamKind.stderr));
        emit(runId, {
          'id': request['id'],
          'error': {
            'code': errorCode,
            'message': diagnostic(env),
            'data': {
              'nested': [
                diagnostic(env),
                {diagnostic(env): 'safe detail'},
              ],
            },
          },
        });
        continue;
      }
      if (method == 'session/prompt') {
        final text = diagnostic(env);
        void update(Map<String, Object?> update) => emit(runId, {
          'method': 'session/update',
          'params': {'sessionId': 's1', 'update': update},
        });
        update({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': text},
        });
        update({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': text},
        });
        update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'title': text,
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {'command': text, 'type': text},
          'diagnostic': {'status': text, 'id': text},
          text: 'safe diagnostic extension',
        });
        emit(runId, {
          'id': 'permission',
          'method': 'session/request_permission',
          'params': {
            'sessionId': 's1',
            'toolCall': {
              'toolCallId': 't1',
              'title': text,
              'rawInput': {'command': text},
            },
            'options': [
              {'optionId': 'option-yes', 'kind': 'allow_once', 'name': text},
            ],
          },
        });
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 't1',
          'status': 'completed',
          'rawOutput': {'status': text},
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': text},
            },
          ],
        });
      }
      emit(runId, {
        'id': request['id'],
        'result': switch (method) {
          'initialize' => {
            'protocolVersion': 1,
            'agentInfo': {'name': diagnostic(env)},
          },
          'session/new' => {'sessionId': 's1'},
          _ => {'stopReason': 'end_turn'},
        },
      });
    }
  }

  @override
  Future<void> cancel(String runId) async {
    final pipe = _pipes.remove(runId);
    if (pipe != null) await pipe.close();
  }
}

void _expectSafe(Object? surfaced) {
  final text = surfaced.toString();
  for (final secret in _secrets) {
    expect(text, isNot(contains(secret)), reason: 'Launch secret surfaced');
  }
  expect(text, contains('frobnicator'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _DiagnosticRuntime runtime;
  late AcpAgentManager manager;
  final spec = AcpAgentSpec.byId('claude-code')!;

  setUp(() async {
    runtime = _DiagnosticRuntime();
    final environment = EnvironmentProvider(
      preferences: createBusinessTestPreferences(),
    );
    await environment.saveVariable(
      const EnvironmentVariable(
        name: 'OPENCODE_SERVER_PASSWORD',
        value: _password,
      ),
    );
    manager = AcpAgentManager(
      preferences: createBusinessTestPreferences(),
      runtimeProvider: WorkspaceRuntimeProvider()..register(runtime),
      environment: environment,
    );
    addTearDown(manager.dispose);
  });

  for (final failure in [
    'initialize',
    'stderr',
    'setup',
    'startup',
    'malformed',
  ]) {
    test(
      'launch $failure diagnostics redact all secrets in check and lastCheck',
      () async {
        runtime.failAt = failure;
        final result = await manager.check(spec, _provider);
        expect(result.ok, isFalse);
        _expectSafe(result.error);
        _expectSafe(manager.lastCheck(spec.id)!.error);
        for (final secret in _secrets) {
          expect(manager.log, isNot(contains(secret)));
        }
        expect(result.failureKind, isNull);
        if (failure == 'stderr') expect(result.error, contains('code 42'));
      },
    );
  }

  for (final (code, reason, kind) in [
    (-32042, 'Unrecognized frobnicator failure', null),
    (401, 'Unrecognized frobnicator failure', AcpFailureKind.apiKey),
    (
      AcpError.authRequired,
      'Invalid API key: frobnicator failure',
      AcpFailureKind.apiKey,
    ),
    (
      AcpError.invalidParams,
      'Model not found: frobnicator failure',
      AcpFailureKind.model,
    ),
    (
      AcpError.internalError,
      'connect ECONNREFUSED: frobnicator failure',
      AcpFailureKind.network,
    ),
  ]) {
    test(
      'JSON-RPC $code preserves reason/code with recursively redacted data',
      () async {
        runtime
          ..failAt = 'initialize'
          ..errorCode = code
          ..reason = reason;
        try {
          await manager.start(spec, _provider);
          fail('Expected agent error');
        } on AcpError catch (error) {
          expect(error.code, code);
          expect(error.message, contains(reason));
          _expectSafe(error.message);
          _expectSafe(error.data);
          expect(error.data.toString(), contains('safe detail'));
          expect(classifyAcpFailure(error), kind);
        }
      },
    );
  }

  test(
    'chat chunks, stored tool cards and permission payloads redact launch secrets',
    () async {
      final agent = await manager.start(spec, _provider);
      addTearDown(agent.close);
      _expectSafe(agent.info.name);
      final session = await agent.newSession(cwd: '/workspace');
      final permissions = <AcpPermissionRequest>[];
      final updates = <Map<String, Object?>>[];
      agent.onPermission = (permission) async {
        permissions.add(permission);
        return permission.options.single.id;
      };
      agent.onToolUpdate = (_, update) => updates.add(update);
      final chunks = await agent.prompt(session.id, []).toList();
      _expectSafe(chunks.whereType<TextDelta>().single.text);
      _expectSafe(chunks.whereType<ReasoningDelta>().single.text);
      _expectSafe(chunks.whereType<ServerToolStart>().first.input);
      _expectSafe(chunks.whereType<ServerToolEnd>().single.output);
      _expectSafe(chunks.whereType<ServerToolEnd>().single.metadata);
      _expectSafe(updates);
      _expectSafe(permissions.single.title);
      _expectSafe(permissions.single.input);
      _expectSafe(permissions.single.options.single.name);
      final stored = StreamChunkHandler.collect(chunks).parts;
      _expectSafe(stored.whereType<ToolCallPart>().single.payloadJson);
      _expectSafe(stored.whereType<TextPart>().single.text);
    },
  );

  for (final (header, reason, failure, kind) in [
    (
      'API key',
      'Invalid API key: frobnicator failure',
      'initialize',
      AcpFailureKind.apiKey,
    ),
    (
      'network',
      'network error: frobnicator failure',
      'initialize',
      AcpFailureKind.network,
    ),
    (
      'SocketException',
      'frobnicator failure',
      'socket',
      AcpFailureKind.network,
    ),
  ]) {
    test(
      'recognized $kind survives redaction of the diagnostic phrase $header',
      () async {
        final provider = AcpProviderInput(
          baseUrl: 'https://example.invalid',
          apiKey: '',
          model: 'test',
          headers: {'X-Phrase': header},
        );
        runtime
          ..failAt = failure
          ..reason = reason;
        final result = await manager.check(spec, provider);
        expect(result.error, isNot(contains(header)));
        expect(result.error, contains('frobnicator'));
        expect(result.failureKind, kind);
        try {
          await manager.start(spec, provider);
          fail('Expected agent error');
        } on AcpError catch (error) {
          expect(error.message, isNot(contains(header)));
          expect(classifyAcpFailure(error), kind);
        }
      },
    );
  }

  test('short headers leave valid Node version control data intact', () async {
    const provider = AcpProviderInput(
      baseUrl: 'https://example.invalid',
      apiKey: '',
      model: 'test',
      headers: {'X-Node': '24'},
    );
    final agent = await manager.start(
      AcpAgentSpec.byId('kimi-code')!,
      provider,
    );
    addTearDown(agent.close);
    expect(agent.isAlive, isTrue);
    expect(manager.nodeIssueFor(AcpAgentSpec.byId('kimi-code')!), isNull);
  });

  test(
    'node check diagnostics redact secrets before exposing the node issue',
    () async {
      runtime.failAt = 'node';
      final spec = AcpAgentSpec.byId('kimi-code')!;
      final result = await manager.check(spec, _provider);
      expect(result.ok, isFalse);
      _expectSafe(result.nodeIssue!.actual);
      _expectSafe(manager.nodeIssueFor(spec)!.actual);
      _expectSafe(result.error);
    },
  );

  test(
    'the redaction marker cannot itself reproduce a configured header value',
    () async {
      const provider = AcpProviderInput(
        baseUrl: 'https://example.invalid',
        apiKey: '',
        model: 'test',
        headers: {'X-Short': 'REDACTED'},
      );
      runtime.failAt = 'initialize';
      final result = await manager.check(spec, provider);
      expect(result.error, isNot(contains('REDACTED')));
      expect(result.error, contains('frobnicator'));
    },
  );

  test('nonsecret unknown JSON-RPC diagnostics remain intact', () async {
    runtime
      ..failAt = 'initialize'
      ..echoSecrets = false
      ..reason =
          r'Unknown frobnicator: preserve $HOME, "quotes" and unicode é中';
    final result = await manager.check(spec, _provider);
    expect(result.error, runtime.reason);
    expect(result.failureKind, isNull);
  });

  test(
    'Web failure never surfaces the generated OpenCode password or diagnostics',
    () async {
      runtime.failAt = 'stderr';
      Object? surfaced;
      try {
        await manager.webServers.open(
          AcpAgentSpec.byId('opencode')!,
          _provider,
          cwd: '/workspace',
          openBrowser: (_) async => fail('Unexpected browser opening'),
        );
        fail('Expected Web process failure');
      } catch (error) {
        surfaced = error;
      }
      final launch = runtime.requests.singleWhere(
        (request) => request.keepStdinOpen,
      );
      final password = launch.env['OPENCODE_SERVER_PASSWORD']!;
      expect(password, isNot(_password));
      expect(surfaced.toString(), isNot(contains(password)));
      for (final secret in _secrets) {
        expect(surfaced.toString(), isNot(contains(secret)));
        expect(manager.log, isNot(contains(secret)));
      }
      expect(manager.log, isNot(contains(password)));
      expect(surfaced.toString(), contains('exited'));
    },
  );

  test(
    'short header values do not alter ACP routing or control values',
    () async {
      const short = AcpProviderInput(
        baseUrl: 'https://example.invalid',
        apiKey: '',
        model: 'test',
        headers: {
          'X-Session': 's1',
          'X-Type': 'text',
          'X-Field': 'name',
          'X-Kind': 'execute',
          'X-Status': 'completed',
          'X-Method': 'session/update',
          'X-Option': 'option-yes',
          'X-Allow': 'allow_once',
        },
      );
      final agent = await manager.start(spec, short);
      expect(agent.info.name, contains('frobnicator'));
      addTearDown(agent.close);
      final session = await agent.newSession(cwd: '/workspace');
      expect(session.id, 's1');
      agent.onPermission = (request) async {
        expect(request.options.single.kind, 'allow_once');
        return request.options.single.id;
      };
      final chunks = await agent.prompt(session.id, []).toList();
      expect(chunks.whereType<TextDelta>(), hasLength(1));
      expect(chunks.whereType<TextDelta>().single.text, contains('[REDACTED]'));
      expect(chunks.whereType<ServerToolStart>().first.toolName, 'shell');
      expect(
        chunks.whereType<ServerToolEnd>().single.status,
        ServerToolStatus.completed,
      );
      expect(
        runtime.messages
            .where((message) => message['id'] == 'permission')
            .single['result'],
        {
          'outcome': {'outcome': 'selected', 'optionId': 'option-yes'},
        },
      );
      for (final value in short.headers.values) {
        expect(
          chunks.whereType<TextDelta>().single.text,
          isNot(contains(value)),
        );
      }
    },
  );
}
