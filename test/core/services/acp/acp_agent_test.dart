import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/acp/acp_turn_translator.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk_handler.dart';
import 'package:Kelivo/core/services/workspace/task_plan.dart';

/// An agent process played by the test: what Moru writes lands in [sent],
/// and the test answers through [emit].
class _FakeAgentChannel extends AcpChannel {
  final _incoming = StreamController<dynamic>();
  final _closed = Completer<void>();
  final sent = <Map<String, Object?>>[];
  final _sentEvents = StreamController<Map<String, Object?>>.broadcast();
  String stderr = '';
  Object? cancelError;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> send(Map<String, Object?> message) async {
    if (_closed.isCompleted) throw StateError('closed');
    if (message['method'] == 'session/cancel' && cancelError != null) {
      throw cancelError!;
    }
    // Through JSON, as the real pipe would.
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(message)) as Map,
    );
    sent.add(copy);
    _sentEvents.add(copy);
  }

  @override
  void close() {
    if (!_closed.isCompleted) _closed.complete();
    unawaited(_incoming.close());
  }

  @override
  String describeError(Object error) =>
      stderr.isEmpty ? 'agent exited' : 'agent exited\n\n$stderr';

  void emit(Map<String, Object?> message) => _incoming.add(message);

  /// The next message Moru sends with [method].
  Future<Map<String, Object?>> next(String method) async {
    for (final message in sent) {
      if (message['method'] == method && !_seen.contains(message)) {
        _seen.add(message);
        return message;
      }
    }
    final message = await _sentEvents.stream.firstWhere(
      (message) => message['method'] == method,
    );
    _seen.add(message);
    return message;
  }

  final _seen = <Map<String, Object?>>{};

  /// Moru's answer to the agent's request [id], sent already or soon.
  Future<Map<String, Object?>> answerTo(Object id) async {
    for (final message in sent) {
      if (message['id'] == id && message['method'] == null) return message;
    }
    return _sentEvents.stream.firstWhere(
      (message) => message['id'] == id && message['method'] == null,
    );
  }

  void reply(Map<String, Object?> request, Object? result) =>
      emit({'jsonrpc': '2.0', 'id': request['id'], 'result': result});

  void update(String sessionId, Map<String, Object?> update) => emit({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': sessionId, 'update': update},
  });

  void crash() {
    if (!_closed.isCompleted) _closed.complete();
    unawaited(_incoming.close());
  }
}

Future<(AcpAgent, _FakeAgentChannel)> _started({
  Map<String, Object?> initialize = const {},
  AcpSecretRedactor? redactor,
}) async {
  final channel = _FakeAgentChannel();
  final agent = AcpAgent.start(
    channel,
    clientVersion: '0.1.47',
    redactor: redactor,
  );
  final request = await channel.next('initialize');
  channel.reply(request, {
    'protocolVersion': 1,
    'agentCapabilities': {
      'loadSession': true,
      'promptCapabilities': {'image': true},
    },
    'agentInfo': {'name': 'fake-agent', 'title': 'Fake', 'version': '1.0'},
    'authMethods': [
      {'id': 'api-key', 'name': 'API key'},
    ],
    ...initialize,
  });
  return (await agent, channel);
}

List<Map<String, dynamic>> _tools(List<MessagePart> parts) => [
  for (final part in parts.whereType<ToolCallPart>())
    Map<String, dynamic>.from(jsonDecode(part.payloadJson) as Map),
];

