import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../../../core/services/workspace/task_plan.dart';
import '../../../core/services/workspace/file_link_resolver.dart';
import '../../../core/services/workspace/workspace_tool_metadata.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../workspace/workspace_file_navigation.dart';
import '../../workspace/workspace_navigation.dart';
import '../models/computer_step.dart';
import '../models/computer_step_selection.dart';
import 'chat_surface.dart';
import 'computer_browser_action.dart';
import 'computer_step_thumbnail.dart';
import 'unified_diff_view.dart';

Future<void> showComputerSheet(
  BuildContext context, {
  required List<ComputerStep> steps,
  String? conversationId,
  String? initialStepId,
  Listenable? updates,
  List<ComputerStep> Function()? readSteps,
  bool Function()? readResponseRunning,
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
      readResponseRunning: readResponseRunning,
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
    this.readResponseRunning,
    this.actionContext,
    this.onDismiss,
  });

  final List<ComputerStep> steps;
  final String? conversationId;
  final String? initialStepId;
  final Listenable? updates;
  final List<ComputerStep> Function()? readSteps;
  final bool Function()? readResponseRunning;
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
  bool _followOutput = true;
  String? _outputStepId;
  String? _lastOutput;

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
        headerBuilder: _header,
        builder: (context, scrollController) =>
            _body(context, scrollController),
      ),
    );
  }

  Widget _header(BuildContext context, VoidCallback onClose) {
    final l10n = AppLocalizations.of(context)!;
    final step = _selection.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            key: CustomBottomSheet.closeButtonKey,
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: l10n.commonClose,
              onPressed: onClose,
              icon: const Icon(Lucide.X, size: 20),
            ),
          ),
          Expanded(
            child: Text(
              l10n.computerTitle,
              key: const ValueKey('computer-sheet-title'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child:
                step != null &&
                    const {
                      ComputerStepKind.command,
                      ComputerStepKind.browser,
                      ComputerStepKind.file,
                    }.contains(step.kind)
                ? IconButton(
                    key: const ValueKey('computer-header-action'),
                    tooltip: _actionLabel(step, l10n),
                    onPressed: _opening || !_canOpen(step)
                        ? null
                        : () => unawaited(_open(step)),
                    icon: Icon(_actionIcon(step.kind), size: 20),
                  )
                : null,
          ),
        ],
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
    _followCommandOutput(step, scrollController);
    final responseStopped = _steps.any((s) => s.responseStopped);
    final responseRunning =
        !responseStopped &&
        (widget.readResponseRunning?.call() ??
            _steps.any((s) => s.isRunning && !s.isBackground));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _actionField(context, step, l10n),
        Expanded(
          child: SelectionArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (step.kind != ComputerStepKind.command) return false;
                if (notification is UserScrollNotification &&
                    notification.direction == ScrollDirection.forward) {
                  _followOutput = false;
                } else if (notification is ScrollEndNotification &&
                    notification.metrics.extentAfter < 32) {
                  _followOutput = true;
                }
                return false;
              },
              child: CustomScrollView(
                key: ValueKey('computer-step-body:${step.id}'),
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    sliver: SliverList.list(
                      children: [
                        _parameters(context, step, l10n),
                        if (step.kind == ComputerStepKind.browser ||
                            step.kind == ComputerStepKind.image ||
                            step.imagePath != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  ComputerStepThumbnail(
                                    step: step,
                                    conversationId: widget.conversationId,
                                    hideBrowserPlaceholder: true,
                                    width: constraints.maxWidth,
                                    height: math.min(
                                      220,
                                      constraints.maxWidth * 0.58,
                                    ),
                                  ),
                            ),
                          ),
                        if (step.isPlan && step.plan != null)
                          _ComputerPlan(plan: step.plan!)
                        else if (step.kind == ComputerStepKind.browser)
                          _browserResult(context, step, l10n)
                        else if (step.kind != ComputerStepKind.command)
                          _ComputerSection(
                            label: l10n.computerResult,
                            text: step.result.isEmpty
                                ? l10n.computerNoResult
                                : step.result,
                            textKey: const ValueKey('computer-step-result'),
                          ),
                        if (_diffOf(step) case final String diff
                            when diff.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: UnifiedDiffView(
                              diff: diff,
                              showHeader: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (step.kind == ComputerStepKind.command)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      sliver: SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ComputerTerminal(
                          output: step.result.isNotEmpty
                              ? step.result
                              : step.command == null
                              ? (step.isStopped
                                    ? l10n.computerStopped
                                    : l10n.computerNoResult)
                              : '\$ ${step.command}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _ComputerStatus(
          step: step,
          responseStopped: responseStopped,
          responseRunning: responseRunning,
          position: l10n.computerStepPosition(
            _selection.index + 1,
            _steps.length,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('computer-previous-step'),
                    tooltip: l10n.computerPreviousStep,
                    onPressed: _selection.index <= 0
                        ? null
                        : () => _select(_selection.index - 1, scrollController),
                    icon: const Icon(Lucide.ChevronLeft, size: 20),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                  SizedBox(
                    width: 54,
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
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                ],
              ),
              Tooltip(
                message: l10n.computerCopyResult,
                child: TextButton.icon(
                  key: const ValueKey('computer-copy-result'),
                  onPressed: step.result.isEmpty && step.plan == null
                      ? null
                      : () => unawaited(_copy(step)),
                  icon: const Icon(Lucide.Copy, size: 18),
                  label: Text(l10n.computerCopyResult),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
              ),
              if (_selection.index < _steps.length - 1)
                TextButton.icon(
                  key: const ValueKey('computer-latest-step'),
                  onPressed: () {
                    setState(_selection.latest);
                    _followOutput = true;
                    _outputStepId = null;
                  },
                  icon: const Icon(Lucide.ChevronDown, size: 18),
                  label: Text(l10n.computerLatest),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionField(
    BuildContext context,
    ComputerStep step,
    AppLocalizations l10n,
  ) {
    final cs = Theme.of(context).colorScheme;
    final text = _actionText(step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                step.actionLabel(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurface),
              ),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text(
                text,
                key: const ValueKey('computer-step-action'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: step.kind == ComputerStepKind.command
                      ? 'monospace'
                      : null,
                  color: chatSurfacePlainTextColor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _select(int index, ScrollController scrollController) {
    _followOutput = true;
    _outputStepId = null;
    setState(() => _selection.select(index));
    if (scrollController.hasClients) scrollController.jumpTo(0);
  }

  void _followCommandOutput(ComputerStep step, ScrollController controller) {
    if (step.kind != ComputerStepKind.command) return;
    if (_outputStepId != step.id) {
      _outputStepId = step.id;
      _lastOutput = null;
      _followOutput = true;
    }
    final output = step.result;
    if (_lastOutput == output) return;
    _lastOutput = output;
    if (!_followOutput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_followOutput ||
          _selection.selected?.id != step.id ||
          !controller.hasClients) {
        return;
      }
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  Future<void> _copy(ComputerStep step) async {
    final output =
        step.plan?.steps
            .map(
              (item) =>
                  '${item.status == PlanStepStatus.completed ? '[x]' : '[ ]'} ${item.text}',
            )
            .join('\n') ??
        step.result;
    await Clipboard.setData(
      ClipboardData(text: sanitizeComputerDisplayText(output)),
    );
  }

  Widget _parameters(
    BuildContext context,
    ComputerStep step,
    AppLocalizations l10n,
  ) {
    final args = step.arguments;
    final fields = <(String, String)>[];
    final known = <String>{};
    void field(String label, List<String> keys, {bool primary = false}) {
      known.addAll(keys);
      if (primary) return;
      for (final key in keys) {
        final value = args[key];
        if (value == null) continue;
        final display = value is bool
            ? (value ? l10n.computerParameterYes : l10n.computerParameterNo)
            : value is Map || value is List
            ? jsonEncode(value)
            : value.toString();
        fields.add((label, display));
        return;
      }
    }

    if (step.kind == ComputerStepKind.command) {
      field(l10n.computerActionCommand, [
        'command',
        'cmd',
        'command_line',
      ], primary: true);
      field(l10n.computerParameterDirectory, [
        'cwd',
        'workdir',
        'working_directory',
      ]);
      field(l10n.computerParameterBackground, ['background']);
      field(l10n.computerParameterTimeout, [
        'timeout',
        'timeout_seconds',
        'timeout_ms',
      ]);
    } else if (step.kind == ComputerStepKind.browser) {
      field(l10n.computerParameterUrl, ['url'], primary: true);
      field(l10n.computerParameterSelector, ['selector', 'ref']);
      field(l10n.computerParameterText, ['text', 'value']);
      known.addAll(['action', 'summary']);
    } else if (step.kind == ComputerStepKind.file) {
      field(l10n.computerParameterPath, [
        'path',
        'file_path',
        'filePath',
      ], primary: true);
      field(l10n.computerParameterRange, [
        'range',
        'offset',
        'start_line',
        'line_start',
      ]);
      if (args['limit'] != null ||
          args['end_line'] != null ||
          args['line_end'] != null) {
        field(l10n.computerParameterRange, ['limit', 'end_line', 'line_end']);
      }
    } else if (step.isPlan) {
      known.add('plan');
    }
    final hasUnknown = args.keys.any((key) => !known.contains(key));
    final browserResult = step.kind == ComputerStepKind.browser
        ? _jsonResult(step).$2
        : null;
    final showBrowserJson = switch (browserResult) {
      Map() =>
        browserResult.isNotEmpty &&
            (args['action'] != 'done' ||
                browserResult.keys.any(
                  (key) => !const {'ok', 'action', 'summary'}.contains(key),
                )),
      List() => browserResult.isNotEmpty,
      String() => browserResult.trim().isNotEmpty,
      num() || bool() => true,
      _ => false,
    };
    if (fields.isEmpty && !hasUnknown && !showBrowserJson) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labeledFields(context, fields),
          if (hasUnknown || showBrowserJson)
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: ValueKey('computer-all-parameters:${step.id}'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  l10n.computerAllParameters,
                  style: const TextStyle(fontSize: 12),
                ),
                children: [
                  if (hasUnknown)
                    _ComputerSection(
                      label: l10n.computerParameters,
                      text: step.parameters,
                    ),
                  if (showBrowserJson)
                    _ComputerSection(
                      label: l10n.computerResult,
                      text: const JsonEncoder.withIndent(
                        '  ',
                      ).convert(browserResult),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _browserResult(
    BuildContext context,
    ComputerStep step,
    AppLocalizations l10n,
  ) {
    final (isJson, decoded) = _jsonResult(step);
    final result = decoded is Map ? decoded : const {};
    final summary = result['summary'] ?? step.arguments['summary'];
    if (step.arguments['action'] == 'done' || result.isEmpty) {
      final text = summary is String && summary.trim().isNotEmpty
          ? summary
          : !isJson && step.result.isNotEmpty
          ? step.result
          : l10n.computerNoResult;
      return _ComputerSection(
        label: l10n.computerResult,
        text: text,
        monospace: false,
        textKey: const ValueKey('computer-step-result'),
      );
    }
    final fields = <(String, String)>[
      if (result['ok'] case final bool ok)
        (
          l10n.computerBrowserResultStatus,
          ok
              ? l10n.computerBrowserResultSuccess
              : l10n.computerBrowserResultError,
        ),
      if (summary is String && summary.trim().isNotEmpty)
        (l10n.computerActionSummary, summary),
      if (result['title'] case final String title when title.isNotEmpty)
        (l10n.computerBrowserResultTitle, title),
      if (result['url'] case final String url when url.isNotEmpty)
        (l10n.computerParameterUrl, url),
      if (result['message'] ?? result['error'] case final String message
          when message.isNotEmpty)
        (l10n.computerResult, message),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _labeledFields(context, fields),
    );
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

  Future<void> _openBrowser(ComputerStep step) =>
      openComputerStepBrowser(step, conversationId: widget.conversationId);
}

Widget _labeledFields(BuildContext context, List<(String, String)> fields) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    field.$1,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    field.$2,
                    style: TextStyle(
                      fontSize: 12,
                      color: chatSurfacePlainTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

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
  final decoded = _jsonResult(step).$2;
  return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
}

(bool, Object?) _jsonResult(ComputerStep step) {
  try {
    return (true, jsonDecode(step.result));
  } on FormatException {
    return (false, null);
  }
}

String _actionText(ComputerStep step) => switch (step.kind) {
  ComputerStepKind.command => step.command ?? '',
  ComputerStepKind.file || ComputerStepKind.image => step.path ?? '',
  ComputerStepKind.browser =>
    (_resultMap(step)['url'] ??
            step.arguments['url'] ??
            step.arguments['selector'] ??
            '')
        .toString(),
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
    this.monospace = true,
  });

  final String label;
  final String text;
  final Key? textKey;
  final bool monospace;

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
                fontFamily: monospace ? 'monospace' : null,
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
  const _ComputerStatus({
    required this.step,
    required this.position,
    required this.responseStopped,
    required this.responseRunning,
  });

  final ComputerStep step;
  final String position;
  final bool responseStopped;
  final bool responseRunning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final stopped = responseStopped || step.isStopped;
    final working = responseRunning && step.isRunning && !step.isBackground;
    final text = stopped
        ? l10n.computerStopped
        : working
        ? l10n.computerWorking
        : step.isError
        ? l10n.computerError
        : step.isRunning && step.isBackground
        ? l10n.computerBackground
        : l10n.computerDone;
    final icon = stopped
        ? Lucide.Square
        : working
        ? Lucide.Loader
        : step.isError
        ? Lucide.CircleX
        : Lucide.CircleCheck;
    final color = stopped
        ? cs.onSurfaceVariant
        : step.isError
        ? cs.error
        : working
        ? cs.primary
        : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
            const SizedBox(width: 8),
            Text(
              position,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComputerTerminal extends StatelessWidget {
  const _ComputerTerminal({required this.output});

  final String output;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('computer-terminal-output'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff101418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff38424c)),
      ),
      alignment: Alignment.topLeft,
      child: Text(
        output,
        key: const ValueKey('computer-step-result'),
        style: const TextStyle(
          fontSize: 12,
          height: 1.4,
          fontFamily: 'monospace',
          color: Color(0xffd8e0e7),
        ),
      ),
    );
  }
}

class _ComputerPlan extends StatelessWidget {
  const _ComputerPlan({required this.plan});

  final TaskPlan plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('computer-plan-checklist'),
      padding: const EdgeInsets.only(bottom: 12),
      child: buildSharedChatSurface(
        context,
        padding: const EdgeInsets.all(12),
        borderRadius: BorderRadius.circular(12),
        defaultColor: cs.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < plan.steps.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (plan.steps[index].status) {
                        PlanStepStatus.completed => Lucide.CircleCheck,
                        PlanStepStatus.inProgress => Lucide.Loader,
                        PlanStepStatus.pending => Lucide.Circle,
                      },
                      key: ValueKey(
                        'computer-plan-status:$index:${plan.steps[index].status.name}',
                      ),
                      size: 18,
                      color: plan.steps[index].status == PlanStepStatus.pending
                          ? cs.onSurfaceVariant
                          : cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        plan.steps[index].text,
                        style: TextStyle(
                          fontSize: 13,
                          color: chatSurfacePlainTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
