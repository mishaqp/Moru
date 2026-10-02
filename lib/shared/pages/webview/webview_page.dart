import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/acp/acp_secret_redactor.dart';
import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_handoffs.dart';
import '../../../core/services/browser/browser_library.dart';
import '../../../core/services/browser/browser_site_permissions.dart';
import '../../../core/services/browser/browser_tabs.dart';
import '../../../features/home/services/browser_ask_ai_bridge.dart';
import '../../../features/home/services/tool_approval_service.dart';
import '../../../features/settings/pages/browser_settings_page.dart';
import '../../../features/settings/pages/tool_schema_settings_page.dart';
import '../../../icons/lucide_adapter.dart';
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
import 'webview_site_handlers.dart';
import 'webview_library_sheet.dart';
import 'webview_status_banner.dart';
import 'webview_tabs_sheet.dart';
import 'webview_userscripts_sheet.dart';
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
    this.preparedController,
  });
  final String? url;
  final String? contentBase64; // HTML string in Base64
  final bool agentSession;

  /// A fresh controller whose app-owned authentication bootstrap has finished.
  final WebViewController? preparedController;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

/// Console messages of the shared agent WebView go to whichever page shows it
/// now; its JavaScript channel is registered once and outlives the page.
void Function(JavaScriptMessage message)? _agentConsoleSink;

/// Sites whose invalid certificate the user chose to accept, until the app
/// restarts (like Chrome's "Proceed").
final Set<String> _sslAcceptedHosts = <String>{};

/// A WebView for the shared agent browser: its first page and every tab.
/// Nothing here belongs to a page, so tabs opened while the browser is
/// minimized work the same.
WebViewController createAgentBrowserController() {
  final session = BrowserAgentSession.instance;
  final controller =
      createSiteAwareController(
          visible: () => session.isRouteCurrent && !session.minimized.value,
        )
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'Console',
          onMessageReceived: (message) => _agentConsoleSink?.call(message),
        );
  return controller;
}

/// Enables the normal browser only after an isolated authentication bootstrap.
Future<void> prepareAgentBrowserController(WebViewController controller) async {
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.addJavaScriptChannel(
    'Console',
    onMessageReceived: (message) => _agentConsoleSink?.call(message),
  );
}

class _WebViewPageState extends State<WebViewPage> with RouteAware {
  /// The WebView on screen; for the agent browser, the active tab's.
  late WebViewController _controller;

  /// True when this page took over a browser from the mini window, so the
  /// page is already loaded and must not load again.
  bool _adopted = false;

  /// Set right before popping to minimize: dispose hands the controller to
  /// the mini window instead of closing the session.
  bool _minimizing = false;
  String? _title;
  String? _currentUrl;

  /// The last page that finished loading: what the view still shows when a
  /// navigation is refused (an invalid certificate).
  String? _shownUrl;

