import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/animations/widgets.dart';
import 'package:path/path.dart' as p;

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/models/computer_step.dart';
import '../../chat/models/computer_step_selection.dart';
import '../../chat/widgets/chat_surface.dart';
import '../../chat/widgets/computer_sheet.dart';
import '../../chat/widgets/computer_step_thumbnail.dart';

/// The single compact surface for every tool used in a response.
class ComputerStatusPanel extends StatefulWidget {
  const ComputerStatusPanel({
    super.key,
    required this.steps,
    required this.generating,
    this.conversationId,
    this.onStop,
    this.updates,
    this.readSteps,
  });

  static const panelKey = ValueKey('computer-status-panel');
  static const previousKey = ValueKey('computer-status-previous');
  static const nextKey = ValueKey('computer-status-next');
  static const stopKey = ValueKey('computer-status-stop');

  final List<ComputerStep> steps;
  final bool generating;
  final String? conversationId;
  final VoidCallback? onStop;
  final Listenable? updates;
  final List<ComputerStep> Function()? readSteps;

  @override
  State<ComputerStatusPanel> createState() => _ComputerStatusPanelState();
}

class _ComputerStatusPanelState extends State<ComputerStatusPanel> {
  final _selection = ComputerStepSelection();

  @override
  void initState() {
    super.initState();
    _selection.update(widget.steps);
  }

  @override
  void didUpdateWidget(ComputerStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection.update(widget.steps);
  }

  void _open() {
    unawaited(
      showComputerSheet(
        context,
        steps: widget.steps,
        initialStepId: _selection.selected?.id,
        conversationId: widget.conversationId,
        updates: widget.updates,
        readSteps: widget.readSteps,
      ),
    );
  }

  String _label(ComputerStep step, AppLocalizations l10n) =>
      switch (step.kind) {
        ComputerStepKind.command when step.command?.isNotEmpty == true =>
          step.command!.trim().split('\n').first,
        ComputerStepKind.file when step.path?.isNotEmpty == true => p.basename(
          step.path!,
        ),
        _ => step.title(l10n),
      };

  @override
  Widget build(BuildContext context) {
    final step = _selection.selected;
    if (step == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final busy = widget.generating || widget.steps.any((s) => s.isRunning);
    final status = step.isRunning
        ? l10n.computerWorking
        : step.isError
        ? l10n.computerError
        : l10n.computerDone;

    return Material(
      key: ComputerStatusPanel.panelKey,
      type: MaterialType.transparency,
      child: buildSharedChatSurface(
        context,
        borderRadius: BorderRadius.circular(16),
        padding: EdgeInsets.zero,
        defaultColor: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 60,
                    height: 76,
                    child: AnimatedIconSwap(
                      child: ComputerStepThumbnail(
                        key: ValueKey(step.id),
                        step: step,
                        conversationId: widget.conversationId,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.computerTitle,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: step.isError
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _label(step, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: step.kind == ComputerStepKind.command
                              ? 'monospace'
                              : null,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            key: ComputerStatusPanel.previousKey,
                            tooltip: l10n.computerPreviousStep,
                            icon: const Icon(Lucide.ChevronLeft, size: 18),
                            onPressed: _selection.index > 0
                                ? () => setState(
                                    () =>
                                        _selection.select(_selection.index - 1),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: Text(
                              '${_selection.index + 1} / ${widget.steps.length}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          IconButton(
                            key: ComputerStatusPanel.nextKey,
                            tooltip: l10n.computerNextStep,
                            icon: const Icon(Lucide.ChevronRight, size: 18),
                            onPressed:
                                _selection.index < widget.steps.length - 1
                                ? () => setState(
                                    () =>
                                        _selection.select(_selection.index + 1),
                                  )
                                : null,
                          ),
                          if (busy)
                            TextButton(
                              key: ComputerStatusPanel.stopKey,
                              onPressed: widget.onStop,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                foregroundColor: cs.error,
                              ),
                              child: Text(l10n.computerStop),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
