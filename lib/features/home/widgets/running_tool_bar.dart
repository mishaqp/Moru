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
  static const Key tailKey = ValueKey<String>('running-tool-bar-tail');

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
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openDetail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                const _PulsingTerminalIcon(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Live tail: the run notifies at most every 50 ms.
                      ListenableBuilder(
                        listenable: run,
                        builder: (context, _) {
                          final tail = run.tailLines
                              .where((line) => line.trim().isNotEmpty)
                              .lastOrNull;
                          return Text(
                            tail?.trim() ?? '…',
                            key: RunningToolBar.tailKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.moreCount > 0
                        ? '${_elapsed()} · +${widget.moreCount}'
                        : _elapsed(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  key: RunningToolBar.stopKey,
                  tooltip: l10n.workspaceToolCancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: _stopping ? null : _stop,
                  icon: Icon(Lucide.CircleStop, size: 20, color: cs.error),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A terminal glyph with a softly breathing "live" dot.
class _PulsingTerminalIcon extends StatefulWidget {
  const _PulsingTerminalIcon();

  @override
  State<_PulsingTerminalIcon> createState() => _PulsingTerminalIconState();
}

class _PulsingTerminalIconState extends State<_PulsingTerminalIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(Lucide.SquareTerminal, size: 16, color: cs.primary),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: FadeTransition(
              opacity: _pulse,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.shade400,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.surfaceContainerHigh,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
