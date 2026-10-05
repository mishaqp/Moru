import 'dart:async';

import '../../../utils/authentication_uri.dart';
import '../api/tool_call_cancellation.dart';
import '../api/tool_display_redaction.dart';
import 'acp_agent.dart';
import 'acp_mcp_server.dart';
import 'acp_mcp_stdio_bridge.dart';
import 'acp_turn_translator.dart';
import 'acp_tool_correlation.dart';
import 'acp_secret_redactor.dart';

/// Live tool policy and the existing model handler for one assistant/chat.
class AcpMcpTools {
  const AcpMcpTools({
    required this.key,
    required this.definitions,
    required this.execute,
    this.cancelApproval,
    this.miniAppActionNames,
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
  final Set<String> Function()? miniAppActionNames;
}

/// Matches HTTP calls to the cards the agent already streams over ACP.
class AcpMcpBinding {
  AcpMcpBinding._(this._tools, this.redactor);

  AcpMcpTools _tools;
  final AcpSecretRedactor? redactor;
  late final AcpMcpServer server;
  _McpTurn? _turn;

  static Future<AcpMcpBinding> start(
    AcpMcpTools tools, {
    AcpSecretRedactor? redactor,
  }) async {
    final binding = AcpMcpBinding._(tools, redactor);
    binding.server = await AcpMcpServer.start(
      tools: () => binding._tools.definitions(),
      callTool: binding.callTool,
      miniAppActionNames: () =>
          binding._tools.miniAppActionNames?.call() ?? const {},
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
      turn.tools.cancelApproval?.call(
        AcpTurnTranslator.cardId(card.id, redactor: redactor),
      );
    }
  }

  void observe(Map<String, Object?> update) {
    final correlation = AcpToolCorrelation.fromUpdate(update);
    if (correlation != null) observeCorrelation(correlation);
  }

  void observeCorrelation(AcpToolCorrelation correlation) {
    final turn = _turn;
    if (turn == null) return;
    final card = turn.cards.putIfAbsent(
      correlation.id,
      () => _McpCard(correlation.id),
    );
    // Running updates can replace a machine-readable title with a human one.
    card.name ??= correlation.resolveToolName(
      miniAppActionNames: _tools.miniAppActionNames?.call() ?? const {},
    );
    if (correlation.argumentsDigest != null) {
      card.argumentsDigest = correlation.argumentsDigest;
    }
    if (correlation.status != null) card.status = correlation.status;
    turn.wake();
  }

  bool ownsPermission(AcpPermissionRequest request) =>
      _turn?.cards.values.any(
        (card) =>
            card.name != null &&
            _allowsToolName(card.name!) &&
            AcpTurnTranslator.cardId(card.id, redactor: redactor) ==
                request.toolCallId,
      ) ==
      true;

  bool _allowsToolName(String name) =>
      AcpMcpServer.allowedNames.contains(name) ||
      (name.startsWith('ma_') &&
          (_tools.miniAppActionNames?.call().contains(name) ?? false));

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
    if (!_allowsToolName(name)) return _error('This Moru tool is unavailable.');
    if (name == 'browser_use' &&
        redactor?.protectAuthentication == true &&
        _containsAuthenticationUri(args)) {
      // Authorization belongs to the Settings flow's external browser. Do
      // not let WebView navigation, console or activity journals see its URL.
      return _error(
        'Open Settings > Agents to sign in. '
        'Authentication pages cannot be opened by browser_use.',
      );
    }
    final digest = AcpToolCorrelation.digest(args);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!turn.cancelled.isCompleted) {
      if (!_allowsToolName(name)) {
        return _error('This Moru tool is unavailable.');
      }
      final card = turn.cards.values
          .where(
            (card) =>
                !card.claimed &&
                card.name == name &&
                !const ['completed', 'failed'].contains(card.status) &&
                card.argumentsDigest == digest,
          )
          .firstOrNull;
      if (card != null) {
        card.claimed = true;
        final cancellation = ToolCallCancellation(
          isCancelled: () => turn.cancelled.isCompleted,
          cancelled: turn.cancelled.future,
        );
        try {
          Future<Map<String, Object?>> execute() => cancellation.run(
            () => turn.tools.execute(
              name,
              args,
              toolCallId: AcpTurnTranslator.cardId(card.id, redactor: redactor),
            ),
          );
          return await Future.any([
            if (redactor case final filter?)
              ToolDisplayRedaction(
                text: filter.text,
                value: filter.value,
              ).run(execute)
            else
              execute(),
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

  static final _webAddress = RegExp(
    r'''https?://[^\s<>"'`\\]+''',
    caseSensitive: false,
  );
  static final _addressPunctuation = RegExp(r'[)\]},.;!?]+$');

  static bool _containsAuthenticationUri(Object? value) {
    if (value is Map) {
      return value.values.any(_containsAuthenticationUri);
    }
    if (value is Iterable) {
      return value.any(_containsAuthenticationUri);
    }
    if (value is! String) return false;
    final text = value.replaceAll(r'\/', '/');
    for (final match in _webAddress.allMatches(text)) {
      final address = match.group(0)!.replaceFirst(_addressPunctuation, '');
      final uri = Uri.tryParse(address);
      if (uri != null && isAuthenticationUri(uri)) return true;
    }
    return false;
  }

  static Map<String, Object?> _error(String message) => {
    'isError': true,
    'content': [
      {'type': 'text', 'text': message},
    ],
  };
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
  String? argumentsDigest;
  String? status;
  String? name;
  bool claimed = false;
}
