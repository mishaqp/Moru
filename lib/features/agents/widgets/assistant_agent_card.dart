import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../pages/agents_page.dart';
import 'agent_labels.dart';

/// Picks the ACP agent that answers for [assistant], or none (the model
/// answers itself).
class AssistantAgentCard extends StatelessWidget {
  const AssistantAgentCard({super.key, required this.assistant});

  final Assistant assistant;

  static const Key rowKey = ValueKey('assistant-agent-row');

  Future<void> _choose(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final manager = context.read<AcpAgentManager>();
    final assistants = context.read<AssistantProvider>();
    await manager.loaded;
    if (!context.mounted) return;
    const none = '\u0000none';
    const manage = '\u0000manage';
    final choice = await showOptionSheet<String>(
      context,
      title: l10n.assistantAgentTitle,
      selected: assistant.agentId ?? none,
      items: [
        OptionSheetItem(
          value: none,
          icon: LucideIcons.messageCircle,
          label: l10n.assistantAgentNone,
        ),
        for (final spec in manager.agents)
          OptionSheetItem(
            value: spec.id,
            icon: agentIcon(spec),
            label: spec.name,
          ),
        OptionSheetItem(
          value: manage,
          icon: LucideIcons.settings2,
          label: l10n.agentsTitle,
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == manage) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AgentsPage()));
      return;
    }
    final current = assistants.getById(assistant.id);
    if (current == null) return;
    await assistants.updateAssistant(
      choice == none
          ? current.copyWith(clearAgent: true)
          : current.copyWith(agentId: choice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final manager = context.watch<AcpAgentManager>();
    final id = assistant.agentId;
    final spec = id == null ? null : manager.agent(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          children: [
            IosNavRow(
              key: rowKey,
              icon: spec == null ? LucideIcons.bot : agentIcon(spec),
              label: l10n.assistantAgentTitle,
              detailText: id == null
                  ? l10n.assistantAgentNone
                  : (spec?.name ?? id),
              onTap: () => unawaited(_choose(context)),
            ),
          ],
        ),
        IosSectionFooter(text: l10n.assistantAgentHint),
      ],
    );
  }
}
