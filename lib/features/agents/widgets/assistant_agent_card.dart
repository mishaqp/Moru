import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/agent_auth_mode.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/acp/acp_agent_catalog.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../agent_provider_compatibility.dart';
import '../pages/agents_page.dart';
import '../pages/agent_subscription_page.dart';
import 'agent_labels.dart';
import 'agent_auth_mode_row.dart';

/// Picks the ACP agent that answers for [assistant], or none (the model
/// answers itself).
class AssistantAgentCard extends StatelessWidget {
  const AssistantAgentCard({super.key, required this.assistant});

  final Assistant assistant;

  static const Key rowKey = ValueKey('assistant-agent-row');
  static const Key authModeKey = ValueKey('assistant-agent-auth-mode');
  static const Key subscriptionKey = ValueKey('assistant-agent-subscription');

  ProviderConfig? _provider(SettingsProvider settings) {
    final key = assistant.chatModelProvider ?? settings.currentModelProvider;
    return key == null ? null : settings.getProviderConfig(key);
  }

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
      footer:
          assistant.agentAuthMode == AgentAuthMode.provider &&
              agentNeedsResponsesApiWarning(
                AcpAgentSpec.codexId,
                _provider(context.read<SettingsProvider>()),
              )
          ? IosSectionFooter(text: l10n.agentsCodexResponsesRequired)
          : null,
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
          : current.copyWith(
              agentId: choice,
              agentAuthMode: manager.agent(choice)?.supportsSubscription == true
                  ? current.agentAuthMode
                  : AgentAuthMode.provider,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final manager = context.watch<AcpAgentManager>();
    final settings = context.watch<SettingsProvider>();
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
            if (spec?.supportsSubscription == true) ...[
              const IosRowDivider(),
              AgentAuthModeRow(
                key: authModeKey,
                mode: assistant.agentAuthMode,
                onSelected: (mode) async {
                  final assistants = context.read<AssistantProvider>();
                  final current = assistants.getById(assistant.id);
                  if (current == null) return;
                  await assistants.updateAssistant(
                    current.copyWith(agentAuthMode: mode),
                  );
                },
              ),
              if (manager.state(spec!.id) == AcpInstallState.installed) ...[
                const IosRowDivider(),
                IosNavRow(
                  key: subscriptionKey,
                  icon: LucideIcons.userRound,
                  label: l10n.agentsAuthTitle,
                  subtitle: agentAuthStatusLabel(
                    l10n,
                    manager.auth.status(spec.id),
                  ),
                  onTap: () {
                    final assistants = context.read<AssistantProvider>();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AgentSubscriptionPage(
                          agentId: spec.id,
                          onSignIn: () async {
                            final current = assistants.getById(assistant.id);
                            if (current == null || current.agentId != spec.id) {
                              throw StateError('Agent assistant unavailable');
                            }
                            await assistants.updateAssistant(
                              current.copyWith(
                                agentAuthMode: AgentAuthMode.subscription,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
        IosSectionFooter(
          text:
              spec?.supportsSubscription == true &&
                  assistant.agentAuthMode == AgentAuthMode.subscription
              ? l10n.agentsAuthSubscriptionHint
              : l10n.assistantAgentHint,
        ),
        if (assistant.agentAuthMode == AgentAuthMode.provider &&
            agentNeedsResponsesApiWarning(id, _provider(settings)))
          IosSectionFooter(text: l10n.agentsCodexResponsesRequired),
      ],
    );
  }
}
