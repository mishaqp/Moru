import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../models/agent_auth_mode.dart';

import '../api/stream/stream_chunk.dart';
import '../workspace/task_plan.dart';
import '../workspace/workspace_runtime.dart';
import 'acp_agent.dart';
import 'acp_agent_catalog.dart';
import 'acp_chat_prompt.dart';
import 'acp_mcp_binding.dart';

/// Starts an agent process for a chat.
typedef AcpAgentStarter =
    Future<AcpAgent> Function(
      AcpAgentSpec spec,
      AcpProviderInput? provider, {
      required String cwd,
      required List<Mount> mounts,
      required AgentAuthMode authMode,
    });

/// What a chat turn needs from the agent.
class AcpChatTurn {
  const AcpChatTurn({
    required this.conversationId,
    required this.spec,
    this.provider,
    this.authMode = AgentAuthMode.provider,
    required this.cwd,
    this.mounts = const [],
    required this.prompt,
    this.userImagePaths = const [],
    this.imageNotSentMessage = "An image was not sent to the agent.",
    this.history = '',
    this.savedSessionId,
    this.savedModeId,
    this.onSession,
    this.onPermission,
    this.onPlan,
    this.moruTools,
  });

  final String conversationId;
  final AcpAgentSpec spec;
  final AcpProviderInput? provider;
  final AgentAuthMode authMode;
  final String cwd;
  final List<Mount> mounts;

  /// ACP content blocks of the new message.
  final List<Map<String, Object?>> prompt;
  final List<String> userImagePaths;
  final String imageNotSentMessage;

  /// The chat so far as text, given to a session that starts fresh in the
  /// middle of a chat so the agent knows what was said.
  final String history;

  /// The chat's session from an earlier run, reopened when the agent can.
  final String? savedSessionId;
  final String? savedModeId;
  final FutureOr<void> Function(String sessionId)? onSession;
  final AcpPermissionHandler? onPermission;
  final void Function(TaskPlan plan)? onPlan;
  final AcpMcpTools? moruTools;
}

/// One agent process per chat that talks to one: the process and its
/// session live across turns, so the agent keeps its own context. A chat
/// whose agent, model or folder changed gets a fresh process; one left idle
/// is stopped to free memory.
class AcpChatSessions extends ChangeNotifier {
  AcpChatSessions({
    required this.start,
    this.idleTimeout = const Duration(minutes: 20),
  });

  final AcpAgentStarter start;
  final Duration idleTimeout;
  final Map<String, _ChatAgent> _chats = {};
  Future<void> _codexRouting = Future<void>.value();

  bool hasAgent(String conversationId) =>
      _chats[conversationId]?.agent.isAlive == true;

  AcpSession? sessionFor(String? conversationId) =>
      _chats[conversationId]?.session;

  /// Reopen the existing context without sending or replaying any prompt.
  Future<AcpSession> ensureSession(AcpChatTurn turn) async {
    final chat = await _ensure(turn);
    _armIdle(turn.conversationId, chat);
    return chat.session;
  }

