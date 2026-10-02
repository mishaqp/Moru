import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/workspace/file_link_resolver.dart';
import '../../../core/services/workspace/workspace_tool_metadata.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/pages/webview/browser_mini_window.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../workspace/workspace_file_navigation.dart';
import '../../workspace/workspace_navigation.dart';
import '../models/computer_step.dart';
import '../models/computer_step_selection.dart';
import 'chat_surface.dart';
import 'computer_step_thumbnail.dart';
import 'unified_diff_view.dart';

Future<void> showComputerSheet(
  BuildContext context, {
  required List<ComputerStep> steps,
  String? conversationId,
  String? initialStepId,
  Listenable? updates,
  List<ComputerStep> Function()? readSteps,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, _) => ComputerSheet(
      steps: steps,
      conversationId: conversationId,
      initialStepId: initialStepId,
      updates: updates,
      readSteps: readSteps,
      actionContext: context,
      onDismiss: () {
        final route = ModalRoute.of(dialogContext);
        if (route != null && route.isActive) {
          Navigator.of(dialogContext).removeRoute(route);
        }
      },
    ),
  );
}

/// The shared Computer panel, also usable directly for visual previews.
class ComputerSheet extends StatefulWidget {
  const ComputerSheet({
    super.key,
    required this.steps,
    this.conversationId,
    this.initialStepId,
    this.updates,
    this.readSteps,
    this.actionContext,
    this.onDismiss,
  });

  final List<ComputerStep> steps;
  final String? conversationId;
  final String? initialStepId;
  final Listenable? updates;
  final List<ComputerStep> Function()? readSteps;
  final BuildContext? actionContext;
  final VoidCallback? onDismiss;

  @override
  State<ComputerSheet> createState() => _ComputerSheetState();
}

