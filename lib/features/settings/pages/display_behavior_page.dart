part of 'display_settings_page.dart';

class BehaviorStartupSettingsPage extends StatelessWidget {
  const BehaviorStartupSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    // Rebuild only for the settings this page shows.
    context.select<SettingsProvider, Object>(
      (s) => (
        s.autoCollapseThinking,
        s.collapseLongUserMessageChars,
        s.collapseLongUserMessages,
        s.collapseThinkingSteps,
        s.enterToSendOnMobile,
        s.forkKeepMessageVersions,
        s.hideToolResultImages,
        s.insertSuggestionOnTapOnly,
        s.keepAssistantListExpandedOnSidebarClose,
        s.keepScreenOnDuringGeneration,
        s.keepSidebarOpenOnAssistantTap,
        s.keepSidebarOpenOnTopicTap,
        s.keepThinkingAndToolCardsWhenEditingAssistant,
        s.longPasteAsFile,
        s.longPasteAsFileThreshold,
        s.mobileMessageNavButtonsMode,
        s.newChatAfterDelete,
        s.newChatOnAssistantSwitch,
        s.newChatOnLaunch,
        s.regenerateDeleteTrailingMessages,
        s.showAppUpdates,
        s.showChatListDate,
        s.showRegenerateConfirmDialog,
        s.showToolResultSummary,
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
        title: Text(l10n.displaySettingsPageBehaviorStartupTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          SectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Brain,
                label: l10n.displaySettingsPageAutoCollapseThinkingTitle,
                value: sp.autoCollapseThinking,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setAutoCollapseThinking(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ListTree,
                label: l10n.displaySettingsPageCollapseThinkingStepsTitle,
                value: sp.collapseThinkingSteps,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setCollapseThinkingSteps(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FileText,
                label: l10n.displaySettingsPageShowToolResultSummaryTitle,
                value: sp.showToolResultSummary,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowToolResultSummary(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ImageOff,
                label: l10n.displaySettingsPageHideToolResultImagesTitle,
                value: sp.hideToolResultImages,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHideToolResultImages(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.TextSelect,
                label: l10n.displaySettingsPageInsertSuggestionOnlyTitle,
                value: sp.insertSuggestionOnTapOnly,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setInsertSuggestionOnTapOnly(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FoldVertical,
                label: l10n.displaySettingsPageCollapseLongUserMessagesTitle,
                tip: l10n.displaySettingsPageCollapseLongUserMessagesSubtitle,
                value: sp.collapseLongUserMessages,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setCollapseLongUserMessages(v),
              ),
              if (sp.collapseLongUserMessages) ...[
                _iosDivider(context),
                _NumberFieldRow(
                  icon: Lucide.ListOrdered,
                  label: l10n
                      .displaySettingsPageCollapseLongUserMessagesCharsTitle,
                  unit:
                      l10n.displaySettingsPageCollapseLongUserMessagesCharsUnit,
                  value: sp.collapseLongUserMessageChars,
                  min: SettingsProvider.minCollapseLongUserMessageChars,
                  max: SettingsProvider.maxCollapseLongUserMessageChars,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setCollapseLongUserMessageChars(v),
                ),
              ],
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.RefreshCw,
                label: l10n
                    .displaySettingsPageRegenerateDeleteTrailingMessagesTitle,
                value: sp.regenerateDeleteTrailingMessages,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setRegenerateDeleteTrailingMessages(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageCircleWarning,
                label: l10n.displaySettingsPageShowRegenerateConfirmDialogTitle,
                value: sp.showRegenerateConfirmDialog,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowRegenerateConfirmDialog(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.GitFork,
                label: l10n.displaySettingsPageForkKeepMessageVersionsTitle,
                value: sp.forkKeepMessageVersions,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setForkKeepMessageVersions(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Pencil,
                label: l10n
                    .displaySettingsPageEditAssistantKeepThinkingToolCardsTitle,
                tip: l10n
                    .displaySettingsPageEditAssistantKeepThinkingToolCardsSubtitle,
                value: sp.keepThinkingAndToolCardsWhenEditingAssistant,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepThinkingAndToolCardsWhenEditingAssistant(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.BadgeInfo,
                label: l10n.displaySettingsPageShowUpdatesTitle,
                value: sp.showAppUpdates,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowAppUpdates(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Sun,
                label:
                    l10n.displaySettingsPageKeepScreenOnDuringGenerationTitle,
                tip: l10n
                    .displaySettingsPageKeepScreenOnDuringGenerationSubtitle,
                value: sp.keepScreenOnDuringGeneration,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepScreenOnDuringGeneration(v),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.ChevronRight,
                label: l10n.displaySettingsPageMessageNavButtonsTitle,
                detailBuilder: (_) =>
                    Text(switch (sp.mobileMessageNavButtonsMode) {
                      MobileMessageNavButtonsMode.always =>
                        l10n.displaySettingsPageMessageNavButtonsModeAlways,
                      MobileMessageNavButtonsMode.scroll =>
                        l10n.displaySettingsPageMessageNavButtonsModeScroll,
                      MobileMessageNavButtonsMode.never =>
                        l10n.displaySettingsPageMessageNavButtonsModeNever,
                    }),
                onTap: () => _showMobileMessageNavModeSheet(context),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Calendar,
                label: l10n.displaySettingsPageShowChatListDateTitle,
                value: sp.showChatListDate,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowChatListDate(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.panelLeft,
                label:
                    l10n.displaySettingsPageKeepSidebarOpenOnAssistantTapTitle,
                value: sp.keepSidebarOpenOnAssistantTap,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepSidebarOpenOnAssistantTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ListTree,
                label: l10n.displaySettingsPageKeepSidebarOpenOnTopicTapTitle,
                value: sp.keepSidebarOpenOnTopicTap,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepSidebarOpenOnTopicTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.UnfoldVertical,
                label: l10n
                    .displaySettingsPageKeepAssistantListExpandedOnSidebarCloseTitle,
                value: sp.keepAssistantListExpandedOnSidebarClose,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepAssistantListExpandedOnSidebarClose(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Shuffle,
                label: l10n.displaySettingsPageNewChatOnAssistantSwitchTitle,
                value: sp.newChatOnAssistantSwitch,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setNewChatOnAssistantSwitch(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Trash2,
                label: l10n.displaySettingsPageNewChatAfterDeleteTitle,
                value: sp.newChatAfterDelete,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setNewChatAfterDelete(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageCirclePlus,
                label: l10n.displaySettingsPageNewChatOnLaunchTitle,
                value: sp.newChatOnLaunch,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setNewChatOnLaunch(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.CornerDownLeft,
                label: l10n.displaySettingsPageEnterToSendTitle,
                value: sp.enterToSendOnMobile,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnterToSendOnMobile(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Clipboard,
                label: l10n.displaySettingsPageLongPasteAsFileTitle,
                value: sp.longPasteAsFile,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setLongPasteAsFile(v),
              ),
              if (sp.longPasteAsFile) ...[
                _iosDivider(context),
                const _LongPasteAsFileThresholdRow(),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LongPasteAsFileThresholdRow extends StatefulWidget {
  const _LongPasteAsFileThresholdRow();

  @override
  State<_LongPasteAsFileThresholdRow> createState() =>
      _LongPasteAsFileThresholdRowState();
}

class _LongPasteAsFileThresholdRowState
    extends State<_LongPasteAsFileThresholdRow> {
  late final SettingsProvider _settings;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsProvider>();
    _controller = TextEditingController(
      text: '${_settings.longPasteAsFileThreshold}',
    );
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) _commit();
      });
  }

  @override
  void dispose() {
    // Back / toggling the switch often skips unfocus on mobile.
    _commit(syncField: false);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit({bool syncField = true}) {
    final next = SettingsProvider.resolveLongPasteAsFileThreshold(
      _controller.text,
      fallback: _settings.longPasteAsFileThreshold,
    );
    _settings.setLongPasteAsFileThreshold(next);
    if (!syncField) return;
    final text = '$next';
    if (_controller.text != text) {
      _controller.value = _controller.value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final threshold = context.select<SettingsProvider, int>(
      (s) => s.longPasteAsFileThreshold,
    );

    if (!_focusNode.hasFocus) {
      final t = '$threshold';
      if (_controller.text != t) _controller.text = t;
    }

    final baseColor = cs.onSurface.withValues(alpha: 0.9);
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.28),
        width: 0.8,
      ),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary, width: 1.0),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Icon(Lucide.ListOrdered, size: 20, color: baseColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.displaySettingsPageLongPasteAsFileThresholdTitle,
              style: TextStyle(fontSize: 15, color: baseColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56, maxWidth: 96),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: context.appColors.surfaceCard,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: baseBorder,
                  enabledBorder: baseBorder,
                  focusedBorder: focusBorder,
                ),
                onChanged: (_) => _commit(syncField: false),
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.displaySettingsPageLongPasteAsFileThresholdUnit,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
