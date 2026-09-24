import 'package:flutter/foundation.dart';

enum PlanStepStatus { pending, inProgress, completed }

@immutable
class PlanStep {
  const PlanStep(this.text, this.status);

  final String text;
  final PlanStepStatus status;
}

/// The checklist the model keeps with the `update_plan` tool.
@immutable
class TaskPlan {
  const TaskPlan(this.steps);

  final List<PlanStep> steps;

  int get completed =>
      steps.where((step) => step.status == PlanStepStatus.completed).length;

  bool get isDone => steps.isNotEmpty && completed == steps.length;

  PlanStep? get current {
    for (final step in steps) {
      if (step.status == PlanStepStatus.inProgress) return step;
    }
    for (final step in steps) {
      if (step.status == PlanStepStatus.pending) return step;
    }
    return null;
  }

  /// Parses `update_plan` arguments; null when they hold no usable step.
  static TaskPlan? fromArguments(Map<String, dynamic> args) {
    final raw = args['plan'];
    if (raw is! List) return null;
    final steps = <PlanStep>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final text = (item['step'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      steps.add(PlanStep(text, _status(item['status'])));
    }
    return steps.isEmpty ? null : TaskPlan(List.unmodifiable(steps));
  }

  static PlanStepStatus _status(Object? raw) => switch (raw) {
    'completed' => PlanStepStatus.completed,
    'in_progress' => PlanStepStatus.inProgress,
    _ => PlanStepStatus.pending,
  };
}

/// Latest plan per conversation, for the plan strip above the composer.
class TaskPlanRegistry extends ChangeNotifier {
  final Map<String, TaskPlan> _plans = <String, TaskPlan>{};

  TaskPlan? of(String? conversationId) =>
      conversationId == null ? null : _plans[conversationId];

  void set(String conversationId, TaskPlan plan) {
    _plans[conversationId] = plan;
    notifyListeners();
  }

  void clear(String conversationId) {
    if (_plans.remove(conversationId) != null) notifyListeners();
  }
}
