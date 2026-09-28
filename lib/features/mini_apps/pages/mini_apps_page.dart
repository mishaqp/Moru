import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/mini_apps/mini_app_jobs.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../mini_app_launcher.dart';
import '../widgets/mini_app_sheets.dart';

/// "My apps": the mini apps the agent published.
class MiniAppsPage extends StatefulWidget {
  const MiniAppsPage({super.key, this._store, this._jobs});

  final MiniAppStore? _store;
  final MiniAppJobs? _jobs;

  @override
  State<MiniAppsPage> createState() => _MiniAppsPageState();
}

class _MiniAppsPageState extends State<MiniAppsPage> {
  MiniAppStore get _store => widget._store ?? MiniAppStore.instance;
  MiniAppJobs get _jobs => widget._jobs ?? MiniAppLauncher.jobs;

  /// Background jobs and journal entries per app, shown as badges.
  Map<String, ({int jobs, int errors})> _counts = const {};
  final TextEditingController _search = TextEditingController();

  static const int searchFrom = 5;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    unawaited(_store.load().then((_) => _loadCounts()));
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _search.dispose();
    super.dispose();
  }

  void _onStore() => unawaited(_loadCounts());

  Future<void> _loadCounts() async {
    final counts = <String, ({int jobs, int errors})>{};
    for (final app in _store.apps) {
      try {
        counts[app.id] = (
          jobs: (await _store.readJobs(app.id)).length,
          errors: (await _store.readErrors(app.id)).length,
        );
      } on Object {
        // Deleted meanwhile, or unreadable: no badges.
      }
    }
    if (mounted) setState(() => _counts = counts);
  }

  Future<void> _open(MiniApp app) async {
    await MiniAppLauncher.open(context, app.id, store: widget._store);
    // The app may have logged errors or set jobs.
    await _loadCounts();
  }

  List<MiniApp> _filtered(List<MiniApp> apps) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return apps;
    return [
      for (final app in apps)
        if ('${app.name} ${app.description} ${app.id}'.toLowerCase().contains(
          query,
        ))
          app,
    ];
  }

  Future<void> _actions(MiniApp app) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showOptionSheet<String>(
      context,
      title: app.name,
      items: [
        OptionSheetItem(
          value: 'open',
          icon: Lucide.ExternalLink,
          label: l10n.miniAppsOpen,
        ),
        OptionSheetItem(
          value: 'pin',
          icon: Lucide.Smartphone,
          label: l10n.miniAppsAddToHomeScreen,
        ),
        OptionSheetItem(
          value: 'versions',
          icon: Lucide.History,
          label: l10n.miniAppsVersions,
        ),
        if (app.serverCommand != null)
          OptionSheetItem(
            value: 'server',
            icon: Lucide.Server,
            label: l10n.miniAppsServer,
          ),
        OptionSheetItem(
          value: 'jobs',
          icon: Lucide.CalendarClock,
          label: l10n.miniAppsJobs,
        ),
        OptionSheetItem(
          value: 'errors',
          icon: Lucide.Bug,
          label: l10n.miniAppsErrors,
        ),
        OptionSheetItem(
          value: 'share',
          icon: Lucide.Share2,
          label: l10n.miniAppsShare,
        ),
        OptionSheetItem(
          value: 'delete',
          icon: Lucide.Trash2,
          label: l10n.miniAppsDelete,
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        await _open(app);
      case 'pin':
        final ok = await MiniAppLauncher.pinShortcut(app);
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: ok ? l10n.miniAppsPinRequested : l10n.miniAppsPinUnsupported,
          type: ok ? NotificationType.success : NotificationType.warning,
        );
      case 'versions':
        await showMiniAppVersions(context, store: _store, app: app);
      case 'server':
        await showMiniAppServer(
          context,
          servers: MiniAppLauncher.servers,
          app: app,
        );
      case 'jobs':
        await showMiniAppJobs(context, jobs: _jobs, app: app);
      case 'errors':
        await showMiniAppErrors(context, store: _store, app: app);
      case 'share':
        await MiniAppLauncher.share(context, app, store: widget._store);
      case 'delete':
        final confirmed = await showOptionSheet<bool>(
          context,
          title: l10n.miniAppsDeleteTitle(app.name),
          items: [
            OptionSheetItem(
              value: true,
              icon: Lucide.Trash2,
              label: l10n.miniAppsDelete,
            ),
          ],
          footer: IosSectionFooter(text: l10n.miniAppsDeleteDetail),
        );
        if (confirmed == true) await _store.delete(app.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            minSize: 44,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.miniAppsTitle),
        actions: [
          Tooltip(
            message: l10n.miniAppsImport,
            child: IosIconButton(
              icon: Lucide.Import,
              minSize: 44,
              size: 20,
              onTap: () => unawaited(
                MiniAppLauncher.pickAndImport(context, store: widget._store),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (!_store.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = _store.apps;
          final apps = _filtered(all);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (all.length >= searchFrom) ...[
                TextField(
                  key: const ValueKey('mini-apps-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.miniAppsSearch,
                    prefixIcon: const Icon(Lucide.Search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (all.isEmpty)
                _EmptyState(text: l10n.miniAppsEmpty)
              else if (apps.isNotEmpty)
                SectionCard(
                  children: [
                    for (final app in apps) ...[
                      if (app != apps.first) const IosRowDivider(),
                      IosNavRow(
                        key: ValueKey('mini-app-${app.id}'),
                        leading: MiniAppIcon(app: app, size: 32),
                        label: app.name,
                        labelTrailing: _Badges(
                          app: app,
                          counts: _counts[app.id],
                        ),
                        subtitle: app.description.isEmpty
                            ? null
                            : app.description,
                        onTap: () => unawaited(_open(app)),
                        onLongPress: () => unawaited(_actions(app)),
                        trailing: IosIconButton(
                          icon: Lucide.Ellipsis,
                          size: 18,
                          minSize: 36,
                          onTap: () => unawaited(_actions(app)),
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 8),
              IosSectionFooter(text: l10n.miniAppsFooter),
            ],
          );
        },
      ),
    );
  }
}

/// What an app does beyond a page: game, server, jobs, errors.
class _Badges extends StatelessWidget {
  const _Badges({required this.app, required this.counts});

  final MiniApp app;
  final ({int jobs, int errors})? counts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.5);
    final jobs = counts?.jobs ?? 0;
    final errors = counts?.errors ?? 0;
    Widget badge(IconData icon, String tooltip, Color color, [int? count]) =>
        Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                if (count != null)
                  Text(' $count', style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (app.fullscreen)
          badge(Lucide.Gamepad, l10n.miniAppsBadgeGame, muted),
        if (app.serverCommand != null)
          badge(Lucide.Server, l10n.miniAppsServer, muted),
        if (jobs > 0)
          badge(Lucide.CalendarClock, l10n.miniAppsJobs, muted, jobs),
        if (errors > 0)
          badge(Lucide.Bug, l10n.miniAppsErrors, cs.error, errors),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        children: [
          Icon(Lucide.LayoutGrid, size: 40, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's SVG icon, or its first letter.
class MiniAppIcon extends StatelessWidget {
  const MiniAppIcon({super.key, required this.app, required this.size});

  final MiniApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = app.iconPath;
    final letter = Center(
      child: Text(
        app.name.characters.first.toUpperCase(),
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox.square(
        dimension: size,
        child: path == null
            ? ColoredBox(color: cs.primary, child: letter)
            : SvgPicture.file(
                File(path),
                width: size,
                height: size,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: cs.primary, child: letter),
              ),
      ),
    );
  }
}
