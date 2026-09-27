import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/form_sheet.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';

String _when(BuildContext context, DateTime time) => DateFormat.yMMMd(
  Localizations.localeOf(context).toLanguageTag(),
).add_Hm().format(time);

/// The app's error journal, newest first, with copy and clear.
Future<void> showMiniAppErrors(
  BuildContext context, {
  required MiniAppStore store,
  required MiniApp app,
}) => showFormSheet<void>(
  context,
  builder: (_) => _ErrorsSheet(store: store, app: app),
);

class _ErrorsSheet extends StatefulWidget {
  const _ErrorsSheet({required this.store, required this.app});

  final MiniAppStore store;
  final MiniApp app;

  @override
  State<_ErrorsSheet> createState() => _ErrorsSheetState();
}

class _ErrorsSheetState extends State<_ErrorsSheet> {
  List<MiniAppLogEntry>? _entries;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final entries = await widget.store.readErrors(widget.app.id);
    if (mounted) setState(() => _entries = entries.reversed.toList());
  }

  String _line(MiniAppLogEntry entry) =>
      '${_when(context, entry.at)}'
      '${entry.count > 1 ? ' ×${entry.count}' : ''}';

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(
      ClipboardData(
        text: [
          for (final entry in _entries ?? const <MiniAppLogEntry>[])
            '[${_line(entry)}] ${entry.message}',
        ].join('\n'),
      ),
    );
    if (!mounted) return;
    showAppSnackBar(context, message: l10n.miniAppsErrorsCopied);
  }

  Future<void> _clear() async {
    await widget.store.clearErrors(widget.app.id);
    if (mounted) setState(() => _entries = const []);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final entries = _entries;
    return FormSheet(
      title: l10n.miniAppsErrors,
      actions: entries == null || entries.isEmpty
          ? null
          : FormSheetActions(
              cancelLabel: l10n.miniAppsErrorsClear,
              confirmLabel: l10n.miniAppsErrorsCopy,
              onCancel: () => unawaited(_clear()),
              onConfirm: () => unawaited(_copy()),
            ),
      children: [
        if (entries == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )
        else if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l10n.miniAppsErrorsEmpty),
          )
        else
          SectionCard(
            children: [
              for (final entry in entries) ...[
                if (entry != entries.first) const IosRowDivider(indent: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        entry.message,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _line(entry),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 8),
        IosSectionFooter(text: l10n.miniAppsErrorsFooter),
      ],
    );
  }
}

/// Lets the user pick an earlier version of [app] and restores it. Returns
/// the restored app, or null when nothing changed.
Future<MiniApp?> showMiniAppVersions(
  BuildContext context, {
  required MiniAppStore store,
  required MiniApp app,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final versions = await store.versions(app.id);
  if (!context.mounted) return null;
  if (versions.isEmpty) {
    showAppSnackBar(context, message: l10n.miniAppsVersionsEmpty);
    return null;
  }
  final picked = await showOptionSheet<MiniApp>(
    context,
    title: l10n.miniAppsVersionsTitle(app.name),
    items: [
      for (final version in versions)
        OptionSheetItem(
          value: version,
          icon: Lucide.History,
          label: _when(context, version.updatedAt),
          subtitle: version.name == app.name ? null : version.name,
        ),
    ],
    footer: IosSectionFooter(text: l10n.miniAppsVersionsFooter),
  );
  if (picked == null || !context.mounted) return null;
  final restored = await store.rollback(app.id, MiniAppStore.versionOf(picked));
  if (context.mounted) {
    showAppSnackBar(
      context,
      message: l10n.miniAppsRolledBack(_when(context, picked.updatedAt)),
      type: NotificationType.success,
    );
  }
  return restored;
}
