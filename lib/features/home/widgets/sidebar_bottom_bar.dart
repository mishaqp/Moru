import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/sidebar_shortcut.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/browser/browser_library.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/pages/webview/browser_mini_window.dart';
import '../../../shared/widgets/form_sheet.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import '../../mini_apps/mini_app_launcher.dart';
import '../../mini_apps/pages/mini_apps_page.dart';
import '../../scheduled_tasks/pages/scheduled_tasks_page.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../settings/pages/settings_page.dart';
import '../../translate/pages/translate_page.dart';
import '../../workspace/workspace_navigation.dart';
import 'sidebar_glass.dart';

/// The bottom of the sidebar: cards for the mini apps and web pages the user
/// pinned, then a dock with the avatar and the app's main screens.
class SidebarBottomBar extends StatefulWidget {
  const SidebarBottomBar({
    super.key,
    required this.avatar,
    required this.onAvatarTap,
    required this.glass,
    this.miniApps,
    this.browserLibrary,
  });

  final Widget avatar;
  final VoidCallback onAvatarTap;

  /// Light glass tiles on the glass theme, plain ones otherwise.
  final bool glass;

  /// Tests pass their own stores; the app uses the shared ones.
  final MiniAppStore? miniApps;
  final BrowserLibrary? browserLibrary;

  static const Key shortcutsKey = ValueKey<String>('sidebar-shortcuts');
  static const Key addShortcutKey = ValueKey<String>('sidebar-shortcut-add');
  static const Key dockKey = ValueKey<String>('sidebar-dock');

  static Key shortcutKey(SidebarShortcut shortcut) => ValueKey<String>(
    'sidebar-shortcut-${shortcut.web ? 'web' : 'app'}:${shortcut.target}',
  );

  @override
  State<SidebarBottomBar> createState() => _SidebarBottomBarState();
}

class _SidebarBottomBarState extends State<SidebarBottomBar> {
  MiniAppStore get _apps => widget.miniApps ?? MiniAppStore.instance;
  BrowserLibrary get _library =>
      widget.browserLibrary ?? BrowserLibrary.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_apps.load().catchError((Object _) {}));
    unawaited(_library.load().catchError((Object _) {}));
  }

  /// The pinned shortcuts that still lead somewhere: a deleted mini app
  /// drops out of the row (and comes back if it is published again).
  List<({SidebarShortcut shortcut, MiniApp? app})> _visible(
    List<SidebarShortcut> pinned,
  ) => [
    for (final shortcut in pinned)
      if (shortcut.web)
        (shortcut: shortcut, app: null)
      else if (_apps.byId(shortcut.target) case final app?)
        (shortcut: shortcut, app: app),
  ];

  bool _hasCandidates(Set<SidebarShortcut> pinned) =>
      _apps.apps.any(
        (app) => !pinned.contains(SidebarShortcut.miniApp(app.id)),
      ) ||
      _library.bookmarks.value.any(
        (page) => !pinned.contains(SidebarShortcut.webPage(page.url, '')),
      );

  Future<void> _open(SidebarShortcut shortcut) async {
    Haptics.light();
    if (shortcut.web) {
      await openSharedBrowser(startUrl: shortcut.target, newTab: true);
    } else {
      await MiniAppLauncher.open(context, shortcut.target, store: _apps);
    }
  }

  Future<void> _remove(SidebarShortcut shortcut, String name) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final remove = await showOptionSheet<bool>(
      context,
      title: name,
      items: [
        OptionSheetItem(
          value: true,
          icon: Lucide.Trash2,
          label: l10n.sideDrawerShortcutRemove,
        ),
      ],
    );
    if (remove != true) return;
    await settings.setSidebarShortcuts([
      for (final s in settings.sidebarShortcuts)
        if (s != shortcut) s,
    ]);
  }

  Future<void> _pick() async {
    Haptics.light();
    await showFormSheet<void>(
      context,
      builder: (_) => _ShortcutPicker(apps: _apps, library: _library),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = context.select<SettingsProvider, List<SidebarShortcut>>(
      (s) => s.sidebarShortcuts,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([_apps, _library.bookmarks]),
          builder: (context, _) {
            final visible = _visible(pinned);
            final canAdd = _hasCandidates(pinned.toSet());
            if (visible.isEmpty && !canAdd) return const SizedBox.shrink();
            return SizedBox(
              key: SidebarBottomBar.shortcutsKey,
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final item in visible)
                    _ShortcutCard(
                      key: SidebarBottomBar.shortcutKey(item.shortcut),
                      glass: widget.glass,
                      leading: item.app == null
                          ? const _WebIcon(size: 28)
                          : MiniAppIcon(app: item.app!, size: 28),
                      label: item.app?.name ?? _pageName(item.shortcut),
                      onTap: () => unawaited(_open(item.shortcut)),
                      onLongPress: () => unawaited(
                        _remove(
                          item.shortcut,
                          item.app?.name ?? _pageName(item.shortcut),
                        ),
                      ),
                    ),
                  if (canAdd)
                    _ShortcutCard(
                      key: SidebarBottomBar.addShortcutKey,
                      glass: widget.glass,
                      leading: Icon(
                        Lucide.Plus,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: visible.isEmpty
                          ? AppLocalizations.of(context)!.sideDrawerShortcutAdd
                          : null,
                      tooltip: AppLocalizations.of(
                        context,
                      )!.sideDrawerShortcutsTitle,
                      onTap: () => unawaited(_pick()),
                    ),
                ],
              ),
            );
          },
        ),
        _Dock(avatar: widget.avatar, onAvatarTap: widget.onAvatarTap),
      ],
    );
  }
}

