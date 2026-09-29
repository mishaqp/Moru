import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_chat_prompt.dart';
import 'package:Kelivo/core/services/acp/acp_chat_sessions.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/home/services/acp_chat_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';

/// A scripted agent: answers initialize, session/new|load and every prompt
/// with one text chunk naming the session and the prompt text.
class _ScriptedAgent extends AcpChannel {
  _ScriptedAgent({this.loadSession = false, this.loadFails = false});

  final bool loadSession;
  final bool loadFails;
  final _incoming = StreamController<dynamic>();
  final _closed = Completer<void>();
  final sent = <Map<String, Object?>>[];
  int sessions = 0;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  Future<void> get closed => _closed.future;

  bool get isClosed => _closed.isCompleted;

  @override
  Future<void> send(Map<String, Object?> message) async {
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(message)) as Map,
    );
    sent.add(copy);
    final id = copy['id'];
    final params = copy['params'] as Map? ?? const {};
    void reply(Object? result) => scheduleMicrotask(
      () => _incoming.add({'jsonrpc': '2.0', 'id': id, 'result': result}),
    );
    switch (copy['method']) {
      case 'initialize':
        reply({
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': loadSession},
        });
      case 'session/new':
        reply({'sessionId': 'new-${++sessions}'});
      case 'session/load':
        if (loadFails) {
          scheduleMicrotask(
            () => _incoming.add({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32002, 'message': 'Session not found'},
            }),
          );
        } else {
          reply(<String, Object?>{});
        }
      case 'session/prompt':
        final session = params['sessionId'];
        final text = [
          for (final block in params['prompt'] as List) (block as Map)['text'],
        ].join('|');
        scheduleMicrotask(() {
          _incoming
            ..add({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {
                'sessionId': session,
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {'type': 'text', 'text': '$session:$text'},
                },
              },
            })
            ..add({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'stopReason': 'end_turn'},
            });
        });
    }
  }

  @override
  void close() {
    if (!_closed.isCompleted) _closed.complete();
    unawaited(_incoming.close());
  }
}

