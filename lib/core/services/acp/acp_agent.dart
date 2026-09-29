import 'dart:async';

import '../../models/token_usage.dart';
import '../api/stream/stream_chunk.dart';
import '../workspace/task_plan.dart';
import 'acp_connection.dart';
import 'acp_turn_translator.dart';

export 'acp_connection.dart' show AcpChannel, AcpError;

/// ACP protocol version Moru speaks.
const int acpProtocolVersion = 1;

/// What the agent said about itself when it started.
class AcpAgentInfo {
  const AcpAgentInfo({
    this.name,
    this.version,
    this.loadSession = false,
    this.imagePrompts = false,
    this.authMethods = const [],
  });

  factory AcpAgentInfo.fromInitialize(Map<String, Object?> result) {
    final caps = _map(result['agentCapabilities']);
    final prompt = _map(caps['promptCapabilities']);
    final info = _map(result['agentInfo']);
    return AcpAgentInfo(
      name: info['title'] as String? ?? info['name'] as String?,
      version: info['version'] as String?,
      loadSession: caps['loadSession'] == true,
      imagePrompts: prompt['image'] == true,
      authMethods: [
        for (final method in result['authMethods'] as List? ?? const [])
          if (method is Map && method['id'] is String)
            AcpAuthMethod(
              id: method['id'] as String,
              name: (method['name'] ?? method['id']).toString(),
              description: method['description'] as String?,
            ),
      ],
    );
  }

  final String? name;
  final String? version;

  /// The agent can reopen an earlier session (`session/load`).
  final bool loadSession;

  /// Prompts may carry images.
  final bool imagePrompts;
  final List<AcpAuthMethod> authMethods;
}

class AcpAuthMethod {
  const AcpAuthMethod({required this.id, required this.name, this.description});

  final String id;
  final String name;
  final String? description;
}

/// A mode the agent offers for a session ("Ask", "Code", "Plan").
class AcpMode {
  const AcpMode({required this.id, required this.name, this.description});

  final String id;
  final String name;
  final String? description;
}

class AcpSession {
  const AcpSession({
    required this.id,
    this.modes = const [],
    this.currentModeId,
  });

  factory AcpSession.fromResult(String id, Map<String, Object?> result) {
    final modes = _map(result['modes']);
    return AcpSession(
      id: id,
      currentModeId: modes['currentModeId'] as String?,
      modes: [
        for (final mode in modes['availableModes'] as List? ?? const [])
          if (mode is Map && mode['id'] is String)
            AcpMode(
              id: mode['id'] as String,
              name: (mode['name'] ?? mode['id']).toString(),
              description: mode['description'] as String?,
            ),
      ],
    );
  }

  final String id;
  final List<AcpMode> modes;
  final String? currentModeId;
}

