import 'dart:convert';

import '../../../core/providers/settings_provider.dart';
import 'spend_control_service.dart';
import 'tool_approval_service.dart';

typedef SpendCompactHandler =
    Future<Map<String, dynamic>> Function(
      String conversationId, {
      required void Function() checkAllowed,
    });

/// Uses the ordinary tool approval card, with fresh consent for each change.
class SpendControlTool {
  SpendControlTool({
    required this.settings,
    required this.readStatus,
    required this.checkAllowed,
    this.approvals,
    this.compact,
  });

  static const toolName = 'spend_control';
  static const _clearable = [
    'chat_usd',
    'chat_tokens',
    'daily_usd',
    'daily_tokens',
  ];
  final SettingsProvider settings;
  final Future<SpendControlStatus> Function() readStatus;
  final void Function() checkAllowed;
  final ToolApprovalService? approvals;
  final Future<Map<String, dynamic>> Function()? compact;

  static bool requiresApproval(Map<String, dynamic> args) =>
      args['action'] == 'compact' || args['action'] == 'set_limits';

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Inspect chat and today\'s spending and context usage to save tokens before budgets run out. '
          'status reads all paid reply versions, with cached input included once and incomplete prices marked. '
          'Check status during long tasks; near the threshold reply briefly and offer compact or a new chat. '
          'used_percent compares each budget, cached_percent is the share of input, and current_response explains pending usage. '
          'compact uses the app\'s existing compression settings to create a summarized chat, preserving the original; '
          'the current reply still belongs to the original chat. set_limits edits global budgets. '
          'compact and set_limits require confirmation unless full trust is enabled. Dollar costs may be lower bounds; '
          'remaining dollars then are upper bounds. Budgets warn by default; hard_stop is opt-in.',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['status', 'compact', 'set_limits'],
          },
          'limits': {
            'type': 'object',
            'description':
                'set_limits only. Omitted fields keep their value; use clear to disable budgets.',
            'properties': {
              'chat_usd': {
                'type': 'number',
                'description': 'Positive USD per chat.',
              },
              'chat_tokens': {
                'type': 'integer',
                'description': 'Positive input + output tokens per chat.',
              },
              'daily_usd': {
                'type': 'number',
                'description':
                    'Positive USD for all chats today (device local day).',
              },
              'daily_tokens': {
                'type': 'integer',
                'description': 'Positive input + output tokens today.',
              },
              'warning_percent': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 100,
                'description': 'Warning threshold, default 80.',
              },
              'hard_stop': {
                'type': 'boolean',
                'description':
                    'Block new sends after a budget is exhausted; default false.',
              },
            },
            'additionalProperties': false,
          },
          'clear': {
            'type': 'array',
            'items': {'type': 'string', 'enum': _clearable},
            'description':
                'set_limits only: budgets to disable. Do not also set the same fields in limits.',
          },
        },
        'required': ['action'],
        'additionalProperties': false,
      },
    },
  };

  Future<String> execute(
    Map<String, dynamic> args, {
    required String toolCallId,
    required String? conversationId,
  }) async {
    String error(String code, String message) =>
        jsonEncode({'ok': false, 'error': code, 'message': message});
    try {
      checkAllowed();
      final action = args['action'];
      if (!['status', 'compact', 'set_limits'].contains(action) ||
          args.keys.any(
            (key) => !['action', 'limits', 'clear'].contains(key),
          )) {
        throw const FormatException('Use status, compact or set_limits.');
      }
      // Strict-mode function calling (e.g. ChatGPT sign-in) fills every
      // schema field, so status and compact ignore set_limits-only fields.
      if (action != 'set_limits') {
        args = {'action': action};
      }
      Map<String, dynamic>? changes;
      if (action == 'set_limits') {
        if (args.containsKey('limits') && args['limits'] is! Map) {
          throw const FormatException('limits must be an object.');
        }
        changes = args['limits'] is Map
            ? Map<String, dynamic>.from(args['limits'] as Map)
            : <String, dynamic>{};
        if (args.containsKey('clear')) {
          final clear = args['clear'];
          if (clear is! List) {
            throw const FormatException(
              'clear must be an array of budget names.',
            );
          }
          for (final key in clear) {
            if (key is! String ||
                !_clearable.contains(key) ||
                changes.containsKey(key)) {
              throw const FormatException(
                'Only clear supported budgets without conflicting edits.',
              );
            }
            changes[key] = null;
          }
        }
        settings.spendLimits.patch(changes);
      }
      if (action == 'compact' && compact == null) {
        return error(
          'compact_unavailable',
          'Context compression is unavailable in this chat.',
        );
      }
      if (requiresApproval(args) && !settings.toolAutoApproveAll) {
        final service = approvals;
        if (service == null) {
          return error(
            'approval_unavailable',
            'This change needs the user\'s confirmation.',
          );
        }
        service.setAutoApproveAll(false);
        final result = await service.requestApproval(
          toolCallId: toolCallId,
          toolName: toolName,
          arguments: args,
          conversationId: conversationId,
        );
        if (!result.approved) {
          return error(
            'approval_denied',
            result.denyReason ?? 'User denied the tool call.',
          );
        }
      }
      checkAllowed();
      if (action == 'compact') return jsonEncode(await compact!());
      if (changes != null) {
        await settings.setSpendLimits(settings.spendLimits.patch(changes));
      }
      final status = await readStatus();
      checkAllowed();
      return jsonEncode({'ok': true, ...status.toJson()});
    } on FormatException catch (e) {
      return error('invalid_arguments', e.message);
    } on StateError catch (e) {
      return error(
        e.message == 'permission_denied' ? 'permission_denied' : 'cancelled',
        'The tool is disabled or the calling reply is no longer active.',
      );
    }
  }
}
