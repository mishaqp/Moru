import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/services/tool_approval_service.dart';
import 'workspace_tool_ui.dart' show ToolApprovalButton;

String mcpManagerActionTitle(AppLocalizations l10n, String action) =>
    switch (action) {
      'list' => l10n.mcpManagerActionList,
      'get' => l10n.mcpManagerActionGet,
      'add' => l10n.mcpManagerActionAdd,
      'update' => l10n.mcpManagerActionUpdate,
      'enable' => l10n.mcpManagerActionEnable,
      'disable' => l10n.mcpManagerActionDisable,
      'remove' => l10n.mcpManagerActionRemove,
      'test' => l10n.mcpManagerActionTest,
      _ => l10n.mcpManagerToolTitle,
    };

/// Only the private result of consent receives these inputs, never arguments,
/// message parts, clipboard actions or the technical journal.
class McpManagementApproval extends StatefulWidget {
  const McpManagementApproval({
    super.key,
    required this.request,
    required this.onDeny,
  });
  final ToolApprovalRequest request;
  final VoidCallback onDeny;

  @override
  State<McpManagementApproval> createState() => _McpManagementApprovalState();
}

class _McpManagementApprovalState extends State<McpManagementApproval> {
  late final _inputs = {
    for (final name in widget.request.secretFields)
      name: TextEditingController(),
  };
  @override
  void dispose() {
    for (final controller in _inputs.values) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ready = _inputs.values.every(
      (c) => c.text.isNotEmpty && c.text.length <= 8192,
    );
    Widget description(Map server) {
      final rows = <String>[
        '${server['name']} · ${server['type'].toString().toUpperCase()}',
        server['enabled'] == true
            ? l10n.mcpServerEditSheetEnabledLabel
            : l10n.mcpPageStatusDisabled,
        if (server['command'] != null)
          '${l10n.mcpServerEditSheetStdioCommandLabel}: ${server['command']}',
        if (server['args'] is List && (server['args'] as List).isNotEmpty)
          '${l10n.mcpServerEditSheetStdioArgumentsLabel}: ${(server['args'] as List).join(' ')}',
        if (server['url'] != null)
          '${l10n.mcpServerEditSheetUrlLabel}: ${server['url']}',
        if (server['cwd'] != null)
          '${l10n.mcpServerEditSheetStdioWorkingDirectoryLabel}: ${server['cwd']}',
        if (server['workspaceId'] != null)
          '${l10n.mcpWorkspaceBindingLabel}: ${server['workspaceId']}',
        for (final field in ['env', 'headers'])
          if (server[field] is Map && (server[field] as Map).isNotEmpty)
            '${field == 'env' ? l10n.mcpServerEditSheetStdioEnvironmentTitle : l10n.mcpServerEditSheetCustomHeadersTitle}: ${(server[field] as Map).entries.map((e) => '${e.key} (${e.value is Map && e.value['value_set'] == true ? l10n.mcpManagerValueSet : l10n.mcpManagerValueNeeded})').join(', ')}',
      ];
      return Text(
        rows.join('\n'),
        style: const TextStyle(fontSize: 12, height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mcpManagerActionTitle(
            l10n,
            (widget.request.arguments['action'] ?? '').toString(),
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (widget.request.arguments['previous_server']
            case final Map previous) ...[
          const SizedBox(height: 6),
          Text(l10n.mcpManagerPrevious),
          description(previous),
        ],
        if (widget.request.arguments['server'] case final Map server) ...[
          const SizedBox(height: 6),
          description(server),
        ],
        if (_inputs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l10n.mcpManagerSecretHint, style: const TextStyle(fontSize: 12)),
          for (final entry in _inputs.entries)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: ValueKey('mcp-secret:${entry.key}'),
                controller: entry.value,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                maxLength: 8192,
                decoration: InputDecoration(
                  labelText: entry.key,
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ToolApprovalButton(
                label: l10n.toolApprovalDeny,
                color: cs.error,
                filled: false,
                onTap: widget.onDeny,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ToolApprovalButton(
                label: l10n.toolApprovalApprove,
                color: cs.primary,
                filled: true,
                onTap: !ready
                    ? null
                    : () {
                        context.read<ToolApprovalService>().approve(
                          widget.request.toolCallId,
                          conversationId: widget.request.conversationId,
                          secretValues: {
                            for (final entry in _inputs.entries)
                              entry.key: entry.value.text,
                          },
                        );
                        for (final controller in _inputs.values) {
                          controller.clear();
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
