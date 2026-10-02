import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/workspace/task_plan.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../chat/models/computer_step.dart';
import '../../chat/widgets/computer_response_scope.dart';
import 'computer_status_panel.dart';
import 'task_plan_bar.dart';

/// One action strip above the composer, with the existing task plan nearby.
/// Finished responses briefly show their final result; background jobs retain
/// access while running. All controllers remain owned by their existing hosts.
class ComposerStatusStrip extends StatefulWidget {
  const ComposerStatusStrip({
    super.key,
    required this.conversationId,
    required this.generating,
    this.steps,
    this.responseId,
    this.onStop,
  });

  static const resultDuration = Duration(seconds: 4);

  final String? conversationId;
  final bool generating;
  final List<ComputerStep>? steps;
  final String? responseId;
  final VoidCallback? onStop;

  @override
  State<ComposerStatusStrip> createState() => _ComposerStatusStripState();
}

class _ComposerStatusStripState extends State<ComposerStatusStrip> {
  bool _planOpen = false;
  bool _showCompleted = false;
  bool _stopping = false;
  Set<String> _stoppedRunIds = const {};
  String? _responseId;
  Timer? _collapse;

  static T? _watch<T>(BuildContext context) {
    try {
      return Provider.of<T>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void didUpdateWidget(ComposerStatusStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _collapse?.cancel();
      _responseId = null;
      _showCompleted = false;
      _planOpen = false;
      _stopping = false;
    } else if (oldWidget.generating && !widget.generating) {
      _showCompleted = true;
      _collapse?.cancel();
      _collapse = Timer(ComposerStatusStrip.resultDuration, () {
        if (mounted) setState(() => _showCompleted = false);
      });
    } else if (!oldWidget.generating && widget.generating) {
      _collapse?.cancel();
      _showCompleted = false;
      _stopping = false;
    }
  }

  @override
  void dispose() {
    _collapse?.cancel();
    super.dispose();
  }

  void _stop(ComputerToolSource? source, List<ToolRun> runs) {
    if (_stopping) return;
    setState(() {
      _stopping = true;
      _stoppedRunIds = {for (final run in runs) run.runtimeRunId};
    });
    if (widget.generating) (widget.onStop ?? source?.onStop)?.call();
    final browser = BrowserAgentSession.instance;
    if (browser.ownerConversationId == widget.conversationId) {
      browser.requestStop();
    }
    WorkspaceRuntimeProvider? provider;
    try {
      provider = context.read<WorkspaceRuntimeProvider>();
    } on ProviderNotFoundException {
      provider = null;
    }
    final runtime = provider?.runtime;
    if (runtime != null) {
      for (final run in runs) {
        unawaited(runtime.cancel(run.runtimeRunId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ComputerToolSource.maybeOf(context);
    final registry = _watch<ToolRunRegistry>(context);
    final plan = _watch<TaskPlanRegistry>(context)?.of(widget.conversationId);
    final openPlan = widget.generating && plan != null && !plan.isDone
        ? plan
        : null;
    final browser = BrowserAgentSession.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        if (source != null) source.updates,
        browser.minimized,
        browser.currentActivity,
      ]),
      builder: (context, _) {
        final responseId =
            widget.responseId ??
            (source == null
                ? null
                : latestComputerResponseId(source.readMessages()));
        if (_responseId != responseId) {
          _responseId = responseId;
          _showCompleted = false;
          _stopping = false;
          _collapse?.cancel();
        }
        final runs =
            registry?.runningIn(widget.conversationId) ?? const <ToolRun>[];
        if (_stopping &&
            !widget.generating &&
            runs.any((run) => !_stoppedRunIds.contains(run.runtimeRunId))) {
          _stopping = false;
        }
        // These identities belong to the response that opens the sheet.
        // The composer may switch chats while that route is still visible.
        final conversationId = widget.conversationId;
        final suppliedSteps = widget.steps;
        final suppliedResponseId = widget.responseId;
        final retainedRuns = {for (final run in runs) run.runtimeRunId: run};
        List<ComputerStep> readSteps() {
          final sameResponse =
              widget.conversationId == conversationId &&
              widget.responseId == suppliedResponseId;
          var steps = withComputerRuns(
            (sameResponse ? widget.steps : suppliedSteps) ??
                (responseId == null
                    ? const []
                    : source?.readSteps(responseId) ?? const []),
            registry,
            conversationId,
          );
          final ids = steps.map((step) => step.id).toSet();
          final representedRuns = steps
              .map((step) => step.run?.runtimeRunId)
              .toSet();
          for (final run
              in registry?.runningIn(conversationId) ?? const <ToolRun>[]) {
            retainedRuns[run.runtimeRunId] = run;
          }
          final background = retainedRuns.values.toList()
            ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
          steps = [
            // Prior jobs precede this reply's steps, so they cannot steal
            // automatic selection from the newest action of this reply.
            for (final run in background)
              if (!ids.contains(run.runtimeRunId) &&
                  !representedRuns.contains(run.runtimeRunId))
                ComputerStep(
                  id: run.runtimeRunId,
                  toolName: run.toolName,
                  arguments: {if (run.command != null) 'command': run.command},
                  run: run,
                ),
            ...steps,
          ];
          if (steps.isEmpty &&
              browser.minimized.value &&
              browser.ownerConversationId == conversationId &&
              responseId == null) {
            steps = [
              ComputerStep(
                id: 'parked-browser',
                toolName: 'browser_use',
                arguments: {
                  'action': 'observe',
                  if (browser.pageUrl.value != null)
                    'url': browser.pageUrl.value,
                },
                loading:
                    browser.currentActivity.value?.outcome ==
                    BrowserActivityOutcome.running,
              ),
            ];
          }
          return steps;
        }

        final steps = readSteps();
        final showComputer =
            steps.isNotEmpty &&
            (widget.generating ||
                _showCompleted ||
                runs.isNotEmpty ||
                (responseId == null && browser.minimized.value));
        Widget? content;
        if (openPlan != null || showComputer) {
          final cs = Theme.of(context).colorScheme;
          final panel = showComputer
              ? ComputerStatusPanel(
                  key: ValueKey((widget.conversationId, responseId)),
                  steps: steps,
                  generating: widget.generating,
                  conversationId: widget.conversationId,
                  onStop: _stopping ? null : () => _stop(source, runs),
                  updates: Listenable.merge([
                    if (source != null) source.updates,
                    if (registry != null) registry,
                  ]),
                  readSteps: readSteps,
                )
              : null;
          final chip = openPlan == null
              ? null
              : TaskPlanChip(
                  plan: openPlan,
                  expanded: _planOpen,
                  onTap: () => setState(() => _planOpen = !_planOpen),
                );
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (chip != null &&
                        panel != null &&
                        constraints.maxWidth >= 600) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: chip),
                          const SizedBox(width: 6),
                          Expanded(flex: 2, child: panel),
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (chip != null) chip,
                        if (chip != null && panel != null)
                          const SizedBox(height: 6),
                        if (panel != null) panel,
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        }
        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.hardEdge,
          child: content ?? const SizedBox(width: double.infinity),
        );
      },
    );
  }
}
