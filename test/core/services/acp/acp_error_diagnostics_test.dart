import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:Kelivo/core/services/acp/acp_connection.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/acp/acp_error_messages.dart';
import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/acp/acp_stdio_channel.dart';
import 'package:Kelivo/core/services/mcp/workspace_stdio_transport.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/fake_workspace_runtime.dart';
import '../../../support/business_test_harness.dart';

const _apiKey = 'test-api-key-sentinel';
const _header = 'Bearer test-header-sentinel';

class _RpcErrorRuntime extends FakeWorkspaceRuntime
    implements WorkspaceStdioRuntime {
  final pipe = StreamController<CommandEvent>();
  String stderr =
      'Temp directory /tmp/claude is owned by 1000, expected 0. Refusing '
      'to use it. Set CLAUDE_CODE_TMPDIR. $_apiKey $_header';
  String failAt = 'initialize';
  String rpcMessage = 'Internal error';
  int rpcCode = AcpError.internalError;
  Object? rpcData;
  List<List<int>>? diagnosticChunks;
  bool failBeforeStarted = false;
  bool emitStderr = true;

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    requests.add(request);
    if (!request.keepStdinOpen) {
      return Stream.fromIterable([
        const CommandStarted(),
        if (request.command.contains('__moru_node='))
          CommandOutput(
            OutputStreamKind.stdout,
            Uint8List.fromList(utf8.encode('__moru_node=v24.0.0\n')),
          ),
        const CommandExited(
          exitCode: 0,
          timedOut: false,
          cancelled: false,
          interrupted: false,
          duration: Duration.zero,
        ),
      ]);
    }
    if (failBeforeStarted) {
      _writeStderr();
      pipe.add(
        const CommandExited(
          exitCode: 42,
          timedOut: false,
          cancelled: false,
          interrupted: false,
          duration: Duration.zero,
        ),
      );
      return pipe.stream;
    }
    pipe.add(const CommandStarted());
    return pipe.stream;
  }

  void _writeStderr() {
    // Byte chunks must be joined before secrets are filtered.
    final split = stderr.indexOf('sentinel');
    for (final bytes
        in diagnosticChunks ??
            (split < 0
                ? [utf8.encode(stderr)]
                : [
                    utf8.encode(stderr.substring(0, split)),
                    utf8.encode(stderr.substring(split)),
                  ])) {
      pipe.add(
        CommandOutput(OutputStreamKind.stderr, Uint8List.fromList(bytes)),
      );
    }
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    final request = jsonDecode(utf8.decode(data)) as Map;
    if (request['method'] != failAt) {
      pipe.add(
        CommandOutput(
          OutputStreamKind.stdout,
          Uint8List.fromList(
            utf8.encode(
              '${jsonEncode({
                'id': request['id'],
                'result': request['method'] == 'initialize' ? {'protocolVersion': 1} : {'sessionId': 's1'},
              })}\n',
            ),
          ),
        ),
      );
      return;
    }
    if (emitStderr) _writeStderr();
    pipe.add(
      CommandOutput(
        OutputStreamKind.stdout,
        Uint8List.fromList(
          utf8.encode(
            '${jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'error': {
                'code': rpcCode,
                'message': rpcMessage,
                'data': rpcData ?? {
                      'nested': [
                        {'request': _apiKey, 'Authorization': _header},
                        {'reason': 'safe nested detail'},
                        {_header: 'safe keyed detail'},
                      ],
                    },
              },
            })}\n',
          ),
        ),
      ),
    );
  }

  @override
  Future<void> cancel(String runId) async {
    await pipe.close();
  }
}

