import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/workspace/task_plan.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// The model's `update_plan` checklist: done steps struck through, the
/// current one highlighted.
class TaskPlanChecklist extends StatelessWidget {
  const TaskPlanChecklist({super.key, required this.plan});

  final TaskPlan plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final step in plan.steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    switch (step.status) {
                      PlanStepStatus.completed => Lucide.CircleCheck,
                      PlanStepStatus.inProgress => Lucide.CircleDot,
                      PlanStepStatus.pending => Lucide.Circle,
                    },
                    size: 16,
                    color: switch (step.status) {
                      PlanStepStatus.completed => Colors.green.shade500,
                      PlanStepStatus.inProgress => cs.primary,
                      PlanStepStatus.pending => cs.onSurface.withValues(
                        alpha: 0.35,
                      ),
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: step.status == PlanStepStatus.inProgress
                          ? AppFontWeights.semibold
                          : null,
                      color: step.status == PlanStepStatus.completed
                          ? cs.onSurface.withValues(alpha: 0.5)
                          : cs.onSurface,
                      decoration: step.status == PlanStepStatus.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A strip above the composer with the conversation's open plan: progress
/// and the current step, expanding to the whole checklist. Hidden when there
/// is no plan or every step is done.
class TaskPlanBar extends StatefulWidget {
  const TaskPlanBar({super.key, required this.conversationId});

  final String? conversationId;

  static const Key toggleKey = ValueKey<String>('task-plan-bar-toggle');

  @override
  State<TaskPlanBar> createState() => _TaskPlanBarState();
}

class _TaskPlanBarState extends State<TaskPlanBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    TaskPlan? plan;
    try {
      plan = context.watch<TaskPlanRegistry>().of(widget.conversationId);
    } on ProviderNotFoundException {
      plan = null;
    }
    final visible = plan != null && !plan.isDone;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: visible
          ? _buildBar(context, plan)
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _buildBar(BuildContext context, TaskPlan plan) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final current = plan.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: TaskPlanBar.toggleKey,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(Lucide.ListChecks, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(
                      l10n.taskPlanProgress(plan.completed, plan.steps.length),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (current != null && !_expanded) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          current.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    Icon(
                      _expanded ? Lucide.ChevronDown : Lucide.ChevronUp,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: TaskPlanChecklist(plan: plan),
              ),
          ],
        ),
      ),
    );
  }
}