/// One choice the agent offers when it asks to run something.
class AcpPermissionOption {
  const AcpPermissionOption({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;

  /// `allow_once`, `allow_always`, `reject_once` or `reject_always`.
  final String kind;

  bool get allows => kind.startsWith('allow');
}

/// The agent asks before a step (running a command, editing a file).
class AcpPermissionRequest {
  const AcpPermissionRequest({
    required this.sessionId,
    required this.toolCallId,
    required this.title,
    required this.kind,
    required this.input,
    required this.options,
  });

  final String sessionId;

  /// The id of the tool card the request is about
  /// ([AcpTurnTranslator.cardId]); empty when the agent sent none.
  final String toolCallId;
  final String title;

  /// ACP tool kind: `execute`, `edit`, `read`, `fetch`…
  final String kind;
  final Object? input;
  final List<AcpPermissionOption> options;
}

/// Answers a permission request with an option id, or null to cancel.
typedef AcpPermissionHandler =
    Future<String?> Function(AcpPermissionRequest request);

/// A running ACP agent process: sessions, prompts, cancel, permissions.
///
/// Moru does not offer the agent its file system or terminal: the agent runs
/// inside the Linux environment next to the workspace and uses its own
/// tools there, which keeps every agent's behaviour its authors' own.
class AcpAgent {
  AcpAgent._(AcpChannel channel) {
    _connection = AcpConnection(
      channel,
      onRequest: _onRequest,
      onNotification: _onNotification,
    );
  }

  late final AcpConnection _connection;
  late final AcpAgentInfo info;
  final Map<String, _Turn> _turns = {};

  /// Asked when the agent wants permission; with none set, the first
  /// "reject" option is chosen so nothing runs unasked.
  AcpPermissionHandler? onPermission;

  /// Completes when the process is gone.
  Future<void> get done => _connection.done;
  bool get isAlive => _connection.isOpen;
  AcpError? get failure => _connection.failure;

  /// Starts talking to an agent on [channel]; fails with [AcpError] when
  /// the process does not answer `initialize` within [timeout].
  static Future<AcpAgent> start(
    AcpChannel channel, {
    required String clientVersion,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final agent = AcpAgent._(channel);
    try {
      final result = await agent._connection
          .request('initialize', {
            'protocolVersion': acpProtocolVersion,
            'clientCapabilities': {
              'fs': {'readTextFile': false, 'writeTextFile': false},
              'terminal': false,
            },
            'clientInfo': {
              'name': 'moru',
              'title': 'Moru',
              'version': clientVersion,
            },
          })
          .timeout(timeout);
      agent.info = AcpAgentInfo.fromInitialize(result);
      return agent;
    } on TimeoutException {
      agent.close();
      throw const AcpError(
        AcpError.disconnected,
        'The agent did not answer in time',
      );
    } catch (_) {
      agent.close();
      rethrow;
    }
  }

  Future<void> authenticate(String methodId) =>
      _connection.request('authenticate', {'methodId': methodId});

  Future<AcpSession> newSession({
    required String cwd,
    List<Map<String, Object?>> mcpServers = const [],
  }) async {
    final result = await _connection.request('session/new', {
      'cwd': cwd,
      'mcpServers': mcpServers,
    });
    final id = result['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const AcpError(AcpError.internalError, 'No session id');
    }
    return AcpSession.fromResult(id, result);
  }

  /// Reopens [sessionId]. The agent replays the history as updates; the
  /// chat already has it, so they are not shown.
  Future<AcpSession> loadSession({
    required String sessionId,
    required String cwd,
    List<Map<String, Object?>> mcpServers = const [],
  }) async {
    final result = await _connection.request('session/load', {
      'sessionId': sessionId,
      'cwd': cwd,
      'mcpServers': mcpServers,
    });
    return AcpSession.fromResult(sessionId, result);
  }

  Future<void> setMode(String sessionId, String modeId) => _connection.request(
    'session/set_mode',
    {'sessionId': sessionId, 'modeId': modeId},
  );

  /// Sends [prompt] content blocks and streams the answer as chat chunks.
  ///
  /// The stream ends with [Finish]. Cancelling the subscription stops the
  /// agent (`session/cancel`), as does [cancel].
  Stream<StreamChunk> prompt(
    String sessionId,
    List<Map<String, Object?>> prompt, {
    void Function(TaskPlan plan)? onPlan,
  }) {
    late final StreamController<StreamChunk> controller;
    final turn = _Turn(AcpTurnTranslator(onPlan: onPlan));
    controller = StreamController<StreamChunk>(
      onListen: () async {
        // A stopped turn may still be winding down in the agent; the next
        // prompt waits for it instead of failing.
        final previous = _turns[sessionId];
        if (previous != null && previous.cancelled) await previous.ended;
        if (_turns.containsKey(sessionId)) {
          controller
            ..addError(
              const AcpError(
                AcpError.internalError,
                'The agent is still answering in this session',
              ),
            )
            ..close();
          return;
        }
        if (turn.closed) return;
        _turns[sessionId] = turn..sink = controller;
        _connection
            .request('session/prompt', {
              'sessionId': sessionId,
              'prompt': prompt,
            })
            .then(
              (result) {
                if (!identical(_turns[sessionId], turn)) return;
                final usage = _usage(result['usage']);
                if (usage != null) controller.add(Usage(usage));
                final stopReason = turn.cancelled
                    ? 'cancelled'
                    : result['stopReason'] as String?;
                turn.finish(stopReason);
              },
              onError: (Object error) {
                if (!identical(_turns[sessionId], turn)) return;
                if (turn.cancelled) {
                  turn.finish('cancelled');
                } else {
                  turn.fail(error);
                }
              },
            )
            .whenComplete(() {
              if (identical(_turns[sessionId], turn)) {
                _turns.remove(sessionId);
              }
              turn.markEnded();
            });
      },
      onCancel: () async {
        final running = identical(_turns[sessionId], turn) && !turn.closed;
        turn.closed = true;
        if (running) await cancel(sessionId);
      },
    );
    return controller.stream;
  }

  /// Asks the agent to stop the running prompt; open permission prompts
  /// are answered "cancelled". The prompt then ends with stop reason
  /// `cancelled`.
  Future<void> cancel(String sessionId) async {
    final turn = _turns[sessionId];
    if (turn != null) {
      turn.cancelled = true;
      turn.cancelPermissions();
    }
    await _connection.notify('session/cancel', {'sessionId': sessionId});
  }

  void close() {
    for (final turn in _turns.values.toList()) {
      turn.fail(
        _connection.failure ??
            const AcpError(AcpError.disconnected, 'The agent was stopped'),
      );
    }
    _turns.clear();
    _connection.close();
  }

  void _onNotification(String method, Map<String, Object?> params) {
    if (method != 'session/update') return;
    final turn = _turns[params['sessionId']];
    final update = params['update'];
    if (turn == null || update is! Map) return;
    turn.add(turn.translator.translate(Map<String, Object?>.from(update)));
  }

  Future<Object?> _onRequest(String method, Map<String, Object?> params) async {
    if (method != 'session/request_permission') {
      throw const AcpError(AcpError.methodNotFound, 'Not supported by Moru');
    }
    final sessionId = (params['sessionId'] ?? '').toString();
    final toolCall = _map(params['toolCall']);
    final options = [
      for (final option in params['options'] as List? ?? const [])
        if (option is Map && option['optionId'] is String)
          AcpPermissionOption(
            id: option['optionId'] as String,
            name: (option['name'] ?? option['optionId']).toString(),
            kind: (option['kind'] ?? '').toString(),
          ),
    ];
    final turn = _turns[sessionId];
    // A permission request is also a tool update: the card shows what is
    // being asked about while the choice is open.
    if (turn != null && toolCall.isNotEmpty) {
      turn.add(
        turn.translator.translate({
          ...toolCall,
          'sessionUpdate': 'tool_call_update',
        }),
      );
    }
    if (turn == null || turn.cancelled) return _cancelledOutcome;
    final handler = onPermission;
    final String? choice;
    if (handler == null) {
      choice = options
          .where((option) => !option.allows)
          .map((option) => option.id)
          .firstOrNull;
    } else {
      final answer = Completer<String?>();
      turn.permissions.add(answer);
      unawaited(
        handler(
          AcpPermissionRequest(
            sessionId: sessionId,
            toolCallId: toolCall['toolCallId'] is String
                ? AcpTurnTranslator.cardId(toolCall['toolCallId'] as String)
                : '',
            title: (toolCall['title'] ?? '').toString(),
            kind: (toolCall['kind'] ?? 'other').toString(),
            input: toolCall['rawInput'],
            options: options,
          ),
        ).then(
          (value) {
            if (!answer.isCompleted) answer.complete(value);
          },
          onError: (Object _) {
            if (!answer.isCompleted) answer.complete(null);
          },
        ),
      );
      choice = await answer.future;
      turn.permissions.remove(answer);
    }
    if (choice == null || turn.cancelled) return _cancelledOutcome;
    return {
      'outcome': {'outcome': 'selected', 'optionId': choice},
    };
  }

  static const Map<String, Object?> _cancelledOutcome = {
    'outcome': {'outcome': 'cancelled'},
  };

  static TokenUsage? _usage(Object? raw) {
    if (raw is! Map) return null;
    int read(String key) => (raw[key] as num?)?.toInt() ?? 0;
    final input = read('inputTokens');
    final output = read('outputTokens');
    final cached = read('cachedReadTokens');
    if (input == 0 && output == 0) return null;
    return TokenUsage(
      promptTokens: input + cached + read('cachedWriteTokens'),
      completionTokens: output,
      cachedTokens: cached,
      totalTokens: read('totalTokens'),
    );
  }
}

class _Turn {
  _Turn(this.translator);

  final AcpTurnTranslator translator;
  late StreamController<StreamChunk> sink;
  final List<Completer<String?>> permissions = [];
  bool cancelled = false;
  bool closed = false;
  final Completer<void> _ended = Completer<void>();

  /// Completes when the agent has answered this turn's `session/prompt`.
  Future<void> get ended => _ended.future;

  void markEnded() {
    if (!_ended.isCompleted) _ended.complete();
  }

  void add(List<StreamChunk> chunks) {
    if (closed) return;
    for (final chunk in chunks) {
      sink.add(chunk);
    }
  }

  void finish(String? stopReason) {
    add(translator.finish(stopReason));
    _close();
  }

  void fail(Object error) {
    if (!closed) sink.addError(error);
    _close();
  }

  void cancelPermissions() {
    for (final answer in permissions.toList()) {
      if (!answer.isCompleted) answer.complete(null);
    }
  }

  void _close() {
    cancelPermissions();
    if (closed) return;
    closed = true;
    unawaited(sink.close());
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};