  /// Streams the agent's answer to [turn] as chat chunks.
  Stream<StreamChunk> send(AcpChatTurn turn) async* {
    final activity = Object();
    final chat = await _ensure(turn, activity: activity);
    try {
      chat.idle?.cancel();
      if (turn.moruTools case final tools?) chat.mcp?.beginTurn(tools);
      chat.agent.onPermission = (request) async {
        if (chat.mcp?.ownsPermission(request) == true) {
          return chat.mcp!.permissionChoice(request);
        }
        return turn.onPermission?.call(request);
      };
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
      prompt = [
        ...prompt,
        ...await acpImagePromptBlocks(
          turn.userImagePaths,
          supported:
              chat.agent.info.imagePrompts &&
              (turn.authMode == AgentAuthMode.subscription ||
                  turn.provider?.imageInput == true),
          notSentMessage: turn.imageNotSentMessage,
        ),
      ];
      if (!chat.activePrompts.contains(activity)) return;
      final mode = turn.savedModeId;
      if (mode != null &&
          mode != chat.session.currentModeId &&
          chat.session.modes.any((m) => m.id == mode)) {
        await chat.agent.setMode(chat.sessionId, mode);
        chat.session = AcpSession(
          id: chat.sessionId,
          modes: chat.session.modes,
          currentModeId: mode,
        );
        notifyListeners();
      }
      if (!chat.activePrompts.contains(activity)) return;
      chat.needsHistory = false;
      yield* chat.agent.prompt(chat.sessionId, prompt, onPlan: turn.onPlan);
    } finally {
      chat.activePrompts.remove(activity);
      chat.mcp?.endTurn();
      if (chat.agent.isAlive) {
        _armIdle(turn.conversationId, chat);
      } else if (identical(_chats[turn.conversationId], chat)) {
        if (chat.mcp case final mcp?) unawaited(mcp.close());
        _chats.remove(turn.conversationId);
        notifyListeners();
      }
    }
  }

  Future<void> cancel(String conversationId) async {
    final chat = _chats[conversationId];
    if (chat == null || !chat.agent.isAlive) return;
    final active = chat.activePrompts.toList();
    chat.mcp?.endTurn();
    await chat.agent.cancel(chat.sessionId);
    chat.activePrompts.removeAll(active);
    _armIdle(conversationId, chat);
  }

  void close(String conversationId) => unawaited(_closeChat(conversationId));

  Future<void> _closeChat(String conversationId) {
    final chat = _chats.remove(conversationId);
    if (chat == null) return Future<void>.value();
    chat.idle?.cancel();
    chat.activePrompts.clear();
    chat.agent.close();
    final stopped = Future.wait<void>([
      chat.agent.done,
      if (chat.mcp case final mcp?) mcp.close(),
    ]).then((_) {});
    notifyListeners();
    return stopped;
  }

  void closeAll() {
    for (final id in _chats.keys.toList()) {
      close(id);
    }
  }

  void _armIdle(String conversationId, _ChatAgent chat) {
    if (!identical(_chats[conversationId], chat) ||
        !chat.agent.isAlive ||
        chat.activePrompts.isNotEmpty) {
      return;
    }
    chat.idle?.cancel();
    chat.idle = Timer(idleTimeout, () {
      if (identical(_chats[conversationId], chat)) close(conversationId);
    });
  }

  Future<_ChatAgent> _ensure(AcpChatTurn turn, {Object? activity}) {
    Future<_ChatAgent> open() async {
      final chat = await _open(turn);
      if (activity != null) chat.activePrompts.add(activity);
      return chat;
    }

    if (turn.spec.id != AcpAgentSpec.codexId ||
        turn.authMode != AgentAuthMode.subscription) {
      return open();
    }
    final routed = _codexRouting.then((_) async {
      final others = _chats.entries
          .where(
            (entry) =>
                entry.key != turn.conversationId &&
                entry.value.isCodexSubscription,
          )
          .toList();
      if (others.any((entry) => entry.value.activePrompts.isNotEmpty)) {
        throw const AcpError(
          AcpError.internalError,
          'Codex is active in another chat',
          null,
          AcpFailureKind.accountBusy,
        );
      }
      for (final entry in others) {
        await _closeChat(entry.key);
      }
      return open();
    });
    // Hold the routing slot through initialize/restore and prompt reservation.
    // A later request can neither start a competitor nor steal a new turn.
    _codexRouting = routed.then<void>((_) {}, onError: (Object _) {});
    return routed;
  }

