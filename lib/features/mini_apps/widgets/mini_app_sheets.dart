import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/services/mini_apps/mini_app_jobs.dart';
import '../../../core/services/mini_apps/mini_app_servers.dart';
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

/// The app's background jobs: when each runs, how the last run went, and
/// run now or delete.
Future<void> showMiniAppJobs(
  BuildContext context, {
  required MiniAppJobs jobs,
  required MiniApp app,
}) => showFormSheet<void>(
  context,
  builder: (_) => _JobsSheet(jobs: jobs, app: app),
);

class _JobsSheet extends StatefulWidget {
  const _JobsSheet({required this.jobs, required this.app});

  final MiniAppJobs jobs;
  final MiniApp app;

  @override
  State<_JobsSheet> createState() => _JobsSheetState();
}

class _JobsSheetState extends State<_JobsSheet> {
  List<MiniAppJob>? _jobs;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final jobs = await widget.jobs.list(widget.app.id);
    if (mounted) setState(() => _jobs = jobs);
  }

  String _schedule(MiniAppJob job) {
    final l10n = AppLocalizations.of(context)!;
    final days = job.days;
    if (days == null) return '${job.time} · ${l10n.miniAppsJobEveryDay}';
    final format = DateFormat.E(
      Localizations.localeOf(context).toLanguageTag(),
    );
    // 2024-01-01 was a Monday.
    final names = [
      for (final day in days) format.format(DateTime(2024, 1, day)),
    ];
    return '${job.time} · ${names.join(', ')}';
  }

  String _status(MiniAppJob job) {
    final l10n = AppLocalizations.of(context)!;
    final lines = <String>[
      if (job.nextRunAt case final next?)
        l10n.miniAppsJobNext(_when(context, next)),
    ];
    if (job.runs.firstOrNull case final last?) {
      final at = _when(context, last.startedAt);
      lines.add(switch (last.status) {
        'running' => l10n.miniAppsJobRunning,
        'completed' => l10n.miniAppsJobLastDone(at),
        _ => [
          l10n.miniAppsJobLastFailed(at),
          if (last.error case final error?) error,
        ].join(' — '),
      });
    }
    return lines.join('\n');
  }

  Future<void> _actions(MiniAppJob job) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showOptionSheet<String>(
      context,
      title: job.id,
      items: [
        OptionSheetItem(
          value: 'run',
          icon: Lucide.Play,
          label: l10n.miniAppsJobRunNow,
        ),
        OptionSheetItem(
          value: 'delete',
          icon: Lucide.Trash2,
          label: l10n.miniAppsDelete,
        ),
      ],
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'run') {
        await widget.jobs.runNow(widget.app.id, job.id);
        if (mounted) {
          showAppSnackBar(context, message: l10n.miniAppsJobStarted);
        }
      } else {
        await widget.jobs.remove(widget.app.id, job.id);
      }
    } on MiniAppException catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: e.message,
          type: NotificationType.warning,
        );
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final jobs = _jobs;
    return FormSheet(
      title: l10n.miniAppsJobs,
      children: [
        if (jobs == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )
        else if (jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
            child: Text(l10n.miniAppsJobsEmpty, textAlign: TextAlign.center),
          )
        else
          SectionCard(
            children: [
              for (final job in jobs) ...[
                if (job != jobs.first) const IosRowDivider(indent: 54),
                IosNavRow(
                  key: ValueKey('mini-app-job-${job.id}'),
                  icon: Lucide.CalendarClock,
                  label: '${job.id} · ${job.run}()',
                  subtitle: [
                    _schedule(job),
                    _status(job),
                  ].where((line) => line.isNotEmpty).join('\n'),
                  onTap: () => unawaited(_actions(job)),
                ),
              ],
            ],
          ),
        const SizedBox(height: 8),
        IosSectionFooter(text: l10n.miniAppsJobsFooter),
      ],
    );
  }
}

/// The app's server: whether it runs, its command and latest output, and
/// restart.
Future<void> showMiniAppServer(
  BuildContext context, {
  required MiniAppServers servers,
  required MiniApp app,
}) => showFormSheet<void>(
  context,
  builder: (_) => _ServerSheet(servers: servers, app: app),
);

class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.servers, required this.app});

  final MiniAppServers servers;
  final MiniApp app;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late Map<String, Object?> _status = widget.servers.status(widget.app.id);
  late final Timer _refresh;

  @override
  void initState() {
    super.initState();
    // The output grows while the sheet is open.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _status = widget.servers.status(widget.app.id));
      }
    });
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  Future<void> _copy(String text, String copied) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppSnackBar(context, message: copied);
  }

  Future<void> _restart() async {
    await widget.servers.restart(widget.app.id);
    if (mounted) {
      setState(() => _status = widget.servers.status(widget.app.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final running = _status['running'] == true;
    final ready = _status['ready'] == true;
    final exitCode = _status['exit_code'];
    final output = '${_status['output'] ?? ''}'.trimRight();
    final (label, color) = ready
        ? (l10n.miniAppsServerRunning('${_status['port']}'), Colors.green)
        : running
        ? (l10n.miniAppsServerStarting, Colors.orange)
        : exitCode != null
        ? (l10n.miniAppsServerExited('$exitCode'), cs.error)
        : (l10n.miniAppsServerIdle, cs.onSurface.withValues(alpha: 0.4));
    return FormSheet(
      title: l10n.miniAppsServer,
      actions: FormSheetActions(
        cancelLabel: l10n.miniAppsErrorsCopy,
        confirmLabel: l10n.miniAppsServerRestart,
        onCancel: () => unawaited(_copy(output, l10n.miniAppsErrorsCopied)),
        // Restarting is for a server something uses right now.
        onConfirm: running || exitCode != null
            ? () => unawaited(_restart())
            : null,
      ),
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          key: const ValueKey('mini-app-server-status'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '\$ ${widget.app.serverCommand ?? ''}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            // Newest output at the bottom, in view.
            reverse: true,
            child: SelectableText(
              output.isEmpty ? l10n.miniAppsServerNoOutput : output,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
