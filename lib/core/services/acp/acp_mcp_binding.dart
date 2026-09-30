import 'dart:async';
import 'dart:convert';

import '../api/tool_call_cancellation.dart';
import 'acp_agent.dart';
import 'acp_mcp_server.dart';
import 'acp_mcp_stdio_bridge.dart';
import 'acp_turn_translator.dart';

/// Live tool policy and the existing model handler for one assistant/chat.
class AcpMcpTools {
  const AcpMcpTools({
    required this.key,
    required this.definitions,
    required this.execute,
    this.cancelApproval,
  });

  final String key;
  final List<Map<String, dynamic>> Function() definitions;
  final Future<Map<String, Object?>> Function(
    String name,
    Map<String, dynamic> arguments, {
    required String toolCallId,
  })
  execute;
  final void Function(String toolCallId)? cancelApproval;
}

/// Matches HTTP calls to the cards the agent already streams over ACP.
class AcpMcpBinding {
  AcpMcpBinding._(this._tools);

  AcpMcpTools _tools;
  late final AcpMcpServer server;
  _McpTurn? _turn;

  static Future<AcpMcpBinding> start(AcpMcpTools tools) async {
    final binding = AcpMcpBinding._(tools);
    binding.server = await AcpMcpServer.start(
      tools: () => binding._tools.definitions(),
      callTool: binding.callTool,
    );
    return binding;
  }

  Map<String, Object?> serverConfig(AcpAgentInfo info) => info.mcpHttp
      ? {
          'type': 'http',
          'name': 'moru',
          'url': server.url,
          'headers': [
            {'name': 'Authorization', 'value': 'Bearer ${server.token}'},
          ],
        }
      : {
          'name': 'moru',
          'command': 'node',
          'args': [AcpMcpStdioBridge.file.path],
          'env': [
            {'name': 'MORU_MCP_URL', 'value': server.url},
            {'name': 'MORU_MCP_TOKEN', 'value': server.token},
          ],
        };

  void beginTurn(AcpMcpTools tools) {
    endTurn();
    _tools = tools;
    _turn = _McpTurn(tools);
  }

  void endTurn() {
    final turn = _turn;
    _turn = null;
    if (turn == null) return;
    turn.cancelled.complete();
    turn.wake();
    for (final card in turn.cards.values.where((card) => card.claimed)) {
      turn.tools.cancelApproval?.call(AcpTurnTranslator.cardId(card.id));
    }
  }

  void observe(Map<String, Object?> update) {
    final turn = _turn;
    final id = update['toolCallId'];
    if (turn == null || id is! String) return;
    final card = turn.cards.putIfAbsent(id, () => _McpCard(id));
    card.update.addAll(update);
    // Running updates can replace a machine-readable title with a human one.
    card.name ??= _toolName(card.update);
    turn.wake();
  }

  bool ownsPermission(AcpPermissionRequest request) =>
      _turn?.cards.values.any(
        (card) =>
            card.name != null &&
            AcpTurnTranslator.cardId(card.id) == request.toolCallId,
      ) ==
      true;

  /// Agent-side permission delegates to the Moru handler's approval gate.
  String? permissionChoice(AcpPermissionRequest request) {
    if (!ownsPermission(request)) return null;
    return request.options
            .where((option) => option.kind == 'allow_once')
            .map((option) => option.id)
            .firstOrNull ??
        request.options
            .where((option) => option.allows)
            .map((option) => option.id)
            .firstOrNull;
  }

  Future<Map<String, Object?>> callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final turn = _turn;
    if (turn == null) return _error('No active agent turn.');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!turn.cancelled.isCompleted) {
      final card = turn.cards.values
          .where(
            (card) =>
                !card.claimed &&
                card.name == name &&
                !const [
                  'completed',
                  'failed',
                ].contains(card.update['status']) &&
                _canonical(_arguments(card.update)) == _canonical(args),
          )
          .firstOrNull;
      if (card != null) {
        card.claimed = true;
        final cancellation = ToolCallCancellation(
          isCancelled: () => turn.cancelled.isCompleted,
          cancelled: turn.cancelled.future,
        );
        try {
          return await Future.any([
            cancellation.run(
              () => turn.tools.execute(
                name,
                args,
                toolCallId: AcpTurnTranslator.cardId(card.id),
              ),
            ),
            turn.cancelled.future.then(
              (_) => _error('The agent turn was cancelled.'),
            ),
          ]);
        } catch (_) {
          return _error('The Moru tool could not complete.');
        }
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        await turn.changed.future.timeout(remaining);
      } on TimeoutException {
        break;
      }
    }
    return _error(
      turn.cancelled.isCompleted
          ? 'The agent turn was cancelled.'
          : 'The agent did not send a matching Moru tool card.',
    );
  }

  Future<void> close() {
    endTurn();
    return server.close();
  }

  static Map<String, Object?> _error(String message) => {
    'isError': true,
    'content': [
      {'type': 'text', 'text': message},
    ],
  };

  static String? _toolName(Map<String, Object?> update) {
    final raw = update['rawInput'];
    if (raw is Map &&
        raw['server'] == 'moru' &&
        AcpMcpServer.allowedNames.contains(raw['tool'])) {
      return raw['tool'] as String;
    }
    final meta = update['_meta'];
    final claude = meta is Map ? meta['claudeCode'] : null;
    for (final candidate in [
      update['name'],
      update['title'],
      if (claude is Map) claude['toolName'],
    ]) {
      for (final name in AcpMcpServer.allowedNames) {
        if (candidate == 'mcp__moru__$name' ||
            candidate == 'moru_$name' ||
            candidate == 'Tool: moru/$name') {
          return name;
        }
      }
    }
    return null;
  }

  static Object? _arguments(Map<String, Object?> update) {
    final raw = update['rawInput'];
    return raw is Map && raw['server'] == 'moru' ? raw['arguments'] : raw;
  }

  static String _canonical(Object? value) {
    Object? sorted(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: sorted(value[key])};
      }
      if (value is List) return value.map(sorted).toList();
      return value;
    }

    return jsonEncode(sorted(value));
  }
}

class _McpTurn {
  _McpTurn(this.tools);
  final AcpMcpTools tools;
  final cards = <String, _McpCard>{};
  final cancelled = Completer<void>();
  Completer<void> changed = Completer<void>();
  void wake() {
    changed.complete();
    changed = Completer<void>();
  }
}

class _McpCard {
  _McpCard(this.id);
  final String id;
  final update = <String, Object?>{};
  String? name;
  bool claimed = false;
}
