import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/services/acp/acp_agent_catalog.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../widgets/agent_labels.dart';
import 'agent_detail_page.dart';

/// Coding agents (Claude Code, Codex, OpenCode, your own) that answer in
/// Moru's chats: which are installed, and a way to install or add one.
class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  @override
  void initState() {
    super.initState();
    final manager = context.read<AcpAgentManager>();
    unawaited(manager.loaded.then((_) => manager.refresh()));
  }

  Future<void> _addCustom() async {
    final spec = await showCustomAgentDialog(context);
    if (spec == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgentDetailPage(agentId: spec.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final manager = context.watch<AcpAgentManager>();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.agentsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              l10n.agentsIntro,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          IosSectionHeader(text: l10n.agentsSection),
          SectionCard(
            children: [
              for (final (index, spec) in manager.agents.indexed) ...[
                if (index > 0) const IosRowDivider(),
                IosNavRow(
                  key: ValueKey('agent-row-${spec.id}'),
                  icon: agentIcon(spec),
                  label: spec.name,
                  subtitle: agentSummary(l10n, spec),
                  subtitleMaxLines: 2,
                  detailText: agentStatusLabel(l10n, manager, spec),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AgentDetailPage(agentId: spec.id),
                    ),
                  ),
                ),
              ],
              const IosRowDivider(),
              IosNavRow(
                key: const ValueKey('agent-add-custom'),
                icon: LucideIcons.plus,
                label: l10n.agentsCustomAdd,
                trailing: const SizedBox.shrink(),
                onTap: () => unawaited(_addCustom()),
              ),
            ],
          ),
          IosSectionFooter(
            text: manager.environmentAvailable
                ? l10n.agentsFooter
                : l10n.agentsNeedEnvironment,
          ),
        ],
      ),
    );
  }
}

/// Asks for a name and a command; saves and returns the agent, or null.
Future<AcpAgentSpec?> showCustomAgentDialog(
  BuildContext context, {
  AcpAgentSpec? existing,
}) async {
  final manager = context.read<AcpAgentManager>();
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _CustomAgentDialog(existing: existing),
  );
  if (result == null) return null;
  final (name, commandLine) = result;
  final words = splitCommandLine(commandLine);
  if (words.isEmpty) return null;
  return manager.saveCustomAgent(
    id: existing?.id,
    name: name.isEmpty ? words.first : name,
    command: words.first,
    arguments: words.skip(1).toList(),
  );
}

/// Splits `goose acp --flag "a b"` into words, honouring quotes.
List<String> splitCommandLine(String line) {
  final words = <String>[];
  final current = StringBuffer();
  String? quote;
  var hasWord = false;
  for (final char in line.trim().split('')) {
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        current.write(char);
      }
    } else if (char == '"' || char == "'") {
      quote = char;
      hasWord = true;
    } else if (char.trim().isEmpty) {
      if (hasWord || current.isNotEmpty) {
        words.add(current.toString());
        current.clear();
        hasWord = false;
      }
    } else {
      current.write(char);
    }
  }
  if (hasWord || current.isNotEmpty) words.add(current.toString());
  return words;
}

class _CustomAgentDialog extends StatefulWidget {
  const _CustomAgentDialog({this.existing});

  final AcpAgentSpec? existing;

  @override
  State<_CustomAgentDialog> createState() => _CustomAgentDialogState();
}

class _CustomAgentDialogState extends State<_CustomAgentDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _command = TextEditingController(
    text: widget.existing == null
        ? ''
        : [widget.existing!.command, ...widget.existing!.arguments].join(' '),
  );

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.agentsCustomAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('agent-custom-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.agentsCustomName),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('agent-custom-command'),
            controller: _command,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.agentsCustomCommand,
              hintText: 'goose acp',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.agentsCustomHint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.agentsCancel),
        ),
        TextButton(
          onPressed: () {
            if (_command.text.trim().isEmpty) return;
            Navigator.of(context).pop((_name.text.trim(), _command.text));
          },
          child: Text(l10n.agentsSave),
        ),
      ],
    );
  }
}
