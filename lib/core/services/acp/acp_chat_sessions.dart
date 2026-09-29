import 'dart:async';

import '../api/stream/stream_chunk.dart';
import '../workspace/task_plan.dart';
import '../workspace/workspace_runtime.dart';
import 'acp_agent.dart';
import 'acp_agent_catalog.dart';

/// Starts an agent process for a chat.
typedef AcpAgentStarter =
    Future<AcpAgent> Function(
      AcpAgentSpec spec,
      AcpProviderInput provider, {
      required String cwd,
      required List<Mount> mounts,
    });

/// What a chat turn needs from the agent.
class AcpChatTurn {
  const AcpChatTurn({
    required this.conversationId,
    required this.spec,
    required this.provider,
    required this.cwd,
    this.mounts = const [],
    required this.prompt,
    this.history = '',
    this.savedSessionId,
    this.onSession,
    this.onPermission,
    this.onPlan,
  });

  final String conversationId;
  final AcpAgentSpec spec;
  final AcpProviderInput provider;
  final String cwd;
  final List<Mount> mounts;

  /// ACP content blocks of the new message.
  final List<Map<String, Object?>> prompt;

  /// The chat so far as text, given to a session that starts fresh in the
  /// middle of a chat so the agent knows what was said.
  final String history;

  /// The chat's session from an earlier run, reopened when the agent can.
  final String? savedSessionId;
  final void Function(String sessionId)? onSession;
  final AcpPermissionHandler? onPermission;
  final void Function(TaskPlan plan)? onPlan;
}

/// One agent process per chat that talks to one: the process and its
/// session live across turns, so the agent keeps its own context. A chat
/// whose agent, model or folder changed gets a fresh process; one left idle
/// is stopped to free memory.
class AcpChatSessions {
  AcpChatSessions({
    required this.start,
    this.idleTimeout = const Duration(minutes: 20),
  });

  final AcpAgentStarter start;
  final Duration idleTimeout;
  final Map<String, _ChatAgent> _chats = {};

  bool hasAgent(String conversationId) =>
      _chats[conversationId]?.agent.isAlive == true;

  /// Streams the agent's answer to [turn] as chat chunks.
  Stream<StreamChunk> send(AcpChatTurn turn) async* {
    final chat = await _ensure(turn);
    chat.idle?.cancel();
    chat.agent.onPermission = turn.onPermission;
    var prompt = turn.prompt;
    if (chat.needsHistory && turn.history.trim().isNotEmpty) {
      prompt = [
        {
          'type': 'text',
          'text':
              'Earlier in this chat (for context, already answered):\n\n'
              '${turn.history.trim()}\n\n---\n',
        },
        ...prompt,
      ];
    }
    chat.needsHistory = false;
    try {
      yield* chat.agent.prompt(chat.sessionId, prompt, onPlan: turn.onPlan);
    } finally {
      if (chat.agent.isAlive) {
        chat.idle = Timer(idleTimeout, () => close(turn.conversationId));
      } else {
        _chats.remove(turn.conversationId);
      }
    }
  }

  Future<void> cancel(String conversationId) async {
    final chat = _chats[conversationId];
    if (chat == null || !chat.agent.isAlive) return;
    await chat.agent.cancel(chat.sessionId);
  }

  void close(String conversationId) {
    final chat = _chats.remove(conversationId);
    chat?.idle?.cancel();
    chat?.agent.close();
  }

  void closeAll() {
    for (final id in _chats.keys.toList()) {
      close(id);
    }
  }

  Future<_ChatAgent> _ensure(AcpChatTurn turn) async {
    final key = _launchKey(turn);
    final existing = _chats[turn.conversationId];
    if (existing != null && existing.key == key && existing.agent.isAlive) {
      return existing;
    }
    if (existing != null) close(turn.conversationId);
    final agent = await start(
      turn.spec,
      turn.provider,
      cwd: turn.cwd,
      mounts: turn.mounts,
    );
    try {
      String? sessionId;
      var needsHistory = true;
      final saved = turn.savedSessionId;
      if (saved != null && agent.info.loadSession) {
        try {
          await agent.loadSession(sessionId: saved, cwd: turn.cwd);
          sessionId = saved;
          needsHistory = false;
        } on AcpError {
          // The agent lost it (updated, cleaned up): start over with the
          // chat's history instead.
        }
      }
      if (sessionId == null) {
        sessionId = (await agent.newSession(cwd: turn.cwd)).id;
        turn.onSession?.call(sessionId);
      }
      final chat = _ChatAgent(key, agent, sessionId)
        ..needsHistory = needsHistory;
      _chats[turn.conversationId] = chat;
      unawaited(
        agent.done.then((_) {
          if (identical(_chats[turn.conversationId], chat)) {
            _chats.remove(turn.conversationId);
          }
        }),
      );
      return chat;
    } catch (_) {
      agent.close();
      rethrow;
    }
  }

  static String _launchKey(AcpChatTurn turn) => [
    turn.spec.id,
    turn.spec.command,
    ...turn.spec.arguments,
    turn.provider.baseUrl,
    turn.provider.model,
    turn.provider.apiKey.hashCode,
    turn.cwd,
    for (final mount in turn.mounts) '${mount.host}>${mount.guest}',
  ].join('\u0000');
}

class _ChatAgent {
  _ChatAgent(this.key, this.agent, this.sessionId);

  final String key;
  final AcpAgent agent;
  final String sessionId;
  bool needsHistory = true;
  Timer? idle;
}