  Future<_ChatAgent> _open(AcpChatTurn turn) async {
    final key = _launchKey(turn);
    final existing = _chats[turn.conversationId];
    if (existing != null && existing.key == key && existing.agent.isAlive) {
      return existing;
    }
    if (existing != null) await _closeChat(turn.conversationId);
    final agent = await start(
      turn.spec,
      turn.authMode == AgentAuthMode.subscription ? null : turn.provider,
      cwd: turn.cwd,
      mounts: turn.mounts,
      authMode: turn.authMode,
    );
    AcpMcpBinding? mcp;
    try {
      if (turn.moruTools case final tools?) {
        mcp = await AcpMcpBinding.start(tools, redactor: agent.redactor);
      }
      final mcpServers = [if (mcp != null) mcp.serverConfig(agent.info)];
      AcpSession? session;
      var needsHistory = true;
      final saved = turn.savedSessionId;
      if (saved != null &&
          (agent.info.loadSession || agent.info.resumeSession)) {
        try {
          session = agent.info.loadSession
              ? await agent.loadSession(
                  sessionId: saved,
                  cwd: turn.cwd,
                  mcpServers: mcpServers,
                )
              : await agent.resumeSession(
                  sessionId: saved,
                  cwd: turn.cwd,
                  mcpServers: mcpServers,
                );
          needsHistory = false;
        } on AcpError catch (error) {
          if (error.code == AcpError.authRequired ||
              error.failureKind == AcpFailureKind.authRequired) {
            rethrow;
          }
          // The agent lost it (updated, cleaned up): start over with the
          // chat's history instead.
        }
      }
      if (session == null) {
        session = await agent.newSession(cwd: turn.cwd, mcpServers: mcpServers);
        await turn.onSession?.call(session.id);
      }
      final chat = _ChatAgent(
        key,
        agent,
        session,
        mcp,
        specId: turn.spec.id,
        authMode: turn.authMode,
      )..needsHistory = needsHistory;
      agent.onToolCorrelation = (sessionId, correlation) {
        if (sessionId == chat.sessionId) {
          chat.mcp?.observeCorrelation(correlation);
        }
      };
      agent.onModeChanged = (sessionId, modeId) {
        if (sessionId != chat.sessionId ||
            !identical(_chats[turn.conversationId], chat)) {
          return;
        }
        chat.session = AcpSession(
          id: sessionId,
          modes: chat.session.modes,
          currentModeId: modeId,
        );
        notifyListeners();
      };
      _chats[turn.conversationId] = chat;
      notifyListeners();
      unawaited(
        agent.done.then((_) {
          if (chat.mcp case final mcp?) unawaited(mcp.close());
          if (identical(_chats[turn.conversationId], chat)) {
            _chats.remove(turn.conversationId);
            chat.idle?.cancel();
            notifyListeners();
          }
        }),
      );
      return chat;
    } catch (_) {
      await mcp?.close();
      agent.close();
      rethrow;
    }
  }

  @override
  void dispose() {
    closeAll();
    super.dispose();
  }

  static String _launchKey(AcpChatTurn turn) => [
    turn.spec.id,
    turn.spec.command,
    ...turn.spec.arguments,
    turn.authMode.name,
    if (turn.authMode == AgentAuthMode.provider) ...[
      turn.provider?.baseUrl,
      turn.provider?.model,
      turn.provider?.imageInput,
      turn.provider?.contextWindow,
      turn.provider?.apiKey.hashCode,
    ],
    turn.cwd,
    turn.moruTools?.key,
    for (final mount in turn.mounts) '${mount.host}>${mount.guest}',
  ].join('\u0000');
}

class _ChatAgent {
  _ChatAgent(
    this.key,
    this.agent,
    this.session,
    this.mcp, {
    required this.specId,
    required this.authMode,
  });

  final String key;
  final AcpAgent agent;
  final AcpMcpBinding? mcp;
  final String specId;
  final AgentAuthMode authMode;
  final Set<Object> activePrompts = {};
  bool get isCodexSubscription =>
      specId == AcpAgentSpec.codexId && authMode == AgentAuthMode.subscription;
  AcpSession session;
  String get sessionId => session.id;
  bool needsHistory = true;
  Timer? idle;
}