Future<AcpError> _managedFailure(
  _RpcErrorRuntime runtime, {
  String apiKey = _apiKey,
  Map<String, String> headers = const {'Authorization': _header},
}) async {
  final manager = AcpAgentManager(
    preferences: createBusinessTestPreferences(),
    runtimeProvider: WorkspaceRuntimeProvider()..register(runtime),
    environment: EnvironmentProvider(
      preferences: createBusinessTestPreferences(),
    ),
  );
  addTearDown(manager.dispose);
  try {
    final agent = await manager.start(
      const AcpAgentSpec(
        id: 'custom:diagnostic',
        name: 'Diagnostic agent',
        command: 'diagnostic-agent',
        installScript: '',
        api: AcpModelApi.any,
        homepage: '',
      ),
      AcpProviderInput(
        baseUrl: 'https://example.invalid',
        apiKey: apiKey,
        model: 'test',
        headers: headers,
      ),
    );
    addTearDown(agent.close);
    await agent.prompt('s1', const []).drain<void>();
  } on AcpError catch (error) {
    return error;
  }
  throw StateError('Expected ACP failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final method in ['initialize', 'session/prompt']) {
    test('$method never retains a key suffix at the stderr tail cut', () async {
      final runtime = _RpcErrorRuntime()..failAt = method;
      runtime.stderr =
          _apiKey + 'x' * (16 * 1024 - utf8.encode(_apiKey).length + 1);
      final error = await _managedFailure(runtime);
      expect(error.details, isNot(contains(_apiKey.substring(1))));
      expect(error.message, 'Internal error');
      expect(utf8.encode(error.details!).length, lessThanOrEqualTo(32 * 1024));
    });
  }

  test(
    'startup failure masks a multiline key cut inside split UTF-8',
    () async {
      const key = '🔑top-secret\nsecond-line\nsuffix-sentinel';
      final runtime = _RpcErrorRuntime()..failBeforeStarted = true;
      runtime.stderr = key + 'x' * (16 * 1024 - utf8.encode(key).length + 1);
      final bytes = utf8.encode(runtime.stderr);
      runtime.diagnosticChunks = [
        bytes.take(2).toList(),
        bytes.skip(2).toList(),
      ];
      final error = await _managedFailure(runtime, apiKey: key);
      expect(error.message, isNot(contains('suffix-sentinel')));
      expect(acpErrorDetails(error), isNot(contains('second-line')));
      expect(acpErrorDetails(error), isNot(contains('suffix-sentinel')));
      expect(error.message, contains('code 42'));
    },
  );

  test('header whitespace is retained until redaction', () async {
    const header = 'Bearer test-header-sentinel ';
    final runtime = _RpcErrorRuntime()
      ..stderr = 'safe reason\n$header'
      ..rpcData = {'Authorization': header};
    final error = await _managedFailure(
      runtime,
      headers: const {'Authorization': header},
    );
    expect(error.details, isNot(contains(header.trim())));
    expect(error.details, contains('safe reason'));
  });

  test(
    'large safe data and durable details are bounded after redaction',
    () async {
      final runtime = _RpcErrorRuntime();
      runtime.rpcData = {
        'nested': '${'data ' * 500000}Invalid API key',
        'Authorization': _header,
        'key': _apiKey,
      };
      final error = await _managedFailure(runtime);
      expect(
        utf8.encode(jsonEncode(error.data)).length,
        lessThanOrEqualTo(16 * 1024),
      );
      expect(utf8.encode(error.details!).length, lessThanOrEqualTo(32 * 1024));
      expect(error.details, contains('owned by 1000, expected 0'));
      expect(error.details, isNot(contains(_apiKey)));
      expect(error.details, isNot(contains(_header)));
      expect(error.failureKind, AcpFailureKind.apiKey);
    },
  );

  test('current RPC failure category wins over stale stderr', () async {
    final runtime = _RpcErrorRuntime();
    final transport = await WorkspaceStdioTransport.start(
      runtime: runtime,
      command: 'agent',
    );
    final connection = AcpConnection(
      AcpStdioChannel(transport),
      onRequest: (_, _) async => null,
      onNotification: (_, _) {},
      redactor: AcpSecretRedactor([_apiKey, _header]),
    );
    addTearDown(() async {
      connection.close();
      await transport.onClose;
    });
    await expectLater(
      connection.request('initialize'),
      throwsA(
        isA<AcpError>().having(
          (e) => e.failureKind,
          'first category',
          AcpFailureKind.temporaryDirectory,
        ),
      ),
    );
    runtime.rpcMessage = 'Invalid API key';
    runtime.emitStderr = false;
    await expectLater(
      connection.request('initialize'),
      throwsA(
        isA<AcpError>().having(
          (e) => e.failureKind,
          'current category',
          AcpFailureKind.apiKey,
        ),
      ),
    );
  });

  test('empty RPC message keeps details across durable hydration', () async {
    final runtime = _RpcErrorRuntime()..rpcMessage = '';
    final error = await _managedFailure(runtime);
    final part = AgentErrorPart(message: error.message, details: error.details);
    expect(MessagePart.fromRow(part.kind, part.encodePayload()), part);
    expect(error.details, contains('safe nested detail'));
  });

  test('bounded errors do not introduce a secret in the truncation marker', () {
    final error = AcpSecretRedactor([
      'truncated',
    ]).error(AcpError(-32603, 'a' * 40000, {'text': 'b' * 40000}));
    expect(error.message, isNot(contains('truncated')));
    expect(error.details, isNot(contains('truncated')));
    expect(error.data.toString(), isNot(contains('truncated')));
  });

  test(
    'overlapping short headers cannot expose a streamed key suffix',
    () async {
      const key = 'sk-review-sensitive-key';
      final runtime = _RpcErrorRuntime()
        ..stderr = key
        ..rpcData = {'reason': 'safe detail'}
        ..diagnosticChunks = [
          utf8.encode('sk-'),
          utf8.encode('review-sensitive-key'),
        ];
      final error = await _managedFailure(
        runtime,
        apiKey: key,
        headers: const {'X-Prefix': 'sk'},
      );
      final part = AgentErrorPart(
        message: error.message,
        details: error.details,
      );
      expect(error.details, isNot(contains('review-sensitive-key')));
      expect(part.encodePayload(), isNot(contains('review-sensitive-key')));
      expect(MessagePart.fromRow(part.kind, part.encodePayload()), part);
    },
  );

  test('ambiguous short matches wait for a longer key and mask at EOF', () {
    final buffer = AcpSecretRedactor([
      'sk-review-sensitive-key',
      'sk',
    ]).textBuffer();
    expect(buffer.add('sk', id: 'text'), isEmpty);
    final eof = buffer.finish().map((part) => part.text).join();
    expect(eof, isNot(contains('sk')));
    expect(eof, isNotEmpty);
  });

  test('cap markers cannot join ordinary text into a known secret', () {
    const key = 'a\n[truncated]';
    final error = AcpSecretRedactor([
      key,
    ]).error(AcpError(-32603, 'a' * 40000, {'data': 'a' * 40000}));
    final part = AgentErrorPart(message: error.message, details: error.details);
    expect(error.message, isNot(contains(key)));
    expect(error.details, isNot(contains(key)));
    expect(error.data.toString(), isNot(contains(key)));
    expect(part.encodePayload(), isNot(contains(r'a\n[truncated]')));
  });

  test('stderr category expires with its bounded raw evidence window', () {
    final diagnostics = AcpSecretRedactor(['Temp directory']).stderrBuffer();
    diagnostics.addBytes(
      utf8.encode('Temp directory unavailable. Refusing to use it.'),
    );
    expect(diagnostics.failureKind, AcpFailureKind.temporaryDirectory);
    diagnostics.addBytes(utf8.encode('ordinary log\n' * 2000));
    expect(diagnostics.failureKind, isNull);
  });

  test('non-Internal RPC errors never inherit old stderr categories', () async {
    final runtime = _RpcErrorRuntime()
      ..rpcMessage = 'Invalid arguments'
      ..rpcCode = AcpError.invalidParams;
    final error = await _managedFailure(runtime);
    expect(error.failureKind, isNull);
    expect(error.details, contains('CLAUDE_CODE_TMPDIR'));
  });

  test(
    'streaming stderr keeps the raw category when phrases are secrets',
    () async {
      final error = await _managedFailure(
        _RpcErrorRuntime(),
        headers: const {
          'Authorization': _header,
          'X-Phrase': 'Temp directory',
          'X-Variable': 'CLAUDE_CODE_TMPDIR',
        },
      );
      expect(error.failureKind, AcpFailureKind.temporaryDirectory);
      expect(error.details, isNot(contains('Temp directory')));
      expect(error.details, isNot(contains('CLAUDE_CODE_TMPDIR')));
      expect(error.details, contains('owned by 1000, expected 0'));
    },
  );

  test(
    'split UTF-8 JSON-escaped keys and headers are filtered before the cap',
    () async {
      const key = '🔑"quoted"\\path{token}\nline-sentinel';
      const header = 'Bearer header"quotes"\\{json}-sentinel ';
      final runtime = _RpcErrorRuntime();
      runtime.stderr = 'prefix: ${jsonEncode(key)} ${jsonEncode(header)}';
      runtime.rpcData = {
        'nested': [
          {'key': key, 'header': header},
        ],
      };
      final bytes = utf8.encode(runtime.stderr);
      // "prefix: " and the opening JSON quote precede the four-byte emoji.
      runtime.diagnosticChunks = [
        bytes.take(11).toList(),
        bytes.skip(11).toList(),
      ];
      final error = await _managedFailure(
        runtime,
        apiKey: key,
        headers: const {'Authorization': header},
      );
      expect(error.details, contains('prefix:'));
      expect(error.details, isNot(contains('line-sentinel')));
      expect(error.details, isNot(contains('{json}-sentinel')));
      expect(jsonEncode(error.data), isNot(contains('line-sentinel')));
      expect(jsonEncode(error.data), isNot(contains('{json}-sentinel')));
    },
  );

  test('diagnostic byte caps preserve valid Unicode code points', () {
    final error = AcpSecretRedactor(
      const [],
    ).error(AcpError(-32603, '界' * 20000, {'value': '😀' * 10000}));
    expect(utf8.encode(error.message).length, lessThanOrEqualTo(4 * 1024));
    expect(
      utf8.encode(jsonEncode(error.data)).length,
      lessThanOrEqualTo(16 * 1024),
    );
    expect(utf8.encode(error.details!).length, lessThanOrEqualTo(32 * 1024));
    expect(error.message, isNot(contains('\uFFFD')));
    expect(error.details, isNot(contains('\uFFFD')));
  });
  for (final method in ['initialize', 'session/prompt']) {
    test(
      '$method classifies temporary-directory failure from stderr',
      () async {
        final runtime = _RpcErrorRuntime()..failAt = method;
        final transport = await WorkspaceStdioTransport.start(
          runtime: runtime,
          command: 'agent',
        );
        final connection = AcpConnection(
          AcpStdioChannel(transport),
          onRequest: (_, _) async => null,
          onNotification: (_, _) {},
          // Also remove the diagnostic phrase to prove classification happens
          // before redaction, rather than matching the safe text afterwards.
          redactor: AcpSecretRedactor([
            _apiKey,
            _header,
            'Temp directory',
            'CLAUDE_CODE_TMPDIR',
          ]),
        );
        addTearDown(() async {
          connection.close();
          await transport.onClose;
        });
        await expectLater(
          connection.request(method),
          throwsA(
            isA<AcpError>()
                .having((e) => e.message, 'original message', 'Internal error')
                .having(
                  (e) => e.details,
                  'full safe diagnostic details',
                  allOf([
                    contains('Internal error'),
                    contains('safe nested detail'),
                    contains('safe keyed detail'),
                    contains('owned by 1000, expected 0'),
                    isNot(contains(_apiKey)),
                    isNot(contains(_header)),
                    isNot(contains('Temp directory')),
                    isNot(contains('CLAUDE_CODE_TMPDIR')),
                  ]),
                )
                .having(
                  (e) => jsonEncode(e.data),
                  'recursively redacted JSON-RPC data',
                  allOf(
                    contains('safe nested detail'),
                    contains('safe keyed detail'),
                    isNot(contains(_apiKey)),
                    isNot(contains(_header)),
                  ),
                )
                .having(
                  (e) => classifyAcpFailure(e)?.name,
                  'category from stderr before redaction',
                  'temporaryDirectory',
                ),
          ),
        );
      },
    );
  }

  test('unrelated file EACCES is not a temporary-directory failure', () {
    expect(
      classifyAcpFailure(
        const AcpError(-32603, 'EACCES: permission denied, open /workspace/a'),
      ),
      isNull,
    );
  });

  test('localization retains the original diagnostic reason', () {
    final l10n = lookupAppLocalizations(const Locale('ru'));
    final error = localizeAcpError(
      const AcpError(-32603, 'Invalid API key: account needs attention'),
      l10n,
    );
    expect(error.toString(), l10n.agentsErrorApiKey);
    expect((error as AcpError).details, contains('account needs attention'));
  });

  test('JSON-RPC details use the bounded stderr tail', () async {
    final runtime = _RpcErrorRuntime();
    runtime.stderr = '${'old output ' * 2000}\n${runtime.stderr}';
    final transport = await WorkspaceStdioTransport.start(
      runtime: runtime,
      command: 'agent',
    );
    final connection = AcpConnection(
      AcpStdioChannel(transport),
      onRequest: (_, _) async => null,
      onNotification: (_, _) {},
      redactor: AcpSecretRedactor([_apiKey, _header]),
    );
    addTearDown(() async {
      connection.close();
      await transport.onClose;
    });
    await expectLater(
      connection.request('initialize'),
      throwsA(
        isA<AcpError>().having(
          (e) => e.details,
          'bounded details with recent stderr and JSON data',
          allOf(
            hasLength(lessThan(17 * 1024)),
            contains('CLAUDE_CODE_TMPDIR'),
            contains('safe nested detail'),
            isNot(contains(_apiKey)),
            isNot(contains(_header)),
          ),
        ),
      ),
    );
  });

  for (final locale in [
    const Locale('en'),
    const Locale('ru'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    test(
      '$locale localizes temporary-directory error and preserves details',
      () {
        final l10n = lookupAppLocalizations(locale);
        const original = AcpError(-32603, 'Internal error', {
          'reason': 'Temp directory is unavailable',
        });
        final safeError = localizeAcpError(original, l10n) as AcpError;
        expect(safeError.message, l10n.agentsErrorTemporaryDirectory);
        expect(
          acpErrorDetails(safeError),
          contains('Temp directory is unavailable'),
        );
        expect(acpErrorDetails(safeError), contains('Internal error'));
        expect(safeError.code, original.code);
        expect(safeError.data, original.data);
      },
    );
  }
}
