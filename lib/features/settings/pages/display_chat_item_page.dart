part of 'display_settings_page.dart';

class ChatItemDisplaySettingsPage extends StatelessWidget {
  const ChatItemDisplaySettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    // Rebuild only for the settings this page shows.
    context.select<SettingsProvider, Object>(
      (s) => (
        s.showModelIcon,
        s.showModelName,
        s.showModelTimestamp,
        s.showProducedFiles,
        s.showProviderInChatMessage,
        s.showThinkingCards,
        s.showTokenStats,
        s.showToolCards,
        s.showUserAvatar,
        s.showUserMessageActions,
        s.showUserName,
        s.showUserTimestamp,
        s.useNewAssistantAvatarUx,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.displaySettingsPageChatItemDisplayTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          SectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.User,
                label: l10n.displaySettingsPageShowUserAvatarTitle,
                value: sp.showUserAvatar,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowUserAvatar(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.IdCard,
                label: l10n.displaySettingsPageShowUserNameTitle,
                value: sp.showUserName,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowUserName(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.clock,
                label: l10n.displaySettingsPageShowUserTimestampTitle,
                value: sp.showUserTimestamp,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowUserTimestamp(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Ellipsis,
                label: l10n.displaySettingsPageShowUserMessageActionsTitle,
                value: sp.showUserMessageActions,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowUserMessageActions(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Bot,
                label: l10n.displaySettingsPageChatModelIconTitle,
                value: sp.showModelIcon,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowModelIcon(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.PanelTop,
                label: l10n.displaySettingsPageUseNewAssistantAvatarUxTitle,
                value: sp.useNewAssistantAvatarUx,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setUseNewAssistantAvatarUx(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Tag,
                label: l10n.displaySettingsPageShowModelNameTitle,
                value: sp.showModelName,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowModelName(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.clock,
                label: l10n.displaySettingsPageShowModelTimestampTitle,
                value: sp.showModelTimestamp,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowModelTimestamp(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Globe,
                label: l10n.displaySettingsPageShowProviderInChatMessageTitle,
                value: sp.showProviderInChatMessage,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowProviderInChatMessage(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Gauge,
                label: l10n.displaySettingsPageShowTokenStatsTitle,
                value: sp.showTokenStats,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowTokenStats(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Sparkles,
                label: l10n.displaySettingsPageShowThinkingCardsTitle,
                tip: l10n.displaySettingsPageShowThinkingCardsSubtitle,
                value: sp.showThinkingCards,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowThinkingCards(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Wrench,
                label: l10n.displaySettingsPageShowToolCardsTitle,
                tip: l10n.displaySettingsPageShowToolCardsSubtitle,
                value: sp.showToolCards,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowToolCards(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FileText,
                label: l10n.displaySettingsPageShowProducedFilesTitle,
                tip: l10n.displaySettingsPageShowProducedFilesSubtitle,
                value: sp.showProducedFiles,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowProducedFiles(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
