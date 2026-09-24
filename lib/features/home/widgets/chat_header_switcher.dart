import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/pages/webview/browser_mini_window.dart';
import '../../workspace/workspace_navigation.dart';

/// A compact pill in the chat header jumping to the conversation's
/// workspace files and terminal, and to the shared browser. Files and
/// terminal appear only when the chat has a workspace; the browser segment
/// is highlighted while the browser runs minimized.
class ChatHeaderSwitcher extends StatelessWidget {
  const ChatHeaderSwitcher({super.key});

  static const Key filesKey = ValueKey<String>('chat-header-files');
  static const Key terminalKey = ValueKey<String>('chat-header-terminal');
  static const Key browserKey = ValueKey<String>('chat-header-browser');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final workspaceBound = context.select<ChatService?, bool>((chat) {
      final id = chat?.currentConversationId;
      final conversation = id == null ? null : chat!.getConversation(id);
      return conversation != null &&
          WorkspaceBinding.fromExtras(conversation.extras).isBound;
    });

    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (workspaceBound) ...[
            _Segment(
              key: filesKey,
              icon: Lucide.Braces,
              tooltip: l10n.chatHeaderFiles,
              onTap: () => WorkspaceNavigation.openWorkspaceFiles(context),
            ),
            _Segment(
              key: terminalKey,
              icon: Lucide.SquareTerminal,
              tooltip: l10n.chatHeaderTerminal,
              onTap: () => WorkspaceNavigation.openTerminal(context),
            ),
          ],
          ValueListenableBuilder<bool>(
            valueListenable: BrowserAgentSession.instance.minimized,
            builder: (context, minimized, _) => _Segment(
              key: browserKey,
              icon: Lucide.Globe,
              tooltip: l10n.chatHeaderBrowser,
              active: minimized,
              onTap: () => unawaited(openSharedBrowser()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 30,
            child: Icon(
              icon,
              size: 17,
              semanticLabel: tooltip,
              color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}