class _ComputerSheetState extends State<ComputerSheet> {
  final ComputerStepSelection _selection = ComputerStepSelection();
  final Set<Listenable> _sources = {};
  List<ComputerStep> _steps = [];
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _read();
    final index = _steps.indexWhere((step) => step.id == widget.initialStepId);
    if (index >= 0) _selection.select(index);
  }

  @override
  void didUpdateWidget(covariant ComputerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _selection.update([]);
    }
    _read();
    if (oldWidget.initialStepId != widget.initialStepId) {
      final index = _steps.indexWhere(
        (step) => step.id == widget.initialStepId,
      );
      if (index >= 0) _selection.select(index);
    }
  }

  void _read() {
    _steps = List<ComputerStep>.of(widget.readSteps?.call() ?? widget.steps);
    _selection.update(_steps);
    final nextSources = <Listenable>{
      if (widget.updates != null) widget.updates!,
      for (final step in _steps)
        if (step.run != null) step.run!,
    };
    for (final source in _sources.difference(nextSources)) {
      source.removeListener(_refresh);
    }
    for (final source in nextSources.difference(_sources)) {
      source.addListener(_refresh);
    }
    _sources
      ..clear()
      ..addAll(nextSources);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_read);
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.removeListener(_refresh);
    }
    super.dispose();
  }

  void _dismiss() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedPadding(
      duration: kAnimFast,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CustomBottomSheet(
        title: l10n.computerTitle,
        closeSemanticLabel: l10n.commonClose,
        partialHeightFactor: 0.85,
        expandedHeightFactor: 0.85,
        onDismiss: _dismiss,
        builder: (context, scrollController) =>
            _body(context, scrollController),
      ),
    );
  }

  Widget _body(BuildContext context, ScrollController scrollController) {
    final step = _selection.selected;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (step == null) {
      return Center(
        child: Text(
          l10n.computerNoResult,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
          child: Row(
            children: [
              AnimatedIconSwap(
                child: Icon(
                  step.icon,
                  key: ValueKey(step.kind),
                  size: 22,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.title(l10n),
                  key: const ValueKey('computer-step-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('computer-header-action'),
                tooltip: _actionLabel(step, l10n),
                onPressed: _opening || !_canOpen(step)
                    ? null
                    : () => unawaited(_open(step)),
                icon: Icon(_actionIcon(step.kind), size: 20),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
        ),
        Expanded(
          child: SelectionArea(
            child: ListView(
              key: ValueKey('computer-step-body:${step.id}'),
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              children: [
                if (step.kind == ComputerStepKind.browser ||
                    step.kind == ComputerStepKind.image ||
                    step.imagePath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) => ComputerStepThumbnail(
                        step: step,
                        conversationId: widget.conversationId,
                        width: constraints.maxWidth,
                        height: math.min(220, constraints.maxWidth * 0.58),
                      ),
                    ),
                  ),
                if (_actionText(step).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _actionText(step),
                      key: const ValueKey('computer-step-action'),
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: chatSurfacePlainTextColor(context),
                      ),
                    ),
                  ),
                if (step.parameters.isNotEmpty && step.parameters != '{}')
                  _ComputerSection(
                    label: l10n.computerParameters,
                    text: step.parameters,
                  ),
                _ComputerSection(
                  label: l10n.computerResult,
                  text: step.result.isEmpty
                      ? l10n.computerNoResult
                      : step.result,
                  textKey: const ValueKey('computer-step-result'),
                ),
                if (_diffOf(step) case final String diff when diff.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: UnifiedDiffView(diff: diff, showHeader: true),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('computer-previous-step'),
                tooltip: l10n.computerPreviousStep,
                onPressed: _selection.index <= 0
                    ? null
                    : () => _select(_selection.index - 1, scrollController),
                icon: const Icon(Lucide.ChevronLeft, size: 20),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${_selection.index + 1} / ${_steps.length}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('computer-next-step'),
                tooltip: l10n.computerNextStep,
                onPressed: _selection.index >= _steps.length - 1
                    ? null
                    : () => _select(_selection.index + 1, scrollController),
                icon: const Icon(Lucide.ChevronRight, size: 20),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
              IconButton(
                key: const ValueKey('computer-latest-step'),
                tooltip: l10n.computerLatest,
                onPressed: () {
                  setState(_selection.latest);
                  if (scrollController.hasClients) scrollController.jumpTo(0);
                },
                icon: const Icon(Lucide.ArrowDownToLine, size: 20),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
        ),
        _ComputerStatus(step: step),
      ],
    );
  }

  void _select(int index, ScrollController scrollController) {
    setState(() => _selection.select(index));
    if (scrollController.hasClients) scrollController.jumpTo(0);
  }

  bool _canOpen(ComputerStep step) => switch (step.kind) {
    ComputerStepKind.file => _fileLink(step) != null,
    ComputerStepKind.browser || ComputerStepKind.command => true,
    ComputerStepKind.image || ComputerStepKind.tool => step.result.isNotEmpty,
  };

  Future<void> _open(ComputerStep step) async {
    if (_opening) return;
    setState(() => _opening = true);
    final actionContext = widget.actionContext ?? context;
    try {
      switch (step.kind) {
        case ComputerStepKind.command:
          _dismiss();
          if (actionContext.mounted) {
            WorkspaceNavigation.openTerminal(
              actionContext,
              command: step.run?.command ?? step.command,
            );
          }
        case ComputerStepKind.browser:
          _dismiss();
          await _openBrowser(step);
        case ComputerStepKind.file:
          final link = _fileLink(step);
          _dismiss();
          if (actionContext.mounted && link != null) {
            await openWorkspaceLinkedFile(
              actionContext,
              link,
              conversationId: widget.conversationId,
            );
          }
        case ComputerStepKind.image:
        case ComputerStepKind.tool:
          await Clipboard.setData(
            ClipboardData(text: sanitizeComputerDisplayText(step.result)),
          );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openBrowser(ComputerStep step) async {
    final session = BrowserAgentSession.instance;
    final result = _resultMap(step);
    final target = computerActionUri(
      (result['url'] ?? step.arguments['url'])?.toString(),
    );
    if (session.isAttached) {
      // Switching tabs reuses the saved controller; never reload a live page
      // merely because its historical Computer step was opened.
      if (session.ownerConversationId == null ||
          session.ownerConversationId == widget.conversationId) {
        final tabId = result['tab_id'] ?? step.arguments['tab_id'];
        final tab = session.tabs.value
            .where(
              (tab) =>
                  (tabId != null && tab.id == tabId.toString()) ||
                  (target != null && computerActionUri(tab.url) == target),
            )
            .firstOrNull;
        if (tab != null && !tab.active && computerActionUri(tab.url) != null) {
          await session.switchTab(tab.id);
        }
      }
      await openSharedBrowser();
    } else if (target != null) {
      await openSharedBrowser(startUrl: target.toString());
    } else {
      await openSharedBrowser();
    }
  }
}

String _actionLabel(ComputerStep step, AppLocalizations l10n) =>
    switch (step.kind) {
      ComputerStepKind.command => l10n.computerOpenTerminal,
      ComputerStepKind.browser => l10n.computerOpenBrowser,
      ComputerStepKind.file => l10n.computerOpenFile,
      ComputerStepKind.image ||
      ComputerStepKind.tool => l10n.computerCopyResult,
    };

IconData _actionIcon(ComputerStepKind kind) => switch (kind) {
  ComputerStepKind.command => Lucide.Terminal,
  ComputerStepKind.browser => Lucide.ExternalLink,
  ComputerStepKind.file => Lucide.FileSearch,
  ComputerStepKind.image || ComputerStepKind.tool => Lucide.Copy,
};

Map<String, dynamic> _resultMap(ComputerStep step) {
  try {
    final decoded = jsonDecode(step.content ?? '');
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  } catch (_) {
    return {};
  }
}

String _actionText(ComputerStep step) => switch (step.kind) {
  ComputerStepKind.command => step.command ?? '',
  ComputerStepKind.file || ComputerStepKind.image => step.path ?? '',
  ComputerStepKind.browser => [
    step.arguments['action'],
    _resultMap(step)['url'] ?? step.arguments['url'],
  ].where((part) => part != null && part.toString().isNotEmpty).join(' · '),
  ComputerStepKind.tool => '',
};

String? _fileLink(ComputerStep step) {
  final meta = step.metadata;
  if (meta != null) {
    try {
      for (final file in WorkspaceToolMetadata.fromJson(meta).files) {
        final link = file.link;
        final parsed = link == null ? null : KelivoLink.tryParse(link);
        if (parsed != null &&
            parsed.kind != KelivoLinkKind.terminal &&
            !link!.contains('[REDACTED]') &&
            !link.contains('***(len=') &&
            !parsed.relativePath.contains('[REDACTED]') &&
            !parsed.relativePath.contains('***(len=')) {
          return link;
        }
      }
    } catch (_) {
      // Old tool metadata can omit the typed workspace envelope.
    }
  }
  final path = step.actionPath;
  if (path == null) return null;
  final parsed = KelivoLink.tryParse(path);
  if (parsed != null && parsed.kind != KelivoLinkKind.terminal) return path;
  return KelivoLink.workspacePathSource(path).link;
}

String? _diffOf(ComputerStep step) {
  try {
    return step.metadata == null
        ? null
        : WorkspaceToolMetadata.fromJson(step.metadata!).diff;
  } catch (_) {
    return null;
  }
}

class _ComputerSection extends StatelessWidget {
  const _ComputerSection({
    required this.label,
    required this.text,
    this.textKey,
  });

  final String label;
  final String text;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: buildSharedChatSurface(
        context,
        borderRadius: BorderRadius.circular(12),
        padding: const EdgeInsets.all(12),
        defaultColor: cs.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              key: textKey,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: chatSurfacePlainTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComputerStatus extends StatelessWidget {
  const _ComputerStatus({required this.step});

  final ComputerStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final text = step.isRunning
        ? l10n.computerWorking
        : step.isError
        ? l10n.computerError
        : l10n.computerDone;
    final icon = step.isRunning
        ? Lucide.Loader
        : step.isError
        ? Lucide.CircleX
        : Lucide.CircleCheck;
    final color = step.isError
        ? cs.error
        : step.isRunning
        ? cs.primary
        : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            AnimatedIconSwap(
              child: Icon(icon, key: ValueKey(text), size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
