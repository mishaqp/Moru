import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/animations/widgets.dart';

import '../../../core/services/browser/browser_agent_session.dart';
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
    this.updates,
    this.readSteps,
    this.readResponseRunning,
  });

  static const panelKey = ValueKey('computer-status-panel');
  static const previousKey = ValueKey('computer-status-previous');
  static const nextKey = ValueKey('computer-status-next');

  final List<ComputerStep> steps;
  final bool generating;
  final String? conversationId;
  final Listenable? updates;
  final List<ComputerStep> Function()? readSteps;
  final bool Function()? readResponseRunning;

  @override
  State<ComputerStatusPanel> createState() => _ComputerStatusPanelState();
}

class _ComputerStatusPanelState extends State<ComputerStatusPanel> {
  final _selection = ComputerStepSelection();
  Timer? _elapsed;
  List<Listenable> _runUpdates = const [];

  @override
  void initState() {
    super.initState();
    _selection.update(widget.steps);
    _listenToRuns();
  }

  @override
  void didUpdateWidget(ComputerStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection.update(widget.steps);
    _listenToRuns();
  }

  void _listenToRuns() {
    for (final run in _runUpdates) {
      run.removeListener(_refresh);
    }
    _runUpdates = widget.steps
        .map((step) => step.run)
        .nonNulls
        .toSet()
        .toList();
    for (final run in _runUpdates) {
      run.addListener(_refresh);
    }
    _syncElapsed();
  }

  void _syncElapsed() {
    final running =
        widget.generating &&
        !widget.steps.any((step) => step.responseStopped) &&
        widget.steps.any((step) => step.run != null && step.isRunning);
    if (running) {
      _elapsed ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _elapsed?.cancel();
      _elapsed = null;
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _selection.update(widget.steps));
    _syncElapsed();
  }

  @override
  void dispose() {
    _elapsed?.cancel();
    for (final run in _runUpdates) {
      run.removeListener(_refresh);
    }
    super.dispose();
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
        readResponseRunning: widget.readResponseRunning,
      ),
    );
  }

  /// A running browser step may not name its page yet (the URL arrives with
  /// its result), so the shared browser of this chat supplies it meanwhile.
  bool _ownsLiveBrowser(ComputerStep step) =>
      step.kind == ComputerStepKind.browser &&
      step.isRunning &&
      widget.conversationId != null &&
      BrowserAgentSession.instance.ownerConversationId == widget.conversationId;

  String _title(ComputerStep step, AppLocalizations l10n) {
    if (step.browserDomain == null && _ownsLiveBrowser(step)) {
      final host = computerActionUri(
        BrowserAgentSession.instance.pageUrl.value,
      )?.host;
      if (host != null) return l10n.computerBrowserStep(host);
    }
    return step.title(l10n);
  }

  String _subtitle(ComputerStep step, AppLocalizations l10n) {
    if (_ownsLiveBrowser(step)) {
      final activity = BrowserAgentSession.instance.currentActivity.value;
      if (activity != null &&
          activity.outcome == BrowserActivityOutcome.running) {
        return l10n.computerBrowserAction(activity.action);
      }
    }
    return step.subtitle(l10n);
  }

  @override
  Widget build(BuildContext context) {
    final step = _selection.selected;
    if (step == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final active =
        widget.generating && !widget.steps.any((s) => s.responseStopped);
    final stopped = widget.steps.any((s) => s.isStopped || s.responseStopped);
    final error = widget.steps.any((s) => s.isError);
    final summary = stopped
        ? l10n.computerStopped
        : error
        ? l10n.computerError
        : widget.steps.every((s) => s.isBackground && s.isRunning)
        ? l10n.computerBackground
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
          child: !active
              ? SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          stopped
                              ? Lucide.Square
                              : error
                              ? Lucide.TriangleAlert
                              : Lucide.Check,
                          size: 18,
                          color: error && !stopped
                              ? cs.error
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$summary · ${l10n.computerActionsCount(widget.steps.length)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: error && !stopped
                                  ? cs.error
                                  : cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.computerViewAction,
                          style: TextStyle(fontSize: 12, color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        AnimatedIconSwap(
                          child: ComputerStepThumbnail(
                            key: ValueKey(step.id),
                            step: step,
                            conversationId: widget.conversationId,
                            width: 76,
                            height: 56,
                            borderRadius: 10,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title(step, l10n),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1,
                                  fontFamily:
                                      step.kind == ComputerStepKind.command
                                      ? 'monospace'
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _subtitle(step, l10n),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1,
                                  color: step.isError
                                      ? cs.error
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(
                                width: 148,
                                height: 48,
                                child: Row(
                                  children: [
                                    IconButton(
                                      key: ComputerStatusPanel.previousKey,
                                      tooltip: l10n.computerPreviousStep,
                                      icon: const Icon(
                                        Lucide.ChevronLeft,
                                        size: 18,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 48,
                                            height: 48,
                                          ),
                                      style: IconButton.styleFrom(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: _selection.index > 0
                                          ? () => setState(
                                              () => _selection.select(
                                                _selection.index - 1,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${_selection.index + 1} / ${widget.steps.length}',
                                          maxLines: 1,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: ComputerStatusPanel.nextKey,
                                      tooltip: l10n.computerNextStep,
                                      icon: const Icon(
                                        Lucide.ChevronRight,
                                        size: 18,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 48,
                                            height: 48,
                                          ),
                                      style: IconButton.styleFrom(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed:
                                          _selection.index <
                                              widget.steps.length - 1
                                          ? () => setState(
                                              () => _selection.select(
                                                _selection.index + 1,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
