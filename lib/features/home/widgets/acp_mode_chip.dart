import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/acp/acp_agent.dart';
import '../../../core/services/acp/acp_chat_sessions.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../services/acp_chat_bridge.dart';

/// Modes and session options (model, reasoning effort) offered by the live
/// agent. A choice is applied before the next turn.
class AcpModeChip extends StatelessWidget {
  const AcpModeChip({
    super.key,
    required this.conversationId,
    required this.assistantId,
  });

  final String? conversationId;
  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<AcpChatSessions>();
    final chats = context.watch<ChatService>();
    final assistants = context.watch<AssistantProvider>();
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final id = conversationId;
        final session = sessions.sessionFor(id);
        if (id == null || session == null) return const SizedBox.shrink();
        final options = sessions.configOptionsFor(id);
        final assistant = assistantId == null
            ? null
            : assistants.getById(assistantId!);
        if (session.modes.isEmpty && (options.isEmpty || assistant == null)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (session.modes.isNotEmpty)
                _ModeButton(conversationId: id, session: session, chats: chats),
              if (options.isNotEmpty && assistant != null)
                _ConfigButton(
                  options: options,
                  assistant: assistant,
                  assistants: assistants,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.conversationId,
    required this.session,
    required this.chats,
  });

  final String conversationId;
  final AcpSession session;
  final ChatService chats;

  @override
  Widget build(BuildContext context) {
    final saved = chats.getConversation(conversationId)?.extras[acpModeKey];
    final selected = session.modes.any((m) => m.id == saved)
        ? saved as String
        : session.currentModeId;
    final mode = session.modes.where((m) => m.id == selected).firstOrNull;
    final l10n = AppLocalizations.of(context)!;
    return IosTileButton(
      key: const ValueKey('acp-mode-chip'),
      label: mode?.name ?? l10n.agentsMode,
      icon: Lucide.SlidersHorizontal,
      fontSize: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onTap: () async {
        final choice = await showOptionSheet<String>(
          context,
          title: l10n.agentsMode,
          selected: selected,
          items: [
            for (final mode in session.modes)
              OptionSheetItem(
                value: mode.id,
                label: mode.name,
                subtitle: mode.description,
              ),
          ],
        );
        if (choice == null || !context.mounted) return;
        await chats.updateConversationExtras(
          conversationId,
          (extras) => extras..[acpModeKey] = choice,
        );
      },
    );
  }
}

/// The assistant keeps the choice, so its next chats start with it too.
class _ConfigButton extends StatelessWidget {
  const _ConfigButton({
    required this.options,
    required this.assistant,
    required this.assistants,
  });

  final List<AcpConfigOption> options;
  final Assistant assistant;
  final AssistantProvider assistants;

  /// The saved choice while the agent still offers it, else its own value.
  AcpConfigValue? _selected(AcpConfigOption option) {
    final saved = assistant.agentConfig[option.id];
    return option.values.where((v) => v.value == saved).firstOrNull ??
        option.current;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const shown = {AcpConfigOption.modelCategory, 'thought_level'};
    final label = [
      for (final option in options)
        if (shown.contains(option.category)) _selected(option)?.name,
    ].nonNulls.join(' · ');
    return IosTileButton(
      key: const ValueKey('acp-config-chip'),
      label: label.isEmpty ? l10n.agentsSessionOptions : label,
      icon: Lucide.Brain,
      fontSize: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onTap: () async {
        final option = options.length == 1
            ? options.single
            : await showOptionSheet<AcpConfigOption>(
                context,
                title: l10n.agentsSessionOptions,
                items: [
                  for (final option in options)
                    OptionSheetItem(
                      key: ValueKey('acp-config-${option.id}'),
                      value: option,
                      label: option.name,
                      subtitle: _selected(option)?.name,
                    ),
                ],
              );
        if (option == null || !context.mounted) return;
        final choice = await showOptionSheet<String>(
          context,
          title: option.name,
          selected: _selected(option)?.value,
          items: [
            for (final value in option.values)
              OptionSheetItem(
                key: ValueKey('acp-config-value-${value.value}'),
                value: value.value,
                label: value.name,
                subtitle: value.description,
              ),
          ],
        );
        if (choice == null || !context.mounted) return;
        final current = assistants.getById(assistant.id);
        if (current == null) return;
        await assistants.updateAssistant(
          current.copyWith(
            agentConfig: {...current.agentConfig, option.id: choice},
          ),
        );
      },
    );
  }
}