void main() {
  const secret = 'fake-api-key-sentinel';
  test(
    'subscription permissions use the safe card ID while wire choices and correlation stay raw',
    () async {
      const wireId = 'sk-ant-oat01-malicious-wire-id-sentinel';
      const choiceId = 'sk-ant-ort01-private-choice-sentinel';
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor(const [], protectAuthentication: true),
      );
      addTearDown(agent.close);
      final correlations = <String>[];
      final asked = Completer<AcpPermissionRequest>();
      agent.onToolCorrelation = (_, correlation) =>
          correlations.add(correlation.id);
      agent.onPermission = (request) async {
        asked.complete(request);
        return request.options.single.id;
      };
      final done = agent.prompt('s1', const []).toList();
      final prompt = await channel.next('session/prompt');
      channel.update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': wireId,
        'title': 'Safe command',
        'kind': 'execute',
        'status': 'pending',
        'rawInput': {'command': 'echo safe'},
      });
      channel.emit({
        'jsonrpc': '2.0',
        'id': 'permission',
        'method': 'session/request_permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {
            'toolCallId': wireId,
            'title': 'Safe command',
            'kind': 'execute',
          },
          'options': [
            {'optionId': choiceId, 'name': 'Allow', 'kind': 'allow_once'},
          ],
        },
      });
      final permission = await asked.future;
      final answer = await channel.answerTo('permission');
      channel.update('s1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': wireId,
        'status': 'completed',
        'rawOutput': 'Done',
      });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final chunks = await done;
      final start = chunks.whereType<ServerToolStart>().single;
      expect(permission.toolCallId, isNot(contains(wireId)));
      expect(permission.toolCallId, start.id);
      expect(chunks.whereType<ServerToolEnd>().single.id, start.id);
      expect(
        ((answer['result'] as Map)['outcome'] as Map)['optionId'],
        choiceId,
      );
      expect(correlations, isNotEmpty);
      expect(correlations.every((id) => id == wireId), isTrue);
      for (final part in StreamChunkHandler.collect(
        chunks,
      ).parts.whereType<ToolCallPart>()) {
        expect(part.payloadJson, isNot(contains(wireId)));
        expect(part.payloadJson, isNot(contains(choiceId)));
      }
    },
  );
  for (final kind in ['agent_message_chunk', 'agent_thought_chunk']) {
    for (final ending in ['complete', 'cancel', 'failure', 'close']) {
      test(
        '$kind split secrets and legitimate tails are safe on $ending',
        () async {
          final (agent, channel) = await _started(
            redactor: AcpSecretRedactor([secret]),
          );
          addTearDown(agent.close);
          final chunks = <StreamChunk>[];
          final errors = <Object>[];
          final done = Completer<void>();
          agent
              .prompt('s1', [])
              .listen(chunks.add, onError: errors.add, onDone: done.complete);
          final request = await channel.next('session/prompt');
          for (final text in [
            'before fake-api-',
            'key-',
            'sentinel after fake-',
          ]) {
            channel.update('s1', {
              'sessionUpdate': kind,
              'content': {'type': 'text', 'text': text},
            });
          }
          // Observe delivery of all preceding updates without timing assumptions.
          final seen = Completer<String?>();
          agent.onPermission = (_) {
            seen.complete(null);
            return seen.future;
          };
          channel.emit({
            'method': 'session/request_permission',
            'id': 'sync',
            'params': {'sessionId': 's1', 'options': []},
          });
          await seen.future;
          final streamed = chunks
              .map(
                (chunk) => switch (chunk) {
                  TextDelta(:final text) || ReasoningDelta(:final text) => text,
                  _ => '',
                },
              )
              .join();
          expect(streamed, isNot(contains(secret)));
          if (ending == 'cancel') await agent.cancel('s1');
          if (ending == 'close') {
            agent.close();
          } else if (ending == 'failure') {
            channel.emit({
              'id': request['id'],
              'error': {'code': -32042, 'message': 'safe error'},
            });
          } else {
            channel.reply(request, {'stopReason': 'end_turn'});
          }
          await done.future.timeout(const Duration(seconds: 2));
          final all = chunks
              .map(
                (chunk) => switch (chunk) {
                  TextDelta(:final text) || ReasoningDelta(:final text) => text,
                  _ => '',
                },
              )
              .join();
          expect(all, 'before [REDACTED] after fake-');
          final stored = StreamChunkHandler.collect(chunks).parts;
          final visible = stored
              .map(
                (part) => switch (part) {
                  TextPart(:final text) || ReasoningPart(:final text) => text,
                  _ => '',
                },
              )
              .join();
          expect(visible, isNot(contains(secret)));
          expect(visible, all);
        },
      );
    }
  }

  test(
    'large ordinary chunks preserve text around an incremental secret',
    () async {
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([secret]),
      );
      addTearDown(agent.close);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      final ordinary = List.filled(128 * 1024, 'x').join();
      for (final text in ['${ordinary}fake-api-', 'key-sentinel safe']) {
        channel.update('s1', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': text},
        });
      }
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final chunks = await done;
      expect(
        chunks.whereType<TextDelta>().map((chunk) => chunk.text).join(),
        '$ordinary[REDACTED] safe',
      );
    },
  );

  test(
    'streaming replacements cannot assemble a different secret across part spans',
    () {
      final translator = AcpTurnTranslator(
        redactor: AcpSecretRedactor(['abc', 'def', 'R']),
      );
      final chunks = [
        ...translator.translate({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'ad'},
        }),
        ...translator.translate({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'a',
          'title': 'Safe title',
          'kind': 'execute',
        }),
        ...translator.translate({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'efbc'},
        }),
        ...translator.finish('end_turn'),
      ];
      final stored = StreamChunkHandler.collect(
        chunks,
      ).parts.whereType<TextPart>().map((part) => part.text).join();
      expect(stored, isNot(contains('abc')));
      expect(stored, isNot(contains('def')));
      expect(stored, isNot(contains('R')));
      expect(translator.text.toString(), stored);
    },
  );

  test(
    'replacement marker boundaries cannot manufacture a configured API key',
    () {
      const key = 'secret[REDACTED]token';
      final redactor = AcpSecretRedactor([key, 'X']);
      final diagnostic = redactor.text('secretXtoken');
      expect(diagnostic, isNot(contains(key)));
      expect(diagnostic, isNot(contains('X')));

      final translator = AcpTurnTranslator(redactor: redactor);
      final chunks = [
        ...translator.translate({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'secret'},
        }),
        ...translator.translate({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'a',
          'title': 'Safe title',
          'kind': 'execute',
        }),
        ...translator.translate({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Xtoken'},
        }),
        ...translator.finish('end_turn'),
      ];
      final stored = StreamChunkHandler.collect(
        chunks,
      ).parts.whereType<TextPart>().map((part) => part.text).join();
      expect(stored, diagnostic);
      expect(stored, isNot(contains(key)));
      expect(translator.text.toString(), stored);
    },
  );

  test(
    'removing a short header cannot assemble another launch secret in an error',
    () async {
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([secret, 'E']),
      );
      addTearDown(agent.close);
      channel.cancelError = const AcpError(-32042, 'fake-api-Ekey-sentinel');
      await expectLater(
        agent.cancel('s1'),
        throwsA(
          isA<AcpError>().having(
            (error) => error.message,
            'no assembled secret',
            isNot(contains(secret)),
          ),
        ),
      );
    },
  );

  test('cancel send exceptions are redacted including error data', () async {
    final (agent, channel) = await _started(
      redactor: AcpSecretRedactor([secret]),
    );
    addTearDown(agent.close);
    channel.cancelError = const AcpError(-32042, 'cancel $secret', {
      'detail': secret,
    });
    await expectLater(
      agent.cancel('s1'),
      throwsA(
        isA<AcpError>()
            .having((e) => e.code, 'code', -32042)
            .having((e) => e.message, 'safe message', isNot(contains(secret)))
            .having(
              (e) => e.data.toString(),
              'safe data',
              isNot(contains(secret)),
            ),
      ),
    );
    expect(agent.failure!.message, isNot(contains(secret)));
  });

  test(
    'routing IDs stay raw while synthesized auth/mode/option labels are redacted',
    () async {
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([secret]),
        initialize: {
          'authMethods': [
            {'id': secret},
          ],
        },
      );
      addTearDown(agent.close);
      expect(agent.info.authMethods.single.id, secret);
      expect(agent.info.authMethods.single.name, isNot(contains(secret)));
      final opening = agent.newSession(cwd: '/workspace');
      final newRequest = await channel.next('session/new');
      channel.reply(newRequest, {
        'sessionId': 's1',
        'modes': {
          'availableModes': [
            {'id': secret},
          ],
          'currentModeId': secret,
        },
      });
      final session = await opening;
      expect(session.modes.single.id, secret);
      expect(session.modes.single.name, isNot(contains(secret)));
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      final permission = Completer<AcpPermissionRequest>();
      agent.onPermission = (request) async {
        permission.complete(request);
        return request.options.single.id;
      };
      channel.emit({
        'method': 'session/request_permission',
        'id': 'permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {'title': '', 'kind': secret},
          'options': [
            {'optionId': secret, 'kind': 'allow_once'},
          ],
        },
      });
      final asked = await permission.future;
      expect(asked.kind, isNot(contains(secret)));
      expect(asked.options.single.id, secret);
      expect(asked.options.single.name, isNot(contains(secret)));
      final reply = await channel.answerTo('permission');
      expect(((reply['result'] as Map)['outcome'] as Map)['optionId'], secret);
      channel.reply(prompt, {'stopReason': 'end_turn'});
      await done;
    },
  );

  test(
    'invalid protocol enum and MIME strings never become visible secrets',
    () async {
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([secret]),
      );
      addTearDown(agent.close);
      final updates = <Map<String, Object?>>[];
      agent.onToolUpdate = (_, update) => updates.add(update);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      channel.update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 't1',
        'kind': secret,
        'status': secret,
        'title': 'Safe title',
      });
      channel.update('s1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'image', 'data': 'QQ==', 'mimeType': secret},
      });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final chunks = await done;
      expect(updates.toString(), isNot(contains(secret)));
      expect(
        chunks.whereType<ImageStart>().single.mimeType,
        isNot(contains(secret)),
      );
      expect(
        chunks.whereType<ImageSnapshot>().single.data,
        isNot(contains(secret)),
      );
    },
  );

  test(
    'growing prefixes preserve every original part across multiple card transitions',
    () {
      final translator = AcpTurnTranslator(
        redactor: AcpSecretRedactor(['secret-token']),
      );
      final chunks = <StreamChunk>[];
      for (final update in <Map<String, Object?>>[
        {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'sec'},
        },
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'a',
          'kind': 'execute',
          'title': 'Card A',
        },
        {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 're'},
        },
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'b',
          'kind': 'execute',
          'title': 'Card B',
        },
        {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Done'},
        },
      ]) {
        chunks.addAll(translator.translate(update));
      }
      chunks.addAll(translator.finish('end_turn'));
      final parts = StreamChunkHandler.collect(chunks).parts;
      expect(parts.map((part) => part.runtimeType), [
        TextPart,
        ToolCallPart,
        TextPart,
        ToolCallPart,
        TextPart,
      ]);
      expect(parts.whereType<TextPart>().map((part) => part.text), [
        'sec',
        're',
        'Done',
      ]);
      expect(translator.text.toString(), 'secreDone');
    },
  );

  test(
    'resource text and synthesized resource links use the streaming redactor',
    () async {
      const linkSecret = 'name](uri)';
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([secret, linkSecret]),
      );
      addTearDown(agent.close);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      for (final text in ['fake-api-', 'key-sentinel']) {
        channel.update('s1', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'resource',
            'resource': {'text': text},
          },
        });
      }
      channel.update('s1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'resource_link', 'title': 'name', 'uri': 'uri'},
      });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final rendered = (await done)
          .whereType<TextDelta>()
          .map((chunk) => chunk.text)
          .join();
      expect(rendered, isNot(contains(secret)));
      expect(rendered, isNot(contains(linkSecret)));
      expect(rendered, contains('[REDACTED]'));
    },
  );

  test(
    'ordinary buffered suffixes retain their original position across tool and thought transitions',
    () async {
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor(['secret-token']),
      );
      addTearDown(agent.close);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      channel
        ..update('s1', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Running tests'},
        })
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'kind': 'execute',
          'title': 'Run tests',
        })
        ..update('s1', {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'Thoughts'},
        })
        ..update('s1', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Done'},
        });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final parts = StreamChunkHandler.collect(await done).parts;
      expect(parts.map((part) => part.runtimeType), [
        TextPart,
        ToolCallPart,
        ReasoningPart,
        TextPart,
      ]);
      expect(parts.whereType<TextPart>().map((part) => part.text), [
        'Running tests',
        'Done',
      ]);
      expect(parts.whereType<ReasoningPart>().single.text, 'Thoughts');
    },
  );

  test(
    'secrets split across text parts remain redacted around tool transitions',
    () async {
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([secret]),
      );
      addTearDown(agent.close);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      channel
        ..update('s1', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'fake-api-'},
        })
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'kind': 'execute',
          'title': 'Safe title',
        })
        ..update('s1', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'key-sentinel after'},
        });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final parts = StreamChunkHandler.collect(await done).parts;
      expect(parts.map((part) => part.runtimeType), [
        TextPart,
        ToolCallPart,
        TextPart,
      ]);
      expect(parts.whereType<TextPart>().map((part) => part.text), [
        '[REDACTED]',
        ' after',
      ]);
    },
  );

  test(
    'assembled command and diff metadata never reproduce a header secret',
    () async {
      const commandSecret = 'Bearer fake-header-sentinel';
      const diffSecret = '--- a/path\n+++ b/path';
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([commandSecret, diffSecret]),
      );
      addTearDown(agent.close);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      channel
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'command',
          'kind': 'execute',
          'title': 'Safe title',
          'status': 'completed',
          'rawInput': {
            'command': ['Bearer', 'fake-header-sentinel'],
          },
        })
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'diff',
          'kind': 'edit',
          'title': 'Safe title',
          'status': 'completed',
          'content': [
            {
              'type': 'diff',
              'path': 'path',
              'oldText': 'old',
              'newText': 'new',
            },
          ],
        });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final chunks = await done;
      for (final chunk in chunks.whereType<ServerToolStart>()) {
        expect(chunk.input.toString(), isNot(contains(commandSecret)));
        expect(chunk.input.toString(), isNot(contains(diffSecret)));
      }
      for (final chunk in chunks.whereType<ServerToolEnd>()) {
        expect(chunk.input.toString(), isNot(contains(commandSecret)));
        expect(chunk.metadata.toString(), isNot(contains(commandSecret)));
        expect(chunk.metadata.toString(), isNot(contains(diffSecret)));
        expect(chunk.output.toString(), isNot(contains(diffSecret)));
      }
      final cards = StreamChunkHandler.collect(
        chunks,
      ).parts.whereType<ToolCallPart>();
      for (final card in cards) {
        expect(card.payloadJson, isNot(contains(commandSecret)));
      }
    },
  );

  test(
    'joined tool content is redacted after content blocks are assembled',
    () async {
      const joinedSecret = 'fake-api-\nkey-sentinel';
      final (agent, channel) = await _started(
        redactor: AcpSecretRedactor([joinedSecret]),
      );
      addTearDown(agent.close);
      final done = agent.prompt('s1', []).toList();
      final prompt = await channel.next('session/prompt');
      channel.update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 't1',
        'kind': 'execute',
        'title': 'Safe title',
        'status': 'completed',
        'content': [
          for (final text in ['fake-api-', 'key-sentinel'])
            {
              'type': 'content',
              'content': {'type': 'text', 'text': text},
            },
        ],
      });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      final chunks = await done;
      expect(
        chunks.whereType<ServerToolEnd>().single.output,
        isNot(contains(joinedSecret)),
      );
      expect(
        chunks.whereType<ServerToolEnd>().single.metadata.toString(),
        isNot(contains(joinedSecret)),
      );
    },
  );

  test('initialize announces Moru and reads what the agent can do', () async {
    final (agent, channel) = await _started();
    final init = channel.sent.first;
    final params = init['params'] as Map;
    expect(params['protocolVersion'], 1);
    expect((params['clientInfo'] as Map)['name'], 'moru');
    // Agents use their own tools in the Linux environment.
    expect((params['clientCapabilities'] as Map)['terminal'], false);

    expect(agent.info.name, 'Fake');
    expect(agent.info.version, '1.0');
    expect(agent.info.loadSession, isTrue);
    expect(agent.info.imagePrompts, isTrue);
    expect(agent.info.authMethods.single.id, 'api-key');
    agent.close();
  });

  test('a new session sends the folder and reads the modes', () async {
    final (agent, channel) = await _started();
    final pending = agent.newSession(cwd: '/root/project');
    final request = await channel.next('session/new');
    expect((request['params'] as Map)['cwd'], '/root/project');
    expect((request['params'] as Map)['mcpServers'], isEmpty);
    channel.reply(request, {
      'sessionId': 's1',
      'modes': {
        'currentModeId': 'code',
        'availableModes': [
          {'id': 'ask', 'name': 'Ask'},
          {'id': 'code', 'name': 'Code'},
        ],
      },
    });
    final session = await pending;
    expect(session.id, 's1');
    expect(session.currentModeId, 'code');
    expect(session.modes.map((m) => m.name), ['Ask', 'Code']);
    agent.close();
  });

  test('an answer streams as thoughts, text, a command card, a plan and '
      'usage, with the permission asked in between', () async {
    final (agent, channel) = await _started();
    final plans = <TaskPlan>[];
    final asked = <AcpPermissionRequest>[];
    agent.onPermission = (request) async {
      asked.add(request);
      return request.options.firstWhere((o) => o.kind == 'allow_once').id;
    };
    final chunks = <StreamChunk>[];
    final done = agent
        .prompt('s1', [
          {'type': 'text', 'text': 'run the tests'},
        ], onPlan: plans.add)
        .listen(chunks.add)
        .asFuture<void>();

    final prompt = await channel.next('session/prompt');
    expect((prompt['params'] as Map)['prompt'], [
      {'type': 'text', 'text': 'run the tests'},
    ]);
    channel
      ..update('s1', {
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'Thinking'},
      })
      ..update('s1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Running '},
      })
      ..update('s1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'them.'},
      })
      ..update('s1', {
        'sessionUpdate': 'plan',
        'entries': [
          {'content': 'Run tests', 'status': 'in_progress'},
          {'content': 'Fix failures', 'status': 'pending'},
        ],
      })
      ..update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 't1',
        'title': 'flutter test',
        'kind': 'execute',
        'status': 'pending',
        'rawInput': {'command': 'flutter test'},
      })
      ..emit({
        'jsonrpc': '2.0',
        'id': 'perm-1',
        'method': 'session/request_permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {'toolCallId': 't1', 'title': 'flutter test'},
          'options': [
            {'optionId': 'yes', 'name': 'Allow', 'kind': 'allow_once'},
            {'optionId': 'no', 'name': 'Reject', 'kind': 'reject_once'},
          ],
        },
      });
    // The answer to the permission request.
    final answer = await channel.answerTo('perm-1');
    expect(answer['result'], {
      'outcome': {'outcome': 'selected', 'optionId': 'yes'},
    });
    expect(asked.single.title, 'flutter test');
    expect(asked.single.options.map((o) => o.allows), [true, false]);

    channel
      ..update('s1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 't1',
        'status': 'completed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'All tests passed!'},
          },
        ],
      })
      ..update('s1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Done.'},
      })
      ..reply(prompt, {
        'stopReason': 'end_turn',
        'usage': {'inputTokens': 100, 'outputTokens': 20},
      });
    await done;

    expect(chunks.last, isA<Finish>());
    expect((chunks.last as Finish).finishReason, 'stop');
    expect(chunks.whereType<Usage>().single.usage.completionTokens, 20);
    expect(plans.single.steps.map((s) => s.text), [
      'Run tests',
      'Fix failures',
    ]);
    expect(plans.single.current?.text, 'Run tests');

    final handler = StreamChunkHandler();
    chunks.forEach(handler.handle);
    final parts = handler.parts;
    expect(parts[0], isA<ReasoningPart>());
    expect((parts[0] as ReasoningPart).text, 'Thinking');
    expect((parts[1] as TextPart).text, 'Running them.');
    final tool = _tools(parts).single;
    expect(tool['name'], 'shell');
    expect(tool['arguments']['command'], 'flutter test');
    expect(tool['content'], 'All tests passed!');
    final workspace = tool['metadata']['workspace'] as Map;
    expect(workspace['command'], 'flutter test');
    expect(workspace['status'], 'ok');
    // The text after the card is a new block, below it.
    expect((parts.last as TextPart).text, 'Done.');
    agent.close();
  });

  test('an edit becomes a file card with the diff', () async {
    final (agent, channel) = await _started();
    final chunks = <StreamChunk>[];
    final done = agent.prompt('s1', const []).listen(chunks.add).asFuture();
    final prompt = await channel.next('session/prompt');
    channel
      // Announced before the agent knows the file, as agents often do.
      ..update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'e1',
        'title': 'Edit',
        'kind': 'edit',
        'status': 'in_progress',
      })
      ..update('s1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'e1',
        'status': 'completed',
        'content': [
          {
            'type': 'diff',
            'path': '/root/app/main.dart',
            'oldText': 'a\nb\n',
            'newText': 'a\nc\nd\n',
          },
        ],
      })
      ..reply(prompt, {'stopReason': 'end_turn'});
    await done;

    final handler = StreamChunkHandler();
    chunks.forEach(handler.handle);
    final tool = _tools(handler.parts).single;
    expect(tool['name'], 'edit_file');
    expect(tool['arguments']['path'], '/root/app/main.dart');
    final workspace = tool['metadata']['workspace'] as Map;
    expect(workspace['added'], 2);
    expect(workspace['removed'], 1);
    expect(workspace['files'][0]['role'], 'modified');
    agent.close();
  });

  test(
    'without a handler the agent is refused, so nothing runs unasked',
    () async {
      final (agent, channel) = await _started();
      final done = agent.prompt('s1', const []).drain<void>();
      final prompt = await channel.next('session/prompt');
      channel.emit({
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'session/request_permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {'toolCallId': 't1'},
          'options': [
            {'optionId': 'always', 'name': 'Always', 'kind': 'allow_always'},
            {'optionId': 'no', 'name': 'No', 'kind': 'reject_once'},
          ],
        },
      });
      final answer = await channel.answerTo(7);
      expect((answer['result'] as Map)['outcome'], {
        'outcome': 'selected',
        'optionId': 'no',
      });
      channel.reply(prompt, {'stopReason': 'end_turn'});
      await done;
      agent.close();
    },
  );

  test('Stop cancels the turn, answers an open question "cancelled" and the '
      'next prompt waits for the agent to wind down', () async {
    final (agent, channel) = await _started();
    final asked = Completer<void>();
    agent.onPermission = (request) {
      asked.complete();
      return Completer<String?>().future; // The user never answers.
    };
    final chunks = <StreamChunk>[];
    final subscription = agent.prompt('s1', const []).listen(chunks.add);
    final prompt = await channel.next('session/prompt');
    channel
      ..update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 't1',
        'title': 'rm -rf build',
        'kind': 'execute',
        'status': 'pending',
      })
      ..emit({
        'jsonrpc': '2.0',
        'id': 9,
        'method': 'session/request_permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {'toolCallId': 't1'},
          'options': [
            {'optionId': 'yes', 'name': 'Yes', 'kind': 'allow_once'},
          ],
        },
      });
    await asked.future;

    await agent.cancel('s1');
    final cancel = await channel.next('session/cancel');
    expect((cancel['params'] as Map)['sessionId'], 's1');
    final answer = await channel.answerTo(9);
    expect((answer['result'] as Map)['outcome'], {'outcome': 'cancelled'});

    // A new prompt sent right away waits for the stopped one.
    final second = agent.prompt('s1', const []).drain<void>();
    await pumpEventQueue();
    expect(
      channel.sent.where((m) => m['method'] == 'session/prompt'),
      hasLength(1),
    );
    channel.reply(prompt, {'stopReason': 'cancelled'});
    await subscription.asFuture<void>();
    final finish = chunks.whereType<Finish>().single;
    expect(finish.finishReason, 'cancelled');
    // The unfinished command card ends too, as failed.
    expect(
      chunks.whereType<ServerToolEnd>().single.status,
      ServerToolStatus.failed,
    );

    final nextPrompt = await channel.next('session/prompt');
    channel.reply(nextPrompt, {'stopReason': 'end_turn'});
    await second;
    agent.close();
  });

  test('a crash ends the answer with the agent\'s own error output', () async {
    final (agent, channel) = await _started();
    final result = agent.prompt('s1', const []).drain<void>();
    await channel.next('session/prompt');
    channel
      ..stderr = 'Error: ANTHROPIC_API_KEY is not set'
      ..crash();
    await expectLater(
      result,
      throwsA(
        isA<AcpError>()
            .having((e) => e.code, 'code', AcpError.disconnected)
            .having((e) => e.message, 'message', contains('ANTHROPIC_API_KEY')),
      ),
    );
    expect(agent.isAlive, isFalse);
  });

  test('an agent that never answers initialize is given up on', () async {
    final channel = _FakeAgentChannel();
    await expectLater(
      AcpAgent.start(
        channel,
        clientVersion: '1',
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<AcpError>()),
    );
  });

  test('an error answer reaches the caller with its code', () async {
    final (agent, channel) = await _started();
    final pending = agent.newSession(cwd: '/root');
    final request = await channel.next('session/new');
    channel.emit({
      'jsonrpc': '2.0',
      'id': request['id'],
      'error': {'code': -32000, 'message': 'Authentication required'},
    });
    await expectLater(
      pending,
      throwsA(
        isA<AcpError>().having((e) => e.code, 'code', AcpError.authRequired),
      ),
    );
    agent.close();
  });
}
