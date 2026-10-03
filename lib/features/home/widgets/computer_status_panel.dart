import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/models/computer_step.dart';
import '../../chat/models/computer_step_selection.dart';
import '../../chat/widgets/chat_surface.dart';
import '../../chat/widgets/computer_sheet.dart';
import '../../chat/widgets/computer_browser_action.dart';
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
      step.allowsBrowserPreview &&
      step.isRunning &&
      widget.generating &&
      !step.responseStopped &&
      widget.conversationId != null &&
      BrowserAgentSession.instance.ownerConversationId ==
          widget.conversationId &&
      (step.browserDomain == null ||
          step.browserDomain ==
              computerActionUri(
                BrowserAgentSession.instance.pageUrl.value,
              )?.host) &&
      (step.browserPageKey == null ||
          step.browserPageKey ==
              BrowserAgentSession.instance.currentActivity.value?.pageKey);

  Uri? _livePage(ComputerStep step) {
    final url = BrowserAgentSession.instance.pageUrl.value;
    return _ownsLiveBrowser(step) && step.canPreviewBrowserPage(url)
        ? computerActionUri(url)
        : null;
  }

  String _title(ComputerStep step, AppLocalizations l10n, String? domain) {
    return step.kind == ComputerStepKind.browser && domain != null
        ? l10n.computerBrowserStep(domain)
        : step.title(l10n);
  }

  String _subtitle(ComputerStep step, AppLocalizations l10n) {
    if (_ownsLiveBrowser(step)) {
      final activity = BrowserAgentSession.instance.currentActivity.value;
      if (activity != null &&
          activity.outcome == BrowserActivityOutcome.running) {
        return switch (activity.action) {
          'navigate' || 'open' || 'new_tab' => l10n.computerBrowserOpening,
          'click' || 'tap' => l10n.computerBrowserClicking,
          'type' || 'fill' => l10n.computerBrowserTyping,
          'read' || 'observe' || 'outline' => l10n.computerBrowserReading,
          _ => l10n.computerBrowserAction(activity.action),
        };
      }
    }
    return step.subtitle(l10n);
  }

  Widget _workingCard(ComputerStep step, AppLocalizations l10n) {
    final session = BrowserAgentSession.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([session.pageUrl, session.currentActivity]),
      builder: (context, _) {
        final browser = step.kind == ComputerStepKind.browser;
        final liveUrl = _livePage(step);
        final domain =
            step.browserDomain ??
            liveUrl?.host ??
            step.browserDomainInResponse(widget.steps);
        final activity = liveUrl != null ? session.currentActivity.value : null;
        final stopped = step.isStopped || step.responseStopped;
        final running = step.isRunning && !stopped;
        final cs = Theme.of(context).colorScheme;
        final color = stopped
            ? const Color(0xFF9CA3AF)
            : step.isError
            ? const Color(0xFFEF4444)
            : running
            ? const Color(0xFF3B82F6)
            : const Color(0xFF22C55E);
        Widget dot = DecoratedBox(
          key: ValueKey(
            browser ? 'computer-browser-status-dot' : 'computer-status-dot',
          ),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 6, height: 6),
        );
        if (running && !MediaQuery.disableAnimationsOf(context)) {
          dot = dot
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fade(begin: 1, end: 0.35, duration: 800.ms);
        }
        final thumbnail = ComputerStepThumbnail(
          key: ValueKey(step.id),
          step: step,
          conversationId: widget.conversationId,
          width: 64,
          height: 40,
          borderRadius: 10,
          browserDomain: domain,
          browserPageUrl: liveUrl?.toString(),
          browserPageKey: activity?.pageKey,
          browserStartedAt: activity?.startedAt,
          browserActivityId: activity?.id,
        );
        return SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                if (browser)
                  Semantics(
                    button: true,
                    label: l10n.computerOpenBrowser,
                    child: Tooltip(
                      message: l10n.computerOpenBrowser,
                      child: GestureDetector(
                        key: const ValueKey('computer-browser-preview'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(
                          openComputerStepBrowser(
                            step,
                            conversationId: widget.conversationId,
                          ),
                        ),
                        child: thumbnail,
                      ),
                    ),
                  )
                else
                  thumbnail,
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(step, l10n, domain),
                        key: browser
                            ? const ValueKey('computer-browser-title')
                            : null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.1,
                          fontFamily: step.kind == ComputerStepKind.command
                              ? 'monospace'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              dot,
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  stopped
                                      ? l10n.computerStopped
                                      : _subtitle(step, l10n),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.1,
                                    color: step.isError
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _navigation(l10n),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navigation(AppLocalizations l10n) => SizedBox(
    width: 120,
    height: 48,
    child: Row(
      children: [
        IconButton(
          key: ComputerStatusPanel.previousKey,
          tooltip: l10n.computerPreviousStep,
          icon: const Icon(Lucide.ChevronLeft, size: 16),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 8),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _selection.index > 0
              ? () => setState(() => _selection.select(_selection.index - 1))
              : null,
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${_selection.index + 1}/${widget.steps.length}',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, height: 1.1),
            ),
          ),
        ),
        IconButton(
          key: ComputerStatusPanel.nextKey,
          tooltip: l10n.computerNextStep,
          icon: const Icon(Lucide.ChevronRight, size: 16),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 8),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _selection.index < widget.steps.length - 1
              ? () => setState(() => _selection.select(_selection.index + 1))
              : null,
        ),
      ],
    ),
  );

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
              : _workingCard(step, l10n),
        ),
      ),
    );
  }
}
