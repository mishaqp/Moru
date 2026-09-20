import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import 'webview_ask_ai_controller.dart';

/// The merged bottom panel: one compact nav row (back/forward/reload/
/// activity-log) plus, below it, exactly one of the Ask-AI composer, a
/// status-and-Stop row for a state in flight, or [approvalCard] when a
/// `browser_use` approval is pending for this session -- never more than
/// one of these at a time, and never the same "agent is working" indicator
/// shown twice elsewhere on the page. The whole panel applies its bottom
/// safe-area exactly once.
class WebViewBottomPanel extends StatefulWidget {
  const WebViewBottomPanel({
    super.key,
    required this.controller,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onShowActivityLog,
    required this.currentUrl,
    this.approvalCard,
  });

  final AskAiPanelController controller;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onShowActivityLog;
  final String? currentUrl;

  /// Non-null exactly when a `browser_use` approval is pending for this
  /// browser session -- replaces the composer/status row entirely while
  /// the nav row above it stays put.
  final Widget? approvalCard;

  @override
  State<WebViewBottomPanel> createState() => _WebViewBottomPanelState();
}

class _WebViewBottomPanelState extends State<WebViewBottomPanel> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  /// Submits the composer's current text. Text is cleared only once the
  /// controller actually accepted the submission (a non-null id) -- a
  /// rejected attempt (blank text, or already busy) leaves it exactly as
  /// the user left it, so nothing ever appears to vanish for no reason.
  void _submit() {
    final id = widget.controller.submit(
      _textController.text,
      pageUrl: widget.currentUrl,
    );
    if (id != null) {
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WebViewNavRow(
                  canGoBack: widget.canGoBack,
                  canGoForward: widget.canGoForward,
                  onBack: widget.onBack,
                  onForward: widget.onForward,
                  onReload: widget.onReload,
                  onShowActivityLog: widget.onShowActivityLog,
                ),
                if (widget.approvalCard != null)
                  widget.approvalCard!
                else
                  _AskAiArea(
                    key: ValueKey('browser_ask_ai_area_${state.name}'),
                    state: state,
                    textController: _textController,
                    onSubmit: _submit,
                    onStop: widget.controller.stop,
                    onDismiss: widget.controller.dismiss,
                    errorMessage: state == AskAiPanelState.error
                        ? widget.controller.lastOutcome?.error
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The compact back/forward/reload(/activity-log) row, shared by the merged
/// agent-session panel and the plain (`agentSession: false`) link/browser
/// page's own simpler bottom bar -- [onShowActivityLog] is omitted for the
/// latter, since an activity log is an agent-only concept.
class WebViewNavRow extends StatelessWidget {
  const WebViewNavRow({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    this.onShowActivityLog,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback? onShowActivityLog;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _NavIconButton(
          icon: Lucide.ArrowLeft,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onTap: canGoBack ? onBack : null,
        ),
        _NavIconButton(
          icon: Lucide.ArrowRight,
          tooltip: l10n.messageWebViewForwardTooltip,
          onTap: canGoForward ? onForward : null,
        ),
        _NavIconButton(
          icon: Lucide.RefreshCw,
          tooltip: l10n.messageWebViewRefreshTooltip,
          onTap: onReload,
        ),
        if (onShowActivityLog != null)
          _NavIconButton(
            icon: Lucide.History,
            tooltip: l10n.browserComposerActivityLogTooltip,
            onTap: onShowActivityLog,
          ),
      ],
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: enabled,
        child: IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: onTap,
          icon: Icon(
            icon,
            size: 19,
            color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

/// The part of the panel below the nav row: either the composer (idle /
/// completed / stopped / error) or a compact status line with Stop
/// (starting / running / stopping).
class _AskAiArea extends StatelessWidget {
  const _AskAiArea({
    super.key,
    required this.state,
    required this.textController,
    required this.onSubmit,
    required this.onStop,
    required this.onDismiss,
    required this.errorMessage,
  });

  final AskAiPanelState state;
  final TextEditingController textController;
  final VoidCallback onSubmit;
  final VoidCallback onStop;
  final VoidCallback onDismiss;
  final String? errorMessage;

  bool get _busy =>
      state == AskAiPanelState.starting ||
      state == AskAiPanelState.running ||
      state == AskAiPanelState.stopping;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    if (_busy) {
      final (icon, label) = switch (state) {
        AskAiPanelState.starting => (
          Lucide.RefreshCw,
          l10n.browserStateStarting,
        ),
        AskAiPanelState.running => (Lucide.RefreshCw, l10n.browserStateRunning),
        AskAiPanelState.stopping => (
          Lucide.CircleStop,
          l10n.browserStateStopping,
        ),
        _ => (Lucide.RefreshCw, ''),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: state == AskAiPanelState.stopping
                  ? Icon(
                      icon,
                      size: 14,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    )
                  : CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Tooltip(
              message: l10n.browserComposerStopTooltip,
              child: Semantics(
                button: true,
                label: l10n.browserComposerStopTooltip,
                enabled: state != AskAiPanelState.stopping,
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: state == AskAiPanelState.stopping ? null : onStop,
                  icon: Icon(
                    Lucide.CircleStop,
                    size: 20,
                    color: state == AskAiPanelState.stopping
                        ? cs.onSurface.withValues(alpha: 0.3)
                        : cs.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final showBanner =
        state == AskAiPanelState.completed ||
        state == AskAiPanelState.stopped ||
        state == AskAiPanelState.error;
    final trimmed = textController.text.trim();
    final canSend = trimmed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBanner)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  state == AskAiPanelState.error
                      ? Lucide.TriangleAlert
                      : state == AskAiPanelState.stopped
                      ? Lucide.CircleX
                      : Lucide.CheckCircle,
                  size: 13,
                  color: state == AskAiPanelState.error
                      ? cs.error
                      : cs.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state == AskAiPanelState.error
                        ? (errorMessage ?? l10n.browserStateError)
                        : state == AskAiPanelState.stopped
                        ? l10n.browserStateStopped
                        : l10n.browserStateCompleted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: state == AskAiPanelState.error
                          ? cs.error
                          : cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                if (state != AskAiPanelState.completed)
                  Semantics(
                    button: true,
                    label: l10n.commonClose,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Lucide.X, size: 14),
                      onPressed: onDismiss,
                    ),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: textController,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: l10n.browserComposerHint,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: l10n.browserComposerSendTooltip,
              child: Semantics(
                button: true,
                label: l10n.browserComposerSendTooltip,
                enabled: canSend,
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: canSend ? onSubmit : null,
                  icon: Icon(Lucide.ArrowUp, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: canSend
                        ? cs.primary
                        : cs.primary.withValues(alpha: 0.35),
                    foregroundColor: cs.onPrimary,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