/// A saved page's title, or its host when it had none.
String _pageName(SidebarShortcut shortcut) {
  if (shortcut.title.trim().isNotEmpty) return shortcut.title.trim();
  final host = Uri.tryParse(shortcut.target)?.host ?? '';
  return host.isEmpty ? shortcut.target : host;
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    super.key,
    required this.glass,
    required this.leading,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.tooltip,
  });

  final bool glass;
  final Widget leading;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final text = label;
    Widget card = GestureDetector(
      onLongPress: onLongPress,
      child: IosCardPress(
        borderRadius: radius,
        baseColor: Colors.transparent,
        haptics: false,
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Container(
          constraints: BoxConstraints(
            minWidth: 48,
            maxWidth: text == null ? 48 : 150,
          ),
          padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 10),
          decoration: sidebarGlassTile(context, glass: glass, radius: radius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              if (text != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.medium,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) card = Tooltip(message: tooltip, child: card);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Semantics(button: true, label: tooltip, child: card),
    );
  }
}

class _WebIcon extends StatelessWidget {
  const _WebIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(Lucide.Globe, size: size * 0.6, color: cs.primary),
    );
  }
}

/// Chooses which mini apps and bookmarked pages get a card; a tap adds or
/// removes one, and the sheet stays open.
class _ShortcutPicker extends StatelessWidget {
  const _ShortcutPicker({required this.apps, required this.library});

  final MiniAppStore apps;
  final BrowserLibrary library;

  static Key rowKey(SidebarShortcut shortcut) => ValueKey<String>(
    'sidebar-shortcut-pick-${shortcut.web ? 'web' : 'app'}:${shortcut.target}',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final pinned = settings.sidebarShortcuts;

    Future<void> toggle(SidebarShortcut shortcut) {
      Haptics.light();
      return settings.setSidebarShortcuts(
        pinned.contains(shortcut)
            ? [
                for (final s in pinned)
                  if (s != shortcut) s,
              ]
            : [...pinned, shortcut],
      );
    }

    Widget check(SidebarShortcut shortcut) => pinned.contains(shortcut)
        ? Icon(Lucide.Check, size: 18, color: cs.primary)
        : const SizedBox.shrink();

    final appList = apps.apps;
    final pages = library.bookmarks.value;
    return FormSheet(
      title: l10n.sideDrawerShortcutsTitle,
      children: [
        if (appList.isEmpty && pages.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.sideDrawerShortcutsEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
          ),
        if (appList.isNotEmpty) ...[
          IosSectionHeader(text: l10n.miniAppsTitle, first: true),
          SectionCard(
            children: [
              for (final app in appList) ...[
                if (app != appList.first) const IosRowDivider(indent: 54),
                IosNavRow(
                  key: rowKey(SidebarShortcut.miniApp(app.id)),
                  leading: MiniAppIcon(app: app, size: 28),
                  label: app.name,
                  trailing: check(SidebarShortcut.miniApp(app.id)),
                  onTap: () =>
                      unawaited(toggle(SidebarShortcut.miniApp(app.id))),
                ),
              ],
            ],
          ),
        ],
        if (pages.isNotEmpty) ...[
          IosSectionHeader(text: l10n.browserBookmarks, first: appList.isEmpty),
          SectionCard(
            children: [
              for (final page in pages) ...[
                if (page != pages.first) const IosRowDivider(indent: 54),
                IosNavRow(
                  key: rowKey(SidebarShortcut.webPage(page.url, page.title)),
                  leading: const _WebIcon(size: 28),
                  label: page.title.trim().isEmpty ? page.url : page.title,
                  subtitle: Uri.tryParse(page.url)?.host,
                  trailing: check(SidebarShortcut.webPage(page.url, '')),
                  onTap: () => unawaited(
                    toggle(SidebarShortcut.webPage(page.url, page.title)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The avatar and one-tap icons for the app's main screens.
class _Dock extends StatelessWidget {
  const _Dock({required this.avatar, required this.onAvatarTap});

  final Widget avatar;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = Theme.of(context).colorScheme.onSurface;

    void push(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    // Each icon takes an equal share, so six fit next to the avatar even on
    // a narrow phone.
    Widget item(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Center(
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: IosIconButton(
              size: 22,
              color: color,
              icon: icon,
              padding: const EdgeInsets.all(7),
              onTap: onTap,
            ),
          ),
        ),
      ),
    );

    return Padding(
      key: SidebarBottomBar.dockKey,
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAvatarTap,
            child: avatar,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              children: [
                item(
                  Lucide.LayoutGrid,
                  l10n.miniAppsTitle,
                  () => push(const MiniAppsPage()),
                ),
                item(
                  Lucide.SquareTerminal,
                  l10n.workspaceEnvTitle,
                  () => WorkspaceNavigation.openEnvironmentPage(context),
                ),
                item(
                  Lucide.CalendarClock,
                  l10n.scheduledTasksTitle,
                  () => push(const ScheduledTasksPage()),
                ),
                item(
                  Lucide.Brain,
                  l10n.memorySettingsPageTitle,
                  () => push(const MemorySettingsPage()),
                ),
                item(
                  Lucide.Languages,
                  l10n.desktopNavTranslateTooltip,
                  () => push(const TranslatePage()),
                ),
                item(
                  Lucide.Settings,
                  l10n.settingsPageTitle,
                  () => push(const SettingsPage()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
