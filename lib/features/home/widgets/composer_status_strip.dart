import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/workspace/task_plan.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import 'running_tool_bar.dart';
import 'task_plan_bar.dart';

/// One row above the composer for what the agent is doing: the open task
/// plan and the running command side by side, each taking the full width
/// when alone. The plan's checklist opens above the row. Hidden when there
/// is neither.
class ComposerStatusStrip extends StatefulWidget {
  const ComposerStatusStrip({
    super.key,
    required this.conversationId,
    required this.generating,
  });

  final String? conversationId;

  /// The plan is live progress: once the reply ends it stays only in the
  /// reply's own update_plan card, even if the model left a step open.
  /// Background commands outlive the reply and keep their chip.
  final bool generating;

  @override
  State<ComposerStatusStrip> createState() => _ComposerStatusStripState();
}

class _ComposerStatusStripState extends State<ComposerStatusStrip> {
  bool _planOpen = false;

  static T? _watch<T>(BuildContext context) {
    try {
      return Provider.of<T>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _watch<TaskPlanRegistry>(context)?.of(widget.conversationId);
    final openPlan = widget.generating && plan != null && !plan.isDone
        ? plan
        : null;
    final runs =
        _watch<ToolRunRegistry>(context)?.runningIn(widget.conversationId) ??
        const <ToolRun>[];
    final cs = Theme.of(context).colorScheme;

    Widget? content;
    if (openPlan != null || runs.isNotEmpty) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (openPlan != null && _planOpen)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TaskPlanChecklist(plan: openPlan),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (openPlan != null)
                    Expanded(
                      child: TaskPlanChip(
                        plan: openPlan,
                        expanded: _planOpen,
                        onTap: () => setState(() => _planOpen = !_planOpen),
                      ),
                    ),
                  if (openPlan != null && runs.isNotEmpty)
                    const SizedBox(width: 6),
                  if (runs.isNotEmpty)
                    Expanded(
                      child: RunningToolChip(
                        key: ValueKey(runs.last.toolCallId),
                        run: runs.last,
                        moreCount: runs.length - 1,
                        conversationId: widget.conversationId,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      // Clipping keeps a strip that is still growing from painting over the
      // chips next to it.
      clipBehavior: Clip.hardEdge,
      child: content ?? const SizedBox(width: double.infinity),
    );
  }
}
