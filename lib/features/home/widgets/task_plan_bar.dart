import 'package:flutter/material.dart';

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

/// A compact chip with the plan's progress and current step; a tap opens
/// or closes the whole checklist.
class TaskPlanChip extends StatelessWidget {
  const TaskPlanChip({
    super.key,
    required this.plan,
    required this.expanded,
    required this.onTap,
  });

  static const Key toggleKey = ValueKey<String>('task-plan-bar-toggle');

  final TaskPlan plan;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final current = plan.current;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: toggleKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Icon(Lucide.ListChecks, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                l10n.taskPlanProgress(plan.completed, plan.steps.length),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  current?.text ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.25,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(
                expanded ? Lucide.ChevronDown : Lucide.ChevronUp,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
