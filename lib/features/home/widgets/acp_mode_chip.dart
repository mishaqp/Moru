import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/acp/acp_chat_sessions.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../services/acp_chat_bridge.dart';

/// Modes offered by the live agent. The choice is applied before the next turn.
class AcpModeChip extends StatelessWidget {
  const AcpModeChip({super.key, required this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<AcpChatSessions>();
    final chats = context.watch<ChatService>();
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final id = conversationId;
        final session = sessions.sessionFor(id);
        if (id == null || session == null || session.modes.isEmpty) {
          return const SizedBox.shrink();
        }
        final saved = chats.getConversation(id)?.extras[acpModeKey];
        final selected = session.modes.any((m) => m.id == saved)
            ? saved as String
            : session.currentModeId;
        final mode = session.modes.where((m) => m.id == selected).firstOrNull;
        final l10n = AppLocalizations.of(context)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: IosTileButton(
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
                id,
                (extras) => extras..[acpModeKey] = choice,
              );
            },
          ),
        );
      },
    );
  }
}
