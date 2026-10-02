import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_mcp_binding.dart';
import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/acp/acp_turn_translator.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk_handler.dart';

const _access = 'sk-ant-oat01-access-sentinel-0123456789';
const _refresh = 'sk-ant-ort01-refresh-sentinel-0123456789';
const _jwt =
    'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJmYWtlLW9hdXRoLXNlbnRpbmVsIn0.signature-sentinel';
const _jwtWithWhitespace =
    'IHsgImFsZyI6ICJIUzI1NiIgfQ.IHsgInN1YiI6ICJzZW50aW5lbCIgfQ.signature-sentinel';
const _opaque = 'opaque-oauth-credential-sentinel';
const _code = 'ABCD-EFGH';
const _fragmentArtifacts = <(String, String)>[
  ('https://login.example/#state=$_opaque', _opaque),
  ('https://login.example/#code=$_opaque', _opaque),
  ('https://login.example/#access_token=$_opaque', _opaque),
  ('https://login.example/#id_token=$_jwt', 'signature-sentinel'),
  ('https://login.example/#device_code=$_opaque', _opaque),
  ('https://login.example/#/callback?code=$_opaque', _opaque),
  ('https://login.example/#%61ccess_token=$_opaque', _opaque),
  ('https://login.example/#access_token%3D$_opaque%26state%3Dpublic', _opaque),
  ('https://login.example/?language=%XX#device_code=$_opaque', _opaque),
];

AcpSecretRedactor _redactor() =>
    AcpSecretRedactor(const [], protectAuthentication: true);