  /// The address whose certificate was refused, until the next navigation:
  /// its late progress and finish events are not a page load.
  String? _sslRefusedUrl;
  bool _isLoading = true;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _forceAgentClose = false;
  WebResourceError? _mainFrameError;
  static final _consoleRedactor = AcpSecretRedactor(
    [],
    protectAuthentication: true,
  );
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
    final adopted = widget.agentSession
        ? BrowserAgentSession.instance.takeMinimized()
        : null;
    _adopted = adopted != null;
    if (widget.agentSession) _agentConsoleSink = _onConsoleMessage;
    if (widget.agentSession) {
      BrowserAgentSession.instance.controllerFactory =
          createAgentBrowserController;
    }
    _controller =
        adopted ??
        widget.preparedController ??
        (widget.agentSession
            ? createAgentBrowserController()
            : (createSiteAwareController(visible: () => mounted)
                ..setJavaScriptMode(JavaScriptMode.unrestricted)
                ..addJavaScriptChannel(
                  'Console',
                  onMessageReceived: _onConsoleMessage,
                )));
    if (widget.agentSession && adopted == null) {
      BrowserAgentSession.instance.installDialogHandlers(_controller);
    }
    BrowserSitePermissions.instance.presenter = _askSitePermission;
    BrowserHandoffs.instance.latestDownload.addListener(_onDownload);
    if (widget.agentSession) {
      BrowserLibrary.instance.bookmarks.addListener(_onLibraryChanged);
      unawaited(
        BrowserLibrary.instance.load().catchError(
          (Object error) => debugPrint('Browser library: $error'),
        ),
      );
    }
    unawaited(
      BrowserHandoffs.instance.setNavigationDelegate(
        _controller,
        _pageDelegate(),
      ),
    );
    if (widget.agentSession) {
      BrowserAgentSession.instance.register(
        _controller,
        onClose: () => _closeAgentSession(WebViewCloseReason.agentClose),
      );
      BrowserAgentSession.instance.tabs.addListener(_onTabsChanged);
      // Just pushed, so this route is current from the start -- didPushNext/
      // didPopNext (via routeObserver, subscribed in didChangeDependencies)
      // keep this accurate as later routes cover and uncover it.
      BrowserAgentSession.instance
        ..isRouteCurrent = true
        ..dialogPresenter = _showPageDialog;
      final bridge = context.read<BrowserAskAiBridge>();
      _askAiController = AskAiPanelController(bridge: bridge)
        ..addListener(_onAskAiControllerChanged);
      BrowserAgentSession.instance.recentActivityNotifier.addListener(
        _onSessionActivityChanged,
      );
    }
    if (_adopted) {
      _isLoading = false;
      scheduleMicrotask(_restoreAdoptedState);
    } else {
      scheduleMicrotask(_initialLoad);
    }
  }

  /// Another tab went on screen (from the tab list or the model): show its
  /// WebView and drive it from here.
  void _onTabsChanged() {
    final active = BrowserAgentSession.instance.controller;
    if (!mounted || _minimizing || active == null) return;
    if (identical(active, _controller)) {
      // The count or the active tab's mode changed.
      final url = _activeTabInfo?.url;
      setState(() {
        if (url != null) _currentUrl = url;
      });
      return;
    }
    _navGeneration++;
    setState(() {
      _controller = active;
      _currentUrl = null;
      _shownUrl = null;
      _sslRefusedUrl = null;
      _title = null;
      _mainFrameError = null;
      _isLoading = false;
      _progress = 100;
      _canGoBack = false;
      _canGoForward = false;
    });
    unawaited(
      BrowserHandoffs.instance.setNavigationDelegate(active, _pageDelegate()),
    );
    unawaited(_restoreAdoptedState());
  }

  Future<void> _toggleBookmark() async {
    final url = _currentUrl;
    if (url == null) return;
    final added = await BrowserLibrary.instance.toggleBookmark(url, _title);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: added ? l10n.browserBookmarkAdded : l10n.browserBookmarkRemoved,
      type: NotificationType.success,
    );
  }

  void _openFromLibrary(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) unawaited(_controller.loadRequest(uri));
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  BrowserTabInfo? get _activeTabInfo {
    for (final tab in BrowserAgentSession.instance.tabs.value) {
      if (tab.active) return tab;
    }
    return null;
  }

  Future<void> _clearSiteData() async {
    final l10n = AppLocalizations.of(context)!;
    final site = Uri.tryParse(_currentUrl ?? '')?.host ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.browserClearSiteData),
        content: Text(l10n.browserClearSiteDataConfirm(site)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.browserClearSiteData),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await BrowserAgentSession.instance.clearSiteData();
    if (!mounted || result['ok'] != true) return;
    showAppSnackBar(
      context,
      message: l10n.browserClearSiteDataDone(site),
      type: NotificationType.success,
    );
  }

  /// The page's own navigation handling: progress, address, title, errors,
  /// and the agent session's bookkeeping.
  NavigationDelegate _pageDelegate() => NavigationDelegate(
    onProgress: (p) {
      if (!mounted || _sslRefusedUrl != null) return;
      setState(() {
        _isLoading = p < 100;
        _progress = p;
      });
    },
    onPageStarted: (url) {
      if (url == _sslRefusedUrl) return;
      _sslRefusedUrl = null;
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
      if (url == _sslRefusedUrl) return;
      final generation = _navGeneration;
      _shownUrl = url;
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
    onSslAuthError: (error) => unawaited(_onSslError(error)),
    onHttpError: (error) {
      if (widget.agentSession) {
        BrowserAgentSession.instance.noteHttpError(
          error.request?.uri,
          error.response?.statusCode,
        );
      }
    },
    onWebResourceError: (err) {
      // Only a main-frame failure replaces the page with an error
      // screen. A subresource error (isForMainFrame == false), and
      // conservatively a `null` value too (Android's implementation
      // should always populate this; an unexpected null is treated as
      // "not main frame" rather than guessed at), stays exactly as
      // before: logged to the diagnostics console only.
      if (err.isForMainFrame == true && BrowserHandoffs.isAppLink(err.url)) {
        unawaited(_openAppLink(err.url!));
        return;
      }
      if (err.isForMainFrame == true) {
        if (mounted) setState(() => _mainFrameError = err);
      }
      _pushConsole(
        level: 'error',
        message: 'Web error ${err.errorCode}: ${err.description}',
        source: _currentUrl,
      );
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.agentSession) return;
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  /// A page link for another app (`intent:`, `tel:`, `mailto:` ...): the
  /// WebView cannot load it, so it goes to its app, or the link's web
  /// fallback loads. Not while the model drives the page: an app popping up
  /// on its own would surprise the user, so the model is told instead.
  Future<void> _openAppLink(String url) async {
    final session = BrowserAgentSession.instance;
    final agentWorking =
        widget.agentSession &&
        session.currentActivity.value?.outcome ==
            BrowserActivityOutcome.running;
    final visible = widget.agentSession
        ? session.isRouteCurrent && !session.minimized.value
        : mounted;
    if (agentWorking || !visible) {
      BrowserHandoffs.instance.noteBlockedAppLink(url);
      if (await _controller.canGoBack()) await _controller.goBack();
      return;
    }
    final result = await BrowserHandoffs.instance.openAppLink(url);
    if (!result.opened && result.fallback != null) {
      await _controller.loadRequest(Uri.parse(result.fallback!));
      return;
    }
    if (await _controller.canGoBack()) await _controller.goBack();
    if (!result.opened && mounted) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.browserNoAppForLink,
        type: NotificationType.warning,
      );
    }
  }

  void _onDownload() {
    final download = BrowserHandoffs.instance.latestDownload.value;
    if (download == null || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: download.error == null && download.status == 'done'
          ? l10n.browserDownloadDone(download.file)
          : download.error == null && download.status == 'failed'
          ? l10n.browserDownloadFailed(download.file)
          : download.error == null
          ? l10n.browserDownloadStarted(download.file)
          : download.error == 'unsupported_scheme'
          ? l10n.browserDownloadUnsupported
          : l10n.browserDownloadFailed(download.file),
      type: download.status == 'done'
          ? NotificationType.success
          : download.error == null && download.status != 'failed'
          ? NotificationType.info
          : NotificationType.warning,
    );
  }

  /// A page whose certificate is not valid: the user decides while looking
  /// at the browser; otherwise (the model drives it, or nobody looks) it is
  /// not opened and the model is told.
  Future<void> _onSslError(SslAuthError error) async {
    final platform = error.platform;
    final url = platform is AndroidSslAuthError ? platform.url : _currentUrl;
    final host = Uri.tryParse(url ?? '')?.host ?? '';
    if (host.isNotEmpty && _sslAcceptedHosts.contains(host)) {
      await error.proceed();
      return;
    }
    final session = BrowserAgentSession.instance;
    final agentWorking =
        widget.agentSession &&
        session.currentActivity.value?.outcome ==
            BrowserActivityOutcome.running;
    final visible = widget.agentSession
        ? session.isRouteCurrent && !session.minimized.value
        : true;
    if (!mounted || agentWorking || !visible) {
      await _refuseSsl(error, url);
      if (widget.agentSession) {
        BrowserHandoffs.instance.noteSslError(host, platform.description);
      }
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Lucide.ShieldAlert),
        title: Text(l10n.browserSslTitle),
        content: Text(l10n.browserSslMessage(host, platform.description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.browserSslProceed),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.browserSslBack),
          ),
        ],
      ),
    );
    if (proceed == true) {
      if (host.isNotEmpty) _sslAcceptedHosts.add(host);
      await error.proceed();
    } else {
      await _refuseSsl(error, url);
    }
  }

  /// Refuses the page: the view keeps the page it showed, so the address
  /// bar, progress and the session go back to it.
  Future<void> _refuseSsl(SslAuthError error, String? url) async {
    _sslRefusedUrl = url;
    await error.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _progress = 100;
        _currentUrl = _shownUrl;
      });
    }
    if (widget.agentSession) {
      BrowserAgentSession.instance.navigationBlocked(_shownUrl);
    }
  }

  /// Chrome-style question: may this site use the camera, microphone,
  /// location or protected video?
  Future<bool> _askSitePermission(String host, Set<String> kinds) async {
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    final names = [
      for (final kind in kinds)
        switch (kind) {
          'camera' => l10n.browserPermissionCamera,
          'microphone' => l10n.browserPermissionMicrophone,
          'location' => l10n.browserPermissionLocation,
          _ => l10n.browserPermissionProtectedMedia,
        },
    ];
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(host),
        content: Text(l10n.browserPermissionQuestion(names.join(', '))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.browserPermissionBlock),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.browserPermissionAllow),
          ),
        ],
      ),
    );
    return allowed ?? false;
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
    BrowserSitePermissions.instance.presenter = _askSitePermission;
  }

  @override
  void dispose() {
    BrowserHandoffs.instance.latestDownload.removeListener(_onDownload);
    BrowserLibrary.instance.bookmarks.removeListener(_onLibraryChanged);
    if (identical(
      BrowserSitePermissions.instance.presenter,
      _askSitePermission,
    )) {
      BrowserSitePermissions.instance.presenter = null;
    }
    if (widget.agentSession) {
      BrowserAgentSession.instance.tabs.removeListener(_onTabsChanged);
      routeObserver.unsubscribe(this);
      if (identical(_agentConsoleSink, _onConsoleMessage)) {
        _agentConsoleSink = null;
      }
      if (identical(
        BrowserAgentSession.instance.dialogPresenter,
        _showPageDialog,
      )) {
        BrowserAgentSession.instance.dialogPresenter = null;
      }
      if (_minimizing) {
        BrowserAgentSession.instance.minimize(_controller);
      } else {
        BrowserAgentSession.instance.unregister(_controller);
      }
      BrowserAgentSession.instance.recentActivityNotifier.removeListener(
        _onSessionActivityChanged,
      );
    }
    // Whatever is closing this page (manual close, browser_use: close, or
    // the route being popped some other way), any Ask-AI request this
    // page's own composer started must not keep running invisibly once the
    // UI is gone. A no-op when there is no active request.
    // Minimizing keeps the page (and a running Ask-AI request) alive in the
    // mini window, so only a real close cancels.
    if (!_minimizing) _askAiController?.cancelForClose();
    _askAiController?.removeListener(_onAskAiControllerChanged);
    _askAiController?.dispose();
    super.dispose();
  }

  /// A page's alert/confirm/prompt while the user looks at the browser.
  Future<String?> _showPageDialog(
    String kind,
    String message,
    String? defaultText,
  ) async {
    if (!mounted) return kind == 'confirm' ? 'declined' : null;
    final l10n = AppLocalizations.of(context)!;
    final input = kind == 'prompt'
        ? TextEditingController(text: defaultText ?? '')
        : null;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Uri.tryParse(_currentUrl ?? '')?.host ?? ''),
        content: input == null
            ? SingleChildScrollView(child: Text(message))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 8),
                  TextField(controller: input, autofocus: true),
                ],
              ),
        actions: [
          if (kind != 'alert')
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(kind == 'confirm' ? 'declined' : null),
              child: Text(l10n.homePageCancel),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(switch (kind) {
              'alert' => 'ok',
              'confirm' => 'accepted',
              _ => input!.text,
            }),
            child: Text(l10n.sideDrawerOK),
          ),
        ],
      ),
    );
    input?.dispose();
    return result ?? (kind == 'confirm' ? 'declined' : null);
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

  Future<void> _restoreAdoptedState() async {
    final generation = _navGeneration;
    final url = await _controller.currentUrl();
    if (!mounted || generation != _navGeneration || url == null) return;
    _shownUrl = url;
    setState(() => _currentUrl = url);
    await _refreshCanGoStates(generation);
    await _updateTitle(generation);
  }

  /// Closes the page but keeps the browser running in the mini window.
  Future<void> _minimize() async {
    if (!mounted) return;
    setState(() => _minimizing = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _initialLoad() async {
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
    // Redirects and page scripts can introduce authentication links after
    // navigation starts. Filter every field before the console retains it.
    final entry = ConsoleMessage(
      level: _consoleRedactor.text(level).toUpperCase(),
      message: _consoleRedactor.text(message),
      source: source == null ? null : _consoleRedactor.text(source),
      line: line,
    );
    setState(() {
      _console.add(entry);
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
  /// both the overflow close action and `BrowserAgentSession`'s `onClose`
  /// handler (`browser_use: close`) -- [reason] only distinguishes them for
  /// internal bookkeeping/tests, the behavior is otherwise identical.
  Future<void> _closeAgentSession(WebViewCloseReason reason) async {
    if (reason == WebViewCloseReason.manual) {
      final approvals = context.read<ToolApprovalService>();
      final pendingApproval = _pendingBrowserApproval(approvals);
      final busy =
          (_askAiController?.isBusy ?? false) ||
          pendingApproval != null ||
          BrowserAgentSession.instance.currentActivity.value?.outcome ==
              BrowserActivityOutcome.running;
      if (busy) {
        final l10n = AppLocalizations.of(context)!;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.browserCloseWhileAiTitle),
            content: Text(l10n.browserCloseWhileAiMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.homePageCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.browserCloseBrowser),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        if (pendingApproval != null &&
            approvals.pendingRequests.any(
              (request) => request.approvalId == pendingApproval.approvalId,
            )) {
          approvals.deny(
            pendingApproval.toolCallId,
            conversationId: pendingApproval.conversationId,
          );
        }
        BrowserAgentSession.instance.requestStop();
      }
    }
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
      canPop: _forceAgentClose || _minimizing || !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _forceAgentClose || _minimizing) return;
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
          onMinimize: widget.agentSession ? _minimize : null,
          onTapAddress: contentMode ? null : _openAddressEditor,
          onCopyLink: contentMode ? null : _copyLink,
          onOpenExternally: contentMode ? null : _openExternally,
          onShowActivityLog: widget.agentSession
              ? () => showActivityLogSheet(context)
              : null,
          onOpenSettings: widget.agentSession ? _openBrowserSettings : null,
          onShowConsole: _showConsole,
          progress: _isLoading ? _progress / 100 : null,
          tabCount: widget.agentSession
              ? BrowserAgentSession.instance.tabs.value.length
              : null,
          onShowTabs: widget.agentSession
              ? () => showBrowserTabsSheet(context)
              : null,
          desktopMode: _activeTabInfo?.desktop,
          onDesktopModeChanged: widget.agentSession && !contentMode
              ? (desktop) => unawaited(
                  BrowserAgentSession.instance.setDesktopMode(desktop),
                )
              : null,
          onClearSiteData: widget.agentSession && !contentMode
              ? _clearSiteData
              : null,
          bookmarked: BrowserLibrary.instance.isBookmarked(_currentUrl),
          onToggleBookmark: widget.agentSession && !contentMode
              ? _toggleBookmark
              : null,
          onShowBookmarks: widget.agentSession && !contentMode
              ? () => showBrowserLibrarySheet(
                  context,
                  history: false,
                  onOpen: _openFromLibrary,
                )
              : null,
          onShowUserscripts: widget.agentSession && !contentMode
              ? () => showUserscriptsSheet(context, pageUrl: _currentUrl)
              : null,
          onShowHistory: widget.agentSession && !contentMode
              ? () => showBrowserLibrarySheet(
                  context,
                  history: true,
                  onOpen: _openFromLibrary,
                )
              : null,
        ),
        body: Column(
          children: [
            if (widget.agentSession && !contentMode)
              _askAiController == null
                  ? WebViewStatusBanner(
                      showActivity: true,
                      onOpenInChrome: _openExternally,
                    )
                  : ListenableBuilder(
                      listenable: _askAiController!,
                      builder: (context, _) => WebViewStatusBanner(
                        onOpenInChrome: _openExternally,
                        showActivity: switch (_askAiController!.state) {
                          AskAiPanelState.starting ||
                          AskAiPanelState.running ||
                          AskAiPanelState.awaitingApproval ||
                          AskAiPanelState.stopping => false,
                          _ => true,
                        },
                      ),
                    ),
            Expanded(
              child: _mainFrameError != null
                  ? WebViewErrorView(
                      error: _mainFrameError!,
                      onRetry: _retryMainFrameError,
                    )
                  : WebViewWidget(
                      // A tab switch shows another native WebView.
                      key: ObjectKey(_controller),
                      controller: _controller,
                    ),
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
              ValueListenableBuilder<List<BrowserActivity>>(
                valueListenable:
                    BrowserAgentSession.instance.recentActivityNotifier,
                builder: (context, _, __) => WebViewBottomPanel(
                  controller: _askAiController!,
                  showCompletedStatus: _resultOutcome == null,
                  actionCount: BrowserAgentSession.instance
                      .activityCountForPage(_currentUrl),
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
                          onDeny: () =>
                              context.read<ToolApprovalService>().deny(
                                browserApproval.toolCallId,
                                conversationId: browserApproval.conversationId,
                              ),
                          onChangeTrustSettings: () =>
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const ToolSchemaSettingsPage(),
                                ),
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
