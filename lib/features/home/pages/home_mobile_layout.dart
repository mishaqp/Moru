import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/interactive_drawer.dart';
import '../widgets/side_drawer.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../chat/widgets/frosted/chat_frosted_backdrop.dart';
import '../../chat/widgets/chat_assistant_background.dart';
import '../widgets/assistant_avatar.dart';
import '../widgets/assistant_entry_actions.dart';
import '../widgets/chat_header_switcher.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

/// Height of the name · model line under the header switcher.
const double kChatHeaderTitleLineHeight = 22;

/// Full chat header height below the status bar.
const double kChatHeaderHeight = kToolbarHeight + kChatHeaderTitleLineHeight;

/// Mobile layout scaffold for the home page
/// This widget handles only the structural layout - AppBar, drawer, body structure
/// All message list rendering and input bar logic remain in home_page.dart
class HomeMobileScaffold extends StatelessWidget {
  static const Key modelLineKey = ValueKey<String>('chat-header-model');

  const HomeMobileScaffold({
    super.key,
    required this.scaffoldKey,
    required this.drawerController,
    required this.assistantPickerCloseTick,
    required this.loadingConversationIds,
    required this.title,
    required this.providerName,
    required this.modelDisplay,
    required this.onToggleDrawer,
    required this.onDismissKeyboard,
    required this.onSelectConversation,
    required this.onNewConversation,
    required this.onOpenMiniMap,
    required this.onCreateNewConversation,
    required this.onToggleTemporaryConversation,
    required this.onSelectModel,
    required this.canToggleTemporaryConversation,
    required this.temporaryConversationEnabled,
    required this.globalSearchMode,
    required this.globalSearchQuery,
    required this.onGlobalSearchQueryChanged,
    required this.onEnterGlobalSearch,
    required this.onExitGlobalSearch,
    required this.onOpenGlobalSearchResult,
    this.appBarOverride,
    required this.body,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final InteractiveDrawerController drawerController;
  final ValueNotifier<int> assistantPickerCloseTick;
  final Set<String> loadingConversationIds;
  final String title;
  final String? providerName;
  final String? modelDisplay;
  final VoidCallback onToggleDrawer;
  final VoidCallback onDismissKeyboard;
  final void Function(String id) onSelectConversation;
  final VoidCallback onNewConversation;
  final VoidCallback onOpenMiniMap;
  final Future<void> Function() onCreateNewConversation;
  final Future<void> Function() onToggleTemporaryConversation;
  final VoidCallback onSelectModel;
  final bool canToggleTemporaryConversation;
  final bool temporaryConversationEnabled;
  final bool globalSearchMode;
  final String globalSearchQuery;
  final ValueChanged<String> onGlobalSearchQueryChanged;
  final VoidCallback onEnterGlobalSearch;
  final VoidCallback onExitGlobalSearch;
  final Future<void> Function(String conversationId, String messageId)
  onOpenGlobalSearchResult;
  final PreferredSizeWidget? appBarOverride;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InteractiveDrawer(
      controller: drawerController,
      side: DrawerSide.left,
      drawerWidth: MediaQuery.sizeOf(context).width * 0.75,
      scrimColor: cs.onSurface,
      maxScrimOpacity: 0.12,
      barrierDismissible: true,
      drawer: SideDrawer(
        userName: context.watch<UserProvider>().name,
        assistantName: _getAssistantName(context),
        closePickerTicker: assistantPickerCloseTick,
        loadingConversationIds: loadingConversationIds,
        globalSearchMode: globalSearchMode,
        globalSearchQuery: globalSearchQuery,
        onGlobalSearchQueryChanged: onGlobalSearchQueryChanged,
        onEnterGlobalSearch: onEnterGlobalSearch,
        onExitGlobalSearch: onExitGlobalSearch,
        onOpenGlobalSearchResult: (conversationId, messageId) async {
          await onOpenGlobalSearchResult(conversationId, messageId);
          drawerController.close();
        },
        onSelectConversation: (id, {closeDrawer = true}) {
          onSelectConversation(id);
          if (closeDrawer) drawerController.close();
        },
        onNewConversation: ({closeDrawer = true}) async {
          await onCreateNewConversation();
          if (closeDrawer) drawerController.close();
        },
      ),
      child: ChatFrostedBackdrop(
        backdrop: const MobileBackgroundLayer(),
        child: Scaffold(
          key: scaffoldKey,
          resizeToAvoidBottomInset: true,
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: appBarOverride ?? _buildAppBar(context, cs),
          body: body,
        ),
      ),
    );
  }

  String _getAssistantName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = context.watch<AssistantProvider>().currentAssistant;
    final n = a?.name.trim();
    return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ColorScheme cs) {
    final useNewAssistantAvatarUx = context
        .watch<SettingsProvider>()
        .useNewAssistantAvatarUx;

    return AppBar(
      systemOverlayStyle: (Theme.of(context).brightness == Brightness.dark)
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Builder(
        builder: (context) {
          return IosIconButton(
            size: 20,
            padding: const EdgeInsets.all(8),
            minSize: 40,
            builder: (color) => SvgPicture.asset(
              'assets/icons/list.svg',
              width: 14,
              height: 14,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            onTap: () {
              onDismissKeyboard();
              onToggleDrawer();
            },
          );
        },
      ),
      centerTitle: true,
      title: const ChatHeaderSwitcher(large: true),
      // The chat's name and model sit on one quiet full-width line under
      // the switcher, so neither squeezes the other.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(kChatHeaderTitleLineHeight),
        child: _buildTitleLine(context, cs, useNewAssistantAvatarUx),
      ),
      actions: [
        IosIconButton(
          size: 20,
          minSize: 44,
          onTap: onOpenMiniMap,
          semanticLabel: AppLocalizations.of(context)!.miniMapTooltip,
          icon: Lucide.Map,
        ),
        IosIconButton(
          size: 22,
          minSize: 44,
          onTap: () async {
            if (canToggleTemporaryConversation) {
              await onToggleTemporaryConversation();
            } else {
              await onCreateNewConversation();
            }
          },
          semanticLabel: canToggleTemporaryConversation
              ? AppLocalizations.of(context)!.temporaryChatToggleTooltip
              : AppLocalizations.of(context)!.titleForLocale,
          icon: canToggleTemporaryConversation && !temporaryConversationEnabled
              ? Lucide.MessageCircleDashed
              : Lucide.MessageCirclePlus,
          builder:
              canToggleTemporaryConversation && temporaryConversationEnabled
              ? (color) => SvgPicture.asset(
                  'assets/icons/temporary_chat_checked.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                )
              : null,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildTitleLine(
    BuildContext context,
    ColorScheme cs,
    bool withAvatar,
  ) {
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final hasModel = providerName != null && modelDisplay != null;
    return SizedBox(
      height: kChatHeaderTitleLineHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (withAvatar) ...[
              _buildAssistantTitleAvatar(context, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: AnimatedTextSwap(
                text: title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasModel) ...[
              Text('  ·  ', style: TextStyle(fontSize: 12, color: muted)),
              Flexible(
                child: Tooltip(
                  message: '$modelDisplay ($providerName)',
                  child: InkWell(
                    key: modelLineKey,
                    borderRadius: BorderRadius.circular(6),
                    onTap: onSelectModel,
                    child: AnimatedTextSwap(
                      text: modelDisplay!,
                      style: TextStyle(
                        fontSize: 12,
                        color: muted,
                        fontWeight: AppFontWeights.medium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantTitleAvatar(BuildContext context, {double size = 28}) {
    final assistantProvider = context.watch<AssistantProvider>();
    final currentAssistant = assistantProvider.currentAssistant;
    final currentAssistantId = assistantProvider.currentAssistantId;

    return IosCardPress(
      borderRadius: BorderRadius.circular(999),
      baseColor: Colors.transparent,
      padding: const EdgeInsets.all(2),
      longPressTimeout: const Duration(milliseconds: 280),
      onTap: () {
        onDismissKeyboard();
        onToggleDrawer();
      },
      onLongPress: currentAssistantId == null
          ? null
          : () {
              Haptics.light();
              AssistantEntryActions.openAssistantSettings(
                context,
                currentAssistantId,
              );
            },
      child: AssistantAvatar(
        assistant: currentAssistant,
        fallbackName: _getAssistantName(context),
        size: size,
      ),
    );
  }
}

/// Mobile background widget with assistant-specific image and gradient overlay
class MobileBackgroundLayer extends StatelessWidget {
  const MobileBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatAssistantBackground();
  }
}
