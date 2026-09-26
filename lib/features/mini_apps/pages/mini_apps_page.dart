import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../mini_app_launcher.dart';

/// "My apps": the mini apps the agent published.
class MiniAppsPage extends StatefulWidget {
  const MiniAppsPage({super.key, this._store});

  final MiniAppStore? _store;

  @override
  State<MiniAppsPage> createState() => _MiniAppsPageState();
}

class _MiniAppsPageState extends State<MiniAppsPage> {
  MiniAppStore get _store => widget._store ?? MiniAppStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
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
        await MiniAppLauncher.open(context, app.id, store: widget._store);
      case 'pin':
        final ok = await MiniAppLauncher.pinShortcut(app);
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: ok ? l10n.miniAppsPinRequested : l10n.miniAppsPinUnsupported,
          type: ok ? NotificationType.success : NotificationType.warning,
        );
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
          final apps = _store.apps;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (apps.isEmpty)
                _EmptyState(text: l10n.miniAppsEmpty)
              else
                SectionCard(
                  children: [
                    for (final app in apps) ...[
                      if (app != apps.first) const IosRowDivider(),
                      IosNavRow(
                        key: ValueKey('mini-app-${app.id}'),
                        leading: MiniAppIcon(app: app, size: 32),
                        label: app.name,
                        subtitle: app.description.isEmpty
                            ? null
                            : app.description,
                        onTap: () => unawaited(
                          MiniAppLauncher.open(
                            context,
                            app.id,
                            store: widget._store,
                          ),
                        ),
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