void main() {
  const provider = AcpProviderInput(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'k',
    model: 'deepseek-chat',
  );
  final spec = AcpAgentSpec.byId('opencode')!;

  late List<_ScriptedAgent> started;
  late List<({String cwd, List<Mount> mounts})> launches;

  AcpChatSessions sessionsWith({
    bool loadSession = false,
    bool loadFails = false,
  }) {
    started = [];
    launches = [];
    return AcpChatSessions(
      start: (spec, provider, {required cwd, required mounts}) {
        launches.add((cwd: cwd, mounts: mounts));
        final channel = _ScriptedAgent(
          loadSession: loadSession,
          loadFails: loadFails,
        );
        started.add(channel);
        return AcpAgent.start(channel, clientVersion: '1');
      },
    );
  }

  AcpChatTurn turn(
    String text, {
    String conversation = 'c1',
    String? saved,
    String history = '',
    String cwd = '/workspace',
    AcpProviderInput? using,
    void Function(String)? onSession,
  }) => AcpChatTurn(
    conversationId: conversation,
    spec: spec,
    provider: using ?? provider,
    cwd: cwd,
    prompt: [
      {'type': 'text', 'text': text},
    ],
    history: history,
    savedSessionId: saved,
    onSession: onSession,
  );

  Future<String> answer(AcpChatSessions sessions, AcpChatTurn turn) async {
    final chunks = await sessions.send(turn).toList();
    expect(chunks.last, isA<Finish>());
    return chunks.whereType<TextDelta>().map((c) => c.text).join();
  }

  test('a chat keeps one agent and one session across turns', () async {
    final sessions = sessionsWith();
    final saved = <String>[];
    expect(
      await answer(
        sessions,
        turn('hi', history: 'User: old', onSession: saved.add),
      ),
      // A fresh session in a chat with history gets it first.
      'new-1:Earlier in this chat (for context, already answered):\n\n'
      'User: old\n\n---\n|hi',
    );
    expect(
      await answer(sessions, turn('more', history: 'ignored')),
      'new-1:more',
    );
    expect(started, hasLength(1));
    expect(saved, ['new-1']);
    expect(launches.single.cwd, '/workspace');
    expect(sessions.hasAgent('c1'), isTrue);

    // Another chat gets its own agent.
    expect(await answer(sessions, turn('x', conversation: 'c2')), 'new-1:x');
    expect(started, hasLength(2));
    sessions.closeAll();
    expect(started.every((agent) => agent.isClosed), isTrue);
  });

  test('a new model or folder starts a new agent', () async {
    final sessions = sessionsWith();
    await answer(sessions, turn('a'));
    await answer(
      sessions,
      turn(
        'b',
        using: const AcpProviderInput(
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'k',
          model: 'deepseek-reasoner',
        ),
      ),
    );
    expect(started, hasLength(2));
    expect(started.first.isClosed, isTrue);
    await answer(sessions, turn('c', cwd: '/workspace/app'));
    expect(started, hasLength(3));
    sessions.closeAll();
  });

  test('a saved session is reopened when the agent can, with no history '
      'sent again', () async {
    final sessions = sessionsWith(loadSession: true);
    final saved = <String>[];
    expect(
      await answer(
        sessions,
        turn('hi', saved: 'old-7', history: 'User: old', onSession: saved.add),
      ),
      'old-7:hi',
    );
    expect(
      started.single.sent.map((m) => m['method']),
      containsAllInOrder(['initialize', 'session/load', 'session/prompt']),
    );
    expect(saved, isEmpty);
    sessions.closeAll();
  });

  test('a session the agent lost starts over with the history', () async {
    final sessions = sessionsWith(loadSession: true, loadFails: true);
    final saved = <String>[];
    final text = await answer(
      sessions,
      turn('hi', saved: 'gone', history: 'User: old', onSession: saved.add),
    );
    expect(text, startsWith('new-1:Earlier in this chat'));
    expect(saved, ['new-1']);
    sessions.closeAll();
  });

  test('an idle agent is stopped to free memory', () async {
    started = [];
    final sessions = AcpChatSessions(
      idleTimeout: const Duration(milliseconds: 20),
      start: (spec, provider, {required cwd, required mounts}) {
        final channel = _ScriptedAgent();
        started.add(channel);
        return AcpAgent.start(channel, clientVersion: '1');
      },
    );
    await answer(sessions, turn('hi'));
    expect(sessions.hasAgent('c1'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sessions.hasAgent('c1'), isFalse);
    expect(started.single.isClosed, isTrue);
  });

  test('the prompt is the newest user message; the history leaves out '
      'system prompts', () {
    final result = acpPromptFromMessages([
      {'role': 'system', 'content': 'You are Moru.'},
      {'role': 'user', 'content': 'Make a game'},
      {'role': 'assistant', 'content': 'Done: snake.html'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Make it faster'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AAAA'},
          },
        ],
      },
      {'role': 'assistant', 'content': ''},
    ]);
    expect(result.prompt, [
      {'type': 'text', 'text': 'Make it faster'},
    ]);
    expect(result.history, 'User: Make a game\n\nAssistant: Done: snake.html');
    expect(result.history, isNot(contains('Moru')));

    final long = acpPromptFromMessages([
      {'role': 'user', 'content': 'x' * 100},
      {'role': 'user', 'content': 'now'},
    ], historyLimit: 20);
    expect(long.history.length, 21);
    expect(long.history, startsWith('…'));
  });

  group('permission on the tool card', () {
    const request = AcpPermissionRequest(
      sessionId: 's',
      toolCallId: 'acp-tool-t1',
      title: 'rm -rf build',
      kind: 'execute',
      input: {'command': 'rm -rf build'},
      options: [
        AcpPermissionOption(id: 'always', name: 'Always', kind: 'allow_always'),
        AcpPermissionOption(id: 'once', name: 'Once', kind: 'allow_once'),
        AcpPermissionOption(id: 'no', name: 'No', kind: 'reject_once'),
      ],
    );

    test('Allow picks allow-once, Deny picks reject-once', () async {
      final approvals = ToolApprovalService();
      final allowed = AcpChatBridge.answerPermission(
        approvals,
        request,
        conversationId: 'c1',
      );
      final pending = approvals.pendingFor(
        toolCallId: 'acp-tool-t1',
        conversationId: 'c1',
      );
      expect(pending?.toolName, 'rm -rf build');
      expect(pending?.arguments['command'], 'rm -rf build');
      approvals.approve('acp-tool-t1', conversationId: 'c1');
      expect(await allowed, 'once');

      final denied = AcpChatBridge.answerPermission(
        approvals,
        request,
        conversationId: 'c1',
      );
      approvals.deny('acp-tool-t1', conversationId: 'c1');
      expect(await denied, 'no');
    });

    test('trusted mode allows without asking', () async {
      final approvals = ToolApprovalService()..setAutoApproveAll(true);
      expect(
        await AcpChatBridge.answerPermission(
          approvals,
          request,
          conversationId: 'c1',
        ),
        'once',
      );
      expect(approvals.hasPending, isFalse);
    });
  });
}
