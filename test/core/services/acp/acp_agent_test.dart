import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/acp/acp_agent.dart';
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

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> send(Map<String, Object?> message) async {
    if (_closed.isCompleted) throw StateError('closed');
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
}) async {
  final channel = _FakeAgentChannel();
  final agent = AcpAgent.start(channel, clientVersion: '0.1.47');
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
