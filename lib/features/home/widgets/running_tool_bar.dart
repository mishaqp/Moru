import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/workspace/tool_run_registry.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';
import '../../chat/widgets/workspace_tool_detail.dart';
import '../../chat/widgets/workspace_tool_ui.dart';

/// A strip above the composer for the command still running in this
/// conversation: what runs, for how long, a tap for its live output and a
/// stop button. Hidden when nothing runs.
class RunningToolBar extends StatelessWidget {
  const RunningToolBar({super.key, required this.conversationId});

  final String? conversationId;

  static const Key stopKey = ValueKey<String>('running-tool-bar-stop');

  @override
  Widget build(BuildContext context) {
    ToolRunRegistry? registry;
    try {
      registry = context.watch<ToolRunRegistry>();
    } on ProviderNotFoundException {
      registry = null;
    }
    final runs = registry?.runningIn(conversationId) ?? const <ToolRun>[];
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: runs.isEmpty
          ? const SizedBox(width: double.infinity)
          : _RunningToolTile(
              key: ValueKey(runs.last.toolCallId),
              run: runs.last,
              moreCount: runs.length - 1,
              conversationId: conversationId,
            ),
    );
  }
}

class _RunningToolTile extends StatefulWidget {
  const _RunningToolTile({
    super.key,
    required this.run,
    required this.moreCount,
    required this.conversationId,
  });

  final ToolRun run;
  final int moreCount;
  final String? conversationId;

  @override
  State<_RunningToolTile> createState() => _RunningToolTileState();
}

class _RunningToolTileState extends State<_RunningToolTile> {
  Timer? _ticker;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed() {
    final seconds = DateTime.now().difference(widget.run.startedAt).inSeconds;
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return m > 0 ? '$m:$s' : '${seconds}s';
  }

  void _openDetail() {
    final run = widget.run;
    unawaited(
      showWorkspaceToolDetail(
        context,
        WorkspaceToolPart(
          id: run.toolCallId,
          toolName: run.toolName,
          arguments: {if (run.command != null) 'command': run.command},
          loading: true,
        ),
        conversationId: widget.conversationId,
      ),
    );
  }

  void _stop() {
    final runtime = maybeRead<WorkspaceRuntimeProvider>(context)?.runtime;
    if (runtime == null) return;
    setState(() => _stopping = true);
    unawaited(runtime.cancel(widget.run.runtimeRunId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final run = widget.run;
    final label = (run.command ?? '').trim().isNotEmpty
        ? run.command!.trim().split('\n').first
        : workspaceToolTitle(l10n, run.toolName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openDetail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                Icon(Lucide.SquareTerminal, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.moreCount > 0
                        ? '${l10n.workspaceToolRunning} · ${_elapsed()} · '
                              '+${widget.moreCount}'
                        : '${l10n.workspaceToolRunning} · ${_elapsed()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.primary,
                    ),
                  ),
                ),
                IconButton(
                  key: RunningToolBar.stopKey,
                  tooltip: l10n.workspaceToolCancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: _stopping ? null : _stop,
                  icon: Icon(Lucide.CircleStop, size: 18, color: cs.error),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
