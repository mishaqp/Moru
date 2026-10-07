import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../l10n/app_localizations.dart';
import '../widgets/side_drawer.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../utils/brand_assets.dart';
import '../controllers/chat_action_bus.dart';
import '../../chat/widgets/frosted/chat_frosted_backdrop.dart';
import '../widgets/assistant_avatar.dart';
import '../widgets/assistant_entry_actions.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

/// Desktop/Tablet layout scaffold for the home page
/// Handles the overall structure: left sidebar, main content, optional right sidebar
/// All message list rendering and input bar logic remain in home_page.dart
class HomeDesktopScaffold extends StatelessWidget {
  const HomeDesktopScaffold({
    super.key,
    required this.scaffoldKey,
    required this.assistantPickerCloseTick,
    required this.loadingConversationIds,
    required this.title,
    required this.providerName,
    required this.modelDisplay,
    // Sidebar state
    required this.tabletSidebarOpen,
    required this.embeddedSidebarWidth,
    // Callbacks
    required this.onToggleSidebar,
    required this.onSelectConversation,
    required this.onNewConversation,
    required this.onCreateNewConversation,
    required this.onToggleTemporaryConversation,
    required this.onSelectModel,
    required this.canToggleTemporaryConversation,
    required this.temporaryConversationEnabled,
    required this.globalSearchMode,
    required this.globalSearchQuery,
    required this.onGlobalSearchQueryChanged,
    required this.onOpenGlobalSearchResult,
    required this.buildAssistantBackground,
    this.appBarOverride,
    required this.body,
    this.backgroundActive = true,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final ValueNotifier<int> assistantPickerCloseTick;
  final Set<String> loadingConversationIds;
  final String title;
  final String? providerName;
  final String? modelDisplay;

  // Sidebar state
  final bool tabletSidebarOpen;
  final double embeddedSidebarWidth;

  // Callbacks
  final VoidCallback onToggleSidebar;
  final void Function(String id) onSelectConversation;
  final VoidCallback onNewConversation;
  final Future<void> Function() onCreateNewConversation;
  final Future<void> Function() onToggleTemporaryConversation;
  final VoidCallback onSelectModel;
  final bool canToggleTemporaryConversation;
  final bool temporaryConversationEnabled;
  final bool globalSearchMode;
  final String globalSearchQuery;
  final ValueChanged<String> onGlobalSearchQueryChanged;
  final Future<void> Function(String conversationId, String messageId)
  onOpenGlobalSearchResult;
  final Widget Function(BuildContext context) buildAssistantBackground;
  final PreferredSizeWidget? appBarOverride;
  final Widget body;
  final bool backgroundActive;

  static const Duration _sidebarAnimDuration = Duration(milliseconds: 260);
  static const Curve _sidebarAnimCurve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChatFrostedBackdrop(
      active: backgroundActive,
      backdrop: buildAssistantBackground(context),
      child: SizedBox.expand(
        child: Row(
          children: [
            // Left sidebar
            _buildLeftSidebar(context),
            AnimatedContainer(
              duration: _sidebarAnimDuration,
              curve: _sidebarAnimCurve,
              width: tabletSidebarOpen ? 0.6 : 0,
              child: tabletSidebarOpen
                  ? VerticalDivider(
                      width: 0.6,
                      thickness: 0.5,
                      color: cs.outlineVariant.withValues(alpha: 0.20),
                    )
                  : const SizedBox.shrink(),
            ),
            // Main content
            Expanded(
              child: Scaffold(
                key: scaffoldKey,
                resizeToAvoidBottomInset: true,
                extendBodyBehindAppBar: true,
                backgroundColor: Colors.transparent,
                appBar: appBarOverride ?? _buildAppBar(context, cs),
                body: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSidebar(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = context.select<SettingsProvider, double>(
      (settings) =>
          settings.sidebarAppearance.widthFor(screenWidth, wide: true),
    );
    final sidebar = SideDrawer(
      embedded: true,
      embeddedWidth: sidebarWidth,
      userName: context.watch<UserProvider>().name,
      assistantName: _getAssistantName(context),
      closePickerTicker: assistantPickerCloseTick,
      loadingConversationIds: loadingConversationIds,
      globalSearchMode: globalSearchMode,
      globalSearchQuery: globalSearchQuery,
      onGlobalSearchQueryChanged: onGlobalSearchQueryChanged,
      onEnterGlobalSearch: () {
        ChatActionBus.instance.fire(ChatAction.enterGlobalSearch);
      },
      onExitGlobalSearch: () {
        ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
      },
      onOpenGlobalSearchResult: onOpenGlobalSearchResult,
      onNewConversation: ({closeDrawer = true}) => onNewConversation(),
      onSelectConversation: (id, {closeDrawer = true}) =>
          onSelectConversation(id),
    );

    return AnimatedContainer(
      duration: _sidebarAnimDuration,
      curve: _sidebarAnimCurve,
      width: tabletSidebarOpen ? sidebarWidth : 0,
      color: Colors.transparent,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: sidebarWidth,
          child: TickerMode(
            enabled: tabletSidebarOpen,
            child: SizedBox(width: sidebarWidth, child: sidebar),
          ),
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
    return AppBar(
      centerTitle: false,
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
      leading: IosIconButton(
        size: 20,
        padding: const EdgeInsets.all(8),
        minSize: 40,
        builder: (color) => SvgPicture.asset(
          'assets/icons/list.svg',
          width: 14,
          height: 14,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
        onTap: onToggleSidebar,
      ),
      titleSpacing: 2,
      title: _buildTitle(context, cs),
      actions: _buildActions(context),
    );
  }

  Widget _buildTitle(BuildContext context, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useNewAssistantAvatarUx = context
        .watch<SettingsProvider>()
        .useNewAssistantAvatarUx;
    final currentAssistant = context
        .watch<AssistantProvider>()
        .currentAssistant;
    final String? brandAsset =
        (modelDisplay != null
            ? BrandAssets.assetForName(modelDisplay!)
            : null) ??
        (providerName != null ? BrandAssets.assetForName(providerName!) : null);

    Widget? capsule;
    String? capsuleLabel;

    if (providerName != null && modelDisplay != null) {
      final showProv = context
          .watch<SettingsProvider>()
          .showProviderInModelCapsule;
      capsuleLabel = showProv
          ? '$modelDisplay | $providerName'
          : '$modelDisplay';

      final Widget brandIcon = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: (brandAsset != null)
            ? (brandAsset.endsWith('.svg')
                  ? SvgPicture.asset(
                      brandAsset,
                      width: 16,
                      height: 16,
                      key: ValueKey('brand:$brandAsset'),
                      colorFilter:
                          isDark && BrandAssets.assetNeedsDarkInvert(brandAsset)
                          ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn)
                          : null,
                    )
                  : Image.asset(
                      brandAsset,
                      width: 16,
                      height: 16,
                      key: ValueKey('brand:$brandAsset'),
                    ))
            : Icon(
                Lucide.Boxes,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.7),
                key: const ValueKey('brand:default'),
              ),
      );

      capsule = IosCardPress(
        borderRadius: BorderRadius.circular(20),
        baseColor: Colors.transparent,
        pressedBlendStrength: isDark ? 0.18 : 0.12,
        padding: EdgeInsets.zero,
        onTap: onSelectModel,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                brandIcon,
                const SizedBox(width: 6),
                Flexible(
                  child: AnimatedTextSwap(
                    text: capsuleLabel,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      color: cs.onSurface.withValues(
                        alpha: isDark ? 0.92 : 0.9,
                      ),
                      fontWeight: AppFontWeights.medium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final row = Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (useNewAssistantAvatarUx) ...[
          _buildAssistantTitleAvatar(
            context,
            assistant: currentAssistant,
            fallbackName: _getAssistantName(context),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          fit: FlexFit.loose,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedTextSwap(
              text: title,
              style: TextStyle(fontSize: 16, fontWeight: AppFontWeights.medium),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (capsule != null) ...[
          const SizedBox(width: 8),
          Flexible(
            fit: FlexFit.loose,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey('cap:${capsuleLabel ?? ''}'),
                  child: capsule,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey('hdr:$title|${capsuleLabel ?? ''}'),
          child: row,
        ),
      ),
    );
  }

  Widget _buildAssistantTitleAvatar(
    BuildContext context, {
    required Assistant? assistant,
    required String fallbackName,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: IosCardPress(
        borderRadius: BorderRadius.circular(999),
        baseColor: Colors.transparent,
        padding: const EdgeInsets.all(2),
        onTap: onToggleSidebar,
        onLongPress: assistant != null
            ? () {
                AssistantEntryActions.openAssistantSettings(
                  context,
                  assistant.id,
                );
              }
            : null,
        child: AssistantAvatar(
          assistant: assistant,
          fallbackName: fallbackName,
          size: 28,
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      const SizedBox(width: 2),
      IosIconButton(
        size: 20,
        padding: const EdgeInsets.all(8),
        minSize: 40,
        semanticLabel: canToggleTemporaryConversation
            ? AppLocalizations.of(context)!.temporaryChatToggleTooltip
            : AppLocalizations.of(context)!.titleForLocale,
        icon: canToggleTemporaryConversation && !temporaryConversationEnabled
            ? Lucide.MessageCircleDashed
            : Lucide.MessageCirclePlus,
        builder: canToggleTemporaryConversation && temporaryConversationEnabled
            ? (color) => SvgPicture.asset(
                'assets/icons/temporary_chat_checked.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              )
            : null,
        onTap: () async {
          if (canToggleTemporaryConversation) {
            await onToggleTemporaryConversation();
          } else {
            await onCreateNewConversation();
          }
        },
      ),
      const SizedBox(width: 6),
    ];
  }
}