void main() {
  test('config option ids and values stay routable, labels are redacted', () {
    final option = {
      'id': 'model',
      'name': 'Model $_access',
      'description': 'Uses $_opaque',
      'category': 'model',
      'type': 'select',
      'currentValue': 'gpt-6.1-sol',
      'options': [
        {'value': 'gpt-6.1-sol', 'name': '6.1 Sol'},
        {
          'group': 'older',
          'name': 'Older',
          'options': [
            {'value': 'gpt-5.5', 'description': 'Token $_refresh'},
          ],
        },
      ],
    };
    for (final safe in [
      _redactor().protocol({
            'sessionId': 's',
            'configOptions': [option],
          })
          as Map,
      (_redactor().protocol({
                'update': {
                  'sessionUpdate': 'config_option_update',
                  'configOptions': [option],
                },
              })
              as Map)['update']
          as Map,
    ]) {
      final parsed = AcpConfigOption.listFrom(safe['configOptions']).single;
      expect(parsed.id, 'model');
      expect(parsed.category, 'model');
      expect(parsed.currentValue, 'gpt-6.1-sol');
      expect(parsed.values.map((v) => v.value), ['gpt-6.1-sol', 'gpt-5.5']);
      expect(parsed.values.first.name, '6.1 Sol');
      expect(safe.toString(), isNot(contains('access-sentinel')));
      expect(safe.toString(), isNot(contains('signature-sentinel')));
      expect(safe.toString(), isNot(contains('refresh-sentinel')));
    }
  });

  const artifacts = <(String, String)>[
    (_access, 'access-sentinel'),
    (_refresh, 'refresh-sentinel'),
    (_jwt, 'signature-sentinel'),
    (_jwtWithWhitespace, 'signature-sentinel'),
    ('{"access_token":"$_opaque"}', _opaque),
    ('refresh_token = "$_opaque"', _opaque),
    ('idToken: $_opaque', _opaque),
    ('device_code: $_opaque', _opaque),
    ('User code: $_code', _code),
    ('Authorization code: $_opaque', _opaque),
    ('Enter this one-time code: $_code', _code),
    ('Enter this one-time code\n\n$_code\n', _code),
    ('Enter this one-time code (expires in 15 minutes)\n\n$_code\n', _code),
    ('Authorization: Bearer $_opaque', _opaque),
    (
      r'{\"access_token\":\"'
          '$_opaque'
          r'\"}',
      _opaque,
    ),
    (
      r'https:\/\/auth.openai.com\/authorize?state='
          '$_opaque',
      _opaque,
    ),
    ('https://auth.openai.com/authorize?client_id=public', 'auth.openai'),
    ('https://claude.ai/login', 'claude.ai/login'),
    ('https://claude.ai/oauth/authorize', 'claude.ai/oauth'),
    ('https://claude.com/oauth/authorize', 'claude.com/oauth'),
    ('https://platform.claude.com/oauth/code/callback', 'platform.claude'),
    ('https://login.example/callback?code=$_opaque', _opaque),
    ('https://login.example/authorize?state=$_opaque', _opaque),
    ('https://login.example/device?user_code=$_code', _code),
    ..._fragmentArtifacts,
  ];

  for (final (artifact, credential) in artifacts) {
    test('unknown authentication artifact is masked: $artifact', () {
      final safe = _redactor().text('before $artifact after');
      expect(safe, isNot(contains(credential)));
      expect(safe, contains('[REDACTED]'));
      expect(safe, contains('before '));
      expect(safe, contains(' after'));
    });

    test(
      'authentication artifact is safe at every chunk boundary: $artifact',
      () {
        final source = 'before $artifact after';
        for (var split = 1; split < source.length; split++) {
          final buffer = _redactor().textBuffer();
          final safe = [
            ...buffer.add(source.substring(0, split), id: 'first'),
            ...buffer.add(source.substring(split), id: 'second'),
            ...buffer.finish(),
          ].map((part) => part.text).join();
          expect(safe, isNot(contains(credential)), reason: 'split at $split');
          expect(safe, contains('before '), reason: 'split at $split');
          expect(safe, contains(' after'), reason: 'split at $split');
        }
      },
    );
  }

  test('authentication filtering is confined to subscription launches', () {
    const ordinary = 'access_token=$_opaque https://claude.ai/login';
    expect(AcpSecretRedactor(const []).text(ordinary), ordinary);
    expect(AcpSecretRedactor(const []).value({'user_code': _code}), {
      'user_code': _code,
    });
  });

  test(
    'long spacing after a credential label does not release the next value',
    () {
      for (final source in [
        'access_token${' ' * 8192}: "$_opaque" done',
        'access_token:${' ' * 8192}"$_opaque" done',
      ]) {
        final buffer = _redactor().textBuffer();
        final output = StringBuffer();
        for (var at = 0; at < source.length; at += 127) {
          final end = at + 127 < source.length ? at + 127 : source.length;
          output.writeAll(
            buffer
                .add(source.substring(at, end), id: 'text')
                .map((p) => p.text),
          );
        }
        output.writeAll(buffer.finish().map((p) => p.text));
        expect(output.toString().contains(_opaque), isFalse);
        expect(output.toString().endsWith(' done'), isTrue);
      }
    },
  );

  test(
    'subscription credential masking runs before short launch-key masking',
    () {
      final redactor = AcpSecretRedactor(['s'], protectAuthentication: true);
      final safe = redactor.text('access_token=$_opaque');
      expect(safe, isNot(contains(_opaque)));
      expect(safe, isNot(contains('s')));
    },
  );

  test('structured credentials are masked without masking control values', () {
    final raw = {
      'update': {
        'sessionUpdate': 'tool_call',
        'toolCallId': _jwt,
        'kind': 'execute',
        'status': 'pending',
        'title': 'Authentication failed: $_access',
        'rawInput': {
          'access_token': _opaque,
          'nested': [
            {'refreshToken': _opaque, 'user_code': _code},
          ],
          'code': 'normal-program-code',
          'command': 'echo normal',
        },
      },
      'sessionId': _access,
      'authMethods': [
        {'id': _refresh},
      ],
    };
    final safe = _redactor().protocol(raw) as Map;
    final update = safe['update'] as Map;
    final input = update['rawInput'] as Map;
    expect(safe['sessionId'], _access);
    expect(update['toolCallId'], _jwt);
    expect(update['sessionUpdate'], 'tool_call');
    expect(update['kind'], 'execute');
    expect(update['status'], 'pending');
    expect((safe['authMethods'] as List).single['id'], _refresh);
    expect((safe['authMethods'] as List).single['name'], '[REDACTED]');
    expect(update['title'], isNot(contains('access-sentinel')));
    expect(input.toString(), isNot(contains(_opaque)));
    expect(input.toString(), isNot(contains(_code)));
    expect(input['code'], 'normal-program-code');
    expect(input['command'], 'echo normal');
    expect(
      ((raw['update'] as Map)['rawInput'] as Map)['access_token'],
      _opaque,
    );
  });

  test('error messages, nested data and details mask unknown credentials', () {
    final safe = _redactor().error(
      const AcpError(
        AcpError.authRequired,
        'Login failed $_access',
        {
          'access_token': _opaque,
          'nested': {'id_token': _jwt, 'device_code': _code},
        },
        null,
        'Open https://auth.openai.com/authorize?state=$_opaque',
      ),
      stderr: 'refresh_token=$_opaque',
    );
    for (final surfaced in [
      safe.message,
      safe.data.toString(),
      safe.details!,
    ]) {
      expect(surfaced, isNot(contains('access-sentinel')));
      expect(surfaced, isNot(contains(_opaque)));
      expect(surfaced, isNot(contains('signature-sentinel')));
      expect(surfaced, isNot(contains(_code)));
    }
    expect(safe.code, AcpError.authRequired);
    expect(safe.failureKind?.name, 'authRequired');
  });

  test('UTF-8 stderr fragments never retain authentication suffixes', () {
    final stderr = _redactor().stderrBuffer();
    final output = StringBuffer();
    for (final byte in utf8.encode(
      'Login required. $_access $_jwt user_code=$_code\n',
    )) {
      output.write(stderr.addBytes([byte]));
    }
    expect(output.toString(), isNot(contains('access-sentinel')));
    expect(output.toString(), isNot(contains('signature-sentinel')));
    expect(output.toString(), isNot(contains(_code)));
    expect(stderr.failureKind?.name, 'authRequired');
  });

  test(
    'fragment authentication URLs stay out of diagnostics and persisted tools',
    () {
      for (final (artifact, credential) in _fragmentArtifacts) {
        final redactor = _redactor();
        final error = redactor.error(
          AcpError(
            AcpError.internalError,
            'Failed: $artifact',
            {'url': artifact},
            null,
            'Details: $artifact',
          ),
          stderr: 'Native output: $artifact',
        );
        final diagnostic = '${error.message} ${error.data} ${error.details}';
        expect(diagnostic, isNot(contains(credential)), reason: artifact);
        expect(diagnostic, contains('[REDACTED]'));

        final input = {'url': artifact};
        final translator = AcpTurnTranslator(redactor: redactor);
        final chunks = <StreamChunk>[];
        for (final update in [
          {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'fragment-tool',
            'title': 'Fetch $artifact',
            'kind': 'fetch',
            'status': 'pending',
            'rawInput': input,
          },
          {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'fragment-tool',
            'status': 'completed',
            'rawOutput': {'url': artifact},
          },
        ]) {
          final params = redactor.protocol({'update': update}) as Map;
          chunks.addAll(
            translator.translate(
              Map<String, Object?>.from(params['update'] as Map),
            ),
          );
        }
        chunks.addAll(translator.finish('end_turn'));
        final part = StreamChunkHandler.collect(
          chunks,
        ).parts.whereType<ToolCallPart>().single;
        expect(part.payloadJson, isNot(contains(credential)), reason: artifact);
        expect(part.payloadJson, contains('[REDACTED]'));
        expect(input['url'], artifact);
      }
    },
  );

  test(
    'unfinished authentication artifacts remain private when a turn ends',
    () {
      for (final artifact in [
        'sk-ant-oat01-incomplete-secret',
        'eyJhbGciOiJSUzI1NiJ9.partial-sensitive-payload',
        'access_token="$_opaque',
        'https://auth.openai.com/authorize?state=$_opaque',
      ]) {
        final buffer = _redactor().textBuffer();
        final safe = [
          ...buffer.add(artifact, id: 'text'),
          ...buffer.finish(),
        ].map((part) => part.text).join();
        expect(safe, contains('[REDACTED]'));
        expect(safe, isNot(contains('incomplete-secret')));
        expect(safe, isNot(contains('sensitive-payload')));
        expect(safe, isNot(contains(_opaque)));
        expect(buffer.pendingIds, isEmpty);
      }
    },
  );

  test(
    'overlong authentication candidates stop retaining their private spans',
    () {
      final buffer = _redactor().textBuffer();
      final output = StringBuffer();
      output.writeAll(
        buffer
            .add('https://login.example/?state=', id: 'text')
            .map((p) => p.text),
      );
      for (var i = 0; i < 100; i++) {
        output.writeAll(
          buffer.add('sensitive' * 512, id: 'text').map((p) => p.text),
        );
        if (i > 2) expect(buffer.pendingIds, isEmpty);
      }
      output.writeAll(buffer.add(' done', id: 'text').map((p) => p.text));
      output.writeAll(buffer.finish().map((p) => p.text));
      expect(output.toString().contains('[REDACTED]'), isTrue);
      expect(output.toString().contains('sensitive'), isFalse);
      expect(output.toString().endsWith(' done'), isTrue);
    },
  );

  test(
    'ordinary documentation URLs and code survive authentication filtering',
    () {
      const ordinary =
          'See https://docs.example.com/reference?language=ru#usage. '
          'Run code 1401 and refresh tokens for the UI. '
          'The filename is access_token.dart and a user code example follows.';
      final buffer = _redactor().textBuffer();
      final output = [
        for (final character in ordinary.split(''))
          ...buffer.add(character, id: 'text'),
        ...buffer.finish(),
      ].map((part) => part.text).join();
      expect(output, ordinary);
      expect(_redactor().text(ordinary), ordinary);
    },
  );

  test('chat fragments remain safe across intervening tool cards', () {
    final translator = AcpTurnTranslator(redactor: _redactor());
    final chunks = <StreamChunk>[];
    for (final (index, character) in _access.split('').indexed) {
      chunks.addAll(
        translator.translate({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': character},
        }),
      );
      if (index == 6 || index == 18) {
        chunks.addAll(
          translator.translate({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tool-$index',
            'kind': 'execute',
            'title': 'Safe command',
          }),
        );
      }
    }
    chunks.addAll(translator.finish('end_turn'));
    final text = chunks
        .whereType<TextDelta>()
        .map((chunk) => chunk.text)
        .join();
    expect(text, '[REDACTED]');
    expect(translator.text.toString(), text);
  });

  test(
    'subscription wire tool IDs become distinct stable safe persisted card IDs',
    () {
      final wireIds = [
        _access,
        _refresh,
        _jwt,
        '$_access${String.fromCharCode(0xd800)}',
        '$_access${String.fromCharCode(0xd801)}',
      ];
      final redactor = _redactor();
      final translator = AcpTurnTranslator(redactor: redactor);
      final chunks = <StreamChunk>[];
      for (var i = 0; i < wireIds.length; i++) {
        final update = {
          'sessionUpdate': 'tool_call',
          'toolCallId': wireIds[i],
          'kind': 'execute',
          'status': 'pending',
          'title': 'Card $i',
          'rawInput': {'command': 'echo $i'},
        };
        final safe = redactor.protocol({'update': update}) as Map;
        expect((safe['update'] as Map)['toolCallId'], wireIds[i]);
        chunks.addAll(
          translator.translate(
            Map<String, Object?>.from(safe['update'] as Map),
          ),
        );
      }
      for (var i = wireIds.length - 1; i >= 0; i--) {
        chunks.addAll(
          translator.translate({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': wireIds[i],
            'status': 'completed',
            'rawOutput': 'Result $i',
          }),
        );
      }
      chunks.addAll(translator.finish('end_turn'));
      final starts = chunks.whereType<ServerToolStart>().toList();
      final ends = chunks.whereType<ServerToolEnd>().toList();
      expect(starts.length, wireIds.length);
      expect(starts.map((chunk) => chunk.id).toSet().length, wireIds.length);
      expect(ends.length, wireIds.length);
      for (final end in ends) {
        final command = (end.input as Map)['command'];
        expect(
          end.id,
          starts
              .singleWhere(
                (start) => (start.input as Map)['command'] == command,
              )
              .id,
        );
      }
      final persisted = StreamChunkHandler.collect(
        chunks,
      ).parts.whereType<ToolCallPart>().toList();
      expect(persisted.length, wireIds.length);
      final surfaced = [
        ...starts.map((chunk) => chunk.id),
        ...ends.map((chunk) => chunk.id),
        ...persisted.map((part) => part.payloadJson),
      ].join('\n');
      for (final secret in [
        ...wireIds,
        'access-sentinel',
        'refresh-sentinel',
        'signature-sentinel',
      ]) {
        expect(surfaced, isNot(contains(secret)));
      }
      final later = AcpTurnTranslator(redactor: _redactor());
      for (var i = 0; i < wireIds.length; i++) {
        final start = later
            .translate({
              'sessionUpdate': 'tool_call',
              'toolCallId': wireIds[i],
              'kind': 'execute',
              'title': 'Later $i',
            })
            .whereType<ServerToolStart>()
            .single;
        expect(start.id, starts[i].id);
      }
    },
  );

  test('provider launches retain their existing raw local-card mapping', () {
    for (final redactor in [null, AcpSecretRedactor(const [])]) {
      final translator = AcpTurnTranslator(redactor: redactor);
      final start = translator
          .translate({
            'sessionUpdate': 'tool_call',
            'toolCallId': _access,
            'kind': 'execute',
            'title': 'Safe title',
          })
          .whereType<ServerToolStart>()
          .single;
      expect(start.id, 'acp-tool-$_access');
    }
  });

  test(
    'safe subscription card IDs preserve MCP approvals, cancellation and raw arguments',
    () async {
      final redactor = _redactor();
      final translator = AcpTurnTranslator(redactor: redactor);
      const input = {'action': 'list', 'query': _jwt};
      final update = {
        'sessionUpdate': 'tool_call',
        'toolCallId': _access,
        'title': 'moru_mini_apps',
        'kind': 'other',
        'status': 'pending',
        'rawInput': input,
      };
      final safe = redactor.protocol({'update': update}) as Map;
      final start = translator
          .translate(Map<String, Object?>.from(safe['update'] as Map))
          .whereType<ServerToolStart>()
          .single;
      expect(start.input.toString(), isNot(contains(_jwt)));
      final entered = Completer<String>();
      final release = Completer<void>();
      final cancelled = <String>[];
      final tools = AcpMcpTools(
        key: 'test-subscription',
        definitions: () => [
          {
            'name': 'mini_apps',
            'inputSchema': {'type': 'object'},
          },
        ],
        execute: (name, arguments, {required toolCallId}) async {
          expect(name, 'mini_apps');
          expect(arguments, input);
          entered.complete(toolCallId);
          await release.future;
          return {'content': []};
        },
        cancelApproval: cancelled.add,
      );
      final binding = await AcpMcpBinding.start(tools, redactor: redactor);
      addTearDown(binding.close);
      binding.beginTurn(tools);
      binding.observe(update);
      final request = AcpPermissionRequest(
        sessionId: 's1',
        toolCallId: start.id,
        title: 'Safe permission',
        kind: 'other',
        input: input,
        options: const [
          AcpPermissionOption(id: _refresh, name: 'Allow', kind: 'allow_once'),
        ],
      );
      expect(binding.permissionChoice(request), _refresh);
      final result = binding.callTool('mini_apps', input);
      final executionId = await entered.future.timeout(
        const Duration(seconds: 2),
      );
      expect(executionId, isNot(contains(_access)));
      expect(executionId, start.id);
      binding.endTurn();
      release.complete();
      expect((await result)['isError'], isTrue);
      expect(cancelled, [start.id]);
    },
  );

  test(
    'protocol filtering preserves authentication evidence for the streaming sink',
    () {
      for (final (artifact, credential) in artifacts) {
        final source = 'before $artifact after';
        for (var split = 1; split < source.length; split++) {
          final redactor = _redactor();
          final translator = AcpTurnTranslator(redactor: redactor);
          final chunks = <StreamChunk>[];
          for (final fragment in [
            source.substring(0, split),
            source.substring(split),
          ]) {
            final params =
                redactor.protocol({
                      'sessionId': 's1',
                      'update': {
                        'sessionUpdate': 'agent_message_chunk',
                        'content': {'type': 'text', 'text': fragment},
                      },
                    })
                    as Map;
            chunks.addAll(
              translator.translate(
                Map<String, Object?>.from(params['update'] as Map),
              ),
            );
          }
          chunks.addAll(translator.finish('end_turn'));
          final output = chunks
              .whereType<TextDelta>()
              .map((chunk) => chunk.text)
              .join();
          expect(
            output,
            isNot(contains(credential)),
            reason: '$artifact split at $split',
          );
          expect(output, startsWith('before '));
          expect(output, endsWith(' after'));
        }
      }
    },
  );
}
