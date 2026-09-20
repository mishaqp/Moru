import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../features/home/services/browser_ask_ai_bridge.dart';
import '../../../features/home/services/tool_approval_service.dart';
import '../../../features/settings/pages/browser_settings_page.dart';
import '../../../features/settings/pages/tool_schema_settings_page.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show routeObserver;
import '../../widgets/snackbar.dart';
import 'webview_activity_log_sheet.dart';
import 'webview_address_editor.dart';
import 'webview_approval_card.dart';
import 'webview_ask_ai_controller.dart';
import 'webview_bottom_panel.dart';
import 'webview_console.dart';
import 'webview_error_view.dart';
import 'webview_result_card.dart';
import 'webview_top_bar.dart';

/// Why the browser page is being closed -- used only to keep the three
/// close paths (a manual tap on the close button, `browser_use: close`
/// closing the session programmatically, and the user tapping Stop on their
/// own Ask-AI request without closing the window) from ever being confused
/// with one another. Stop never reaches this at all: it only ever calls
/// [AskAiPanelController.stop], never [_WebViewPageState._closeAgentSession].
enum WebViewCloseReason { manual, agentClose }

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    this.url,
    this.contentBase64,
    this.agentSession = false,
  });
  final String? url;
  final String? contentBase64; // HTML string in Base64
  final bool agentSession;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with RouteAware {
  late final WebViewController _controller;
  String? _title;
  String? _currentUrl;
  bool _isLoading = true;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _forceAgentClose = false;
  WebResourceError? _mainFrameError;
  final List<ConsoleMessage> _console = <ConsoleMessage>[];

  /// Bumped on every `onPageStarted`. Any async callback that started under
  /// an older navigation (a slow title fetch, a slow can-go-back/forward
  /// query) must discard its result if this has moved on by the time it
  /// resolves, rather than applying a stale answer to a page the user has
  /// since navigated away from.
  int _navGeneration = 0;

  @visibleForTesting
  WebViewCloseReason? lastCloseReason;

  /// Only present for an agent session -- a plain link/browser page never
  /// touches the Ask-AI bridge or the browser session at all.
  AskAiPanelController? _askAiController;
  bool _lastPendingApproval = false;

  /// The most recently completed Ask-AI answer for this page's own
  /// requests, kept until the user dismisses it or a newer outcome
  /// supersedes it. Never touched by browser_use activity (including a
  /// `done` activity) -- only [AskAiPanelController]'s own outcome handling
  /// (already filtered to this page's own request id) or [_dismissResult]
  /// change it.
  BrowserAskAiOutcome? _resultOutcome;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Console', onMessageReceived: _onConsoleMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _isLoading = p < 100;
              _progress = p;
            });
          },
          onPageStarted: (url) {
            _navGeneration++;
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _mainFrameError = null;
            });
            if (widget.agentSession) {
              BrowserAgentSession.instance.pageStarted(url);
            }
          },
          onPageFinished: (url) async {
            final generation = _navGeneration;
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _progress = 100;
              _currentUrl = url;
            });
            if (widget.agentSession) {
              BrowserAgentSession.instance.pageFinished(url);
            }
            await _refreshCanGoStates(generation);
            await _updateTitle(generation);
          },
          onWebResourceError: (err) {
            // Only a main-frame failure replaces the page with an error
            // screen. A subresource error (isForMainFrame == false), and
            // conservatively a `null` value too (Android's implementation
            // should always populate this; an unexpected null is treated as
            // "not main frame" rather than guessed at), stays exactly as
            // before: logged to the diagnostics console only.
            if (err.isForMainFrame == true) {
              if (mounted) setState(() => _mainFrameError = err);
            }
            _pushConsole(
              level: 'error',
              message: 'Web error ${err.errorCode}: ${err.description}',
              source: _currentUrl,
            );
          },
        ),
      );
    if (widget.agentSession) {
      BrowserAgentSession.instance.register(
        _controller,
        onClose: () => _closeAgentSession(WebViewCloseReason.agentClose),
      );
      // Just pushed, so this route is current from the start -- didPushNext/
      // didPopNext (via routeObserver, subscribed in didChangeDependencies)
      // keep this accurate as later routes cover and uncover it.
      BrowserAgentSession.instance.isRouteCurrent = true;
      final bridge = context.read<BrowserAskAiBridge>();
      _askAiController = AskAiPanelController(bridge: bridge)
        ..addListener(_onAskAiControllerChanged);
      BrowserAgentSession.instance.recentActivityNotifier.addListener(
        _onSessionActivityChanged,
      );
    }
    // Initial load
    scheduleMicrotask(_initialLoad);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.agentSession) return;
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    // Covered by another route (Settings, the trust-settings link from an
    // approval card, an image viewer) -- the browser's own Ask-AI surface
    // is no longer what the user is actually looking at.
    BrowserAgentSession.instance.isRouteCurrent = false;
  }

  @override
  void didPopNext() {
    BrowserAgentSession.instance.isRouteCurrent = true;
  }

  @override
  void dispose() {
    if (widget.agentSession) {
      routeObserver.unsubscribe(this);
      BrowserAgentSession.instance.unregister(_controller);
      BrowserAgentSession.instance.recentActivityNotifier.removeListener(
        _onSessionActivityChanged,
      );
    }
    // Whatever is closing this page (manual close, browser_use: close, or
    // the route being popped some other way), any Ask-AI request this
    // page's own composer started must not keep running invisibly once the
    // UI is gone. A no-op when there is no active request.
    _askAiController?.cancelForClose();
    _askAiController?.removeListener(_onAskAiControllerChanged);
    _askAiController?.dispose();
    super.dispose();
  }

  void _onSessionActivityChanged() {
    // A `done` (or any other) browser_use activity is just another logged
    // entry -- it must never itself advance the Ask-AI state machine beyond
    // what noteActivity() already does (starting -> running), and it must
    // never touch `_resultOutcome`. This listener exists only to give the
    // "starting" state a real sign of work to advance on.
    _askAiController?.noteActivity();
  }

  void _onAskAiControllerChanged() {
    final controller = _askAiController;
    if (controller == null) return;
    if (controller.state != AskAiPanelState.completed) return;
    final outcome = controller.lastOutcome;
    if (outcome == null || !outcome.ok) return;
    final answer = outcome.answerText?.trim() ?? '';
    if (answer.isEmpty) return;
    // Defense in depth beyond AskAiPanelController's own requestId filter:
    // an outcome reported as successful should always carry the
    // conversation it belongs to. If it somehow doesn't, treat it as not
    // trustworthy enough to show rather than guessing.
    if (outcome.conversationId == null || outcome.conversationId!.isEmpty) {
      return;
    }
    if (!mounted) return;
    setState(() => _resultOutcome = outcome);
  }

  void _dismissResult() {
    if (!mounted) return;
    setState(() => _resultOutcome = null);
  }

  Future<void> _updateTitle(int generation) async {
    try {
      final t = await _controller.runJavaScriptReturningResult(
        'document.title',
      );
      if (!mounted || generation != _navGeneration) return;
      setState(() {
        _title = _stripJsString(t);
      });
    } catch (_) {}
  }

  String? _stripJsString(Object? v) {
    if (v == null) return null;
    var s = '$v';
    if (s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s;
  }

  Future<void> _refreshCanGoStates(int generation) async {
    try {
      final back = await _controller.canGoBack();
      final fwd = await _controller.canGoForward();
      if (!mounted || generation != _navGeneration) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
      });
    } catch (_) {}
  }

  Future<void> _initialLoad() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Keep parity with existing Linux limitation: no WebView support
      final l10n = AppLocalizations.of(context)!;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.htmlPreviewNotSupportedOnLinux)),
      );
      Navigator.of(context).maybePop();
      return;
    }
    final url = widget.url?.trim() ?? '';
    if (url.isNotEmpty) {
      await _controller.loadRequest(Uri.parse(url));
    } else {
      final data = widget.contentBase64 ?? '';
      final html = data.isEmpty
          ? '<!doctype html><html><body></body></html>'
          : utf8.decode(base64Decode(data));
      await _controller.loadHtmlString(html);
    }
  }

  void _onConsoleMessage(JavaScriptMessage msg) {
    try {
      final obj = jsonDecode(msg.message) as Map<String, dynamic>;
      _pushConsole(
        level: obj['level']?.toString() ?? 'log',
        message: obj['message']?.toString() ?? '',
        source: obj['source']?.toString(),
        line: (obj['line'] as num?)?.toInt(),
      );
    } catch (_) {
      _pushConsole(level: 'log', message: msg.message);
    }
  }

  void _pushConsole({
    required String level,
    required String message,
    String? source,
    int? line,
  }) {
    if (!mounted) return;
    setState(() {
      _console.add(
        ConsoleMessage(
          level: level.toUpperCase(),
          message: message,
          source: source,
          line: line,
        ),
      );
      if (_console.length > 128) {
        _console.removeRange(0, _console.length - 128);
      }
    });
  }

  Future<void> _retryMainFrameError() async {
    setState(() => _mainFrameError = null);
    final committed = _currentUrl?.trim() ?? '';
    if (committed.isNotEmpty) {
      await _controller.reload();
      return;
    }
    final original = widget.url?.trim() ?? '';
    if (original.isNotEmpty) {
      final uri = Uri.tryParse(original);
      if (uri != null) {
        if (widget.agentSession) {
          BrowserAgentSession.instance.expectNavigation();
        }
        await _controller.loadRequest(uri);
      }
    }
  }

  /// Closes the browser page. Cancels any Ask-AI request this page's own
  /// composer started (a no-op when there is none) so nothing keeps
  /// running invisibly after the UI is gone, then pops the route. Used by
  /// both the manual close button and `BrowserAgentSession`'s `onClose`
  /// handler (`browser_use: close`) -- [reason] only distinguishes them for
  /// internal bookkeeping/tests, the behavior is otherwise identical.
  Future<void> _closeAgentSession(WebViewCloseReason reason) async {
    lastCloseReason = reason;
    _askAiController?.cancelForClose();
    if (!mounted) return;
    setState(() {
      _forceAgentClose = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _closeNonAgentPage() async {
    if (_canGoBack) {
      await _controller.goBack();
      return;
    }
    await Navigator.of(context).maybePop();
  }

  Future<void> _openAddressEditor() {
    return showBrowserAddressEditor(
      context,
      currentUrl: _currentUrl,
      onSubmit: (uri) {
        if (widget.agentSession) {
          BrowserAgentSession.instance.expectNavigation();
        }
        _controller.loadRequest(uri);
      },
    );
  }

  void _copyLink() {
    final url = _currentUrl ?? '';
    if (url.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    final l10n = AppLocalizations.of(context)!;
    AppSnackBarManager().show(
      context,
      AppNotification(
        message: l10n.chatMessageWidgetCopiedToClipboard,
        type: NotificationType.success,
      ),
    );
  }

  Future<void> _openExternally() async {
    final url = _currentUrl;
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openBrowserSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BrowserSettingsPage()),
    );
  }

  void _showConsole() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ConsoleSheet(messages: _console),
    );
  }

  /// The one `browser_use` approval that belongs to this session, if any.
  /// Never returns another conversation's pending request: `browser_use` is
  /// a single shared session, so a stale approval left behind by a
  /// different (e.g. already-cancelled) conversation must not be shown or
  /// approved from here just because it happens to be first in the queue.
  ToolApprovalRequest? _pendingBrowserApproval(ToolApprovalService? service) {
    if (service == null) return null;
    final owner = BrowserAgentSession.instance.ownerConversationId;
    if (owner == null) return null;
    for (final request in service.pendingRequests) {
      if (request.toolName == 'browser_use' &&
          request.conversationId == owner) {
        return request;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool contentMode =
        (widget.contentBase64 != null && (widget.contentBase64!.isNotEmpty)) &&
        ((widget.url == null) || widget.url!.isEmpty);
    final approvalService = widget.agentSession
        ? context.watch<ToolApprovalService>()
        : null;
    final browserApproval = _pendingBrowserApproval(approvalService);
    final pendingApproval = browserApproval != null;
    if (widget.agentSession && pendingApproval != _lastPendingApproval) {
      _lastPendingApproval = pendingApproval;
      // Deferred to right after this frame: AskAiPanelController is a
      // ChangeNotifier the bottom panel is already listening to, and
      // mutating it mid-build (before that listener has (re)subscribed for
      // this frame) risks a "setState during build" error.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _askAiController?.setPendingApproval(pendingApproval);
      });
    }
    final ru = Localizations.localeOf(context).languageCode == 'ru';

    return PopScope(
      canPop: _forceAgentClose || !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _forceAgentClose) return;
        if (_canGoBack) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: WebViewTopBar(
          currentUrl: _currentUrl,
          title: _title,
          onClose: widget.agentSession
              ? () => _closeAgentSession(WebViewCloseReason.manual)
              : _closeNonAgentPage,
          onTapAddress: contentMode ? null : _openAddressEditor,
          onCopyLink: contentMode ? null : _copyLink,
          onOpenExternally: contentMode ? null : _openExternally,
          onShowActivityLog: widget.agentSession
              ? () => showActivityLogSheet(context)
              : null,
          onOpenSettings: widget.agentSession ? _openBrowserSettings : null,
          onShowConsole: _showConsole,
        ),
        body: Column(
          children: [
            SizedBox(
              height: 3,
              child: _isLoading
                  ? LinearProgressIndicator(
                      minHeight: 3,
                      value: _progress > 0 ? _progress / 100 : null,
                    )
                  : null,
            ),
            Expanded(
              child: _mainFrameError != null
                  ? WebViewErrorView(
                      error: _mainFrameError!,
                      onRetry: _retryMainFrameError,
                    )
                  : WebViewWidget(controller: _controller),
            ),
            if (_resultOutcome != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: BrowserAskAiResultCard(
                  answerText: _resultOutcome!.answerText ?? '',
                  onExpand: () => showBrowserAskAiResultSheet(
                    context,
                    _resultOutcome!.answerText ?? '',
                    conversationId: _resultOutcome!.conversationId,
                  ),
                  onCopy: () => Clipboard.setData(
                    ClipboardData(text: _resultOutcome!.answerText ?? ''),
                  ),
                  onDismiss: _dismissResult,
                ),
              ),
            if (!contentMode && widget.agentSession && _askAiController != null)
              WebViewBottomPanel(
                controller: _askAiController!,
                canGoBack: _canGoBack,
                canGoForward: _canGoForward,
                onBack: () => _controller.goBack(),
                onForward: () => _controller.goForward(),
                onReload: () => _controller.reload(),
                onShowActivityLog: () => showActivityLogSheet(context),
                currentUrl: _currentUrl,
                approvalCard: browserApproval == null
                    ? null
                    : BrowserApprovalCard(
                        request: browserApproval,
                        siteUrl: _currentUrl,
                        ru: ru,
                        onApprove: () =>
                            context.read<ToolApprovalService>().approve(
                              browserApproval.toolCallId,
                              conversationId: browserApproval.conversationId,
                            ),
                        onDeny: () => context.read<ToolApprovalService>().deny(
                          browserApproval.toolCallId,
                          conversationId: browserApproval.conversationId,
                        ),
                        onChangeTrustSettings: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ToolSchemaSettingsPage(),
                          ),
                        ),
                      ),
              ),
            if (!contentMode && !widget.agentSession)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  child: WebViewNavRow(
                    canGoBack: _canGoBack,
                    canGoForward: _canGoForward,
                    onBack: () => _controller.goBack(),
                    onForward: () => _controller.goForward(),
                    onReload: () => _controller.reload(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
