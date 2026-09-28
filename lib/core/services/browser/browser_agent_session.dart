import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../utils/app_directories.dart';
import '../../../utils/utf16_safe_cut.dart';
import 'browser_guard.dart';
import 'browser_handoffs.dart';
import 'browser_tabs.dart';
import 'browser_research.dart';

/// Lifecycle state of a [BrowserActivity]: [running] the moment it is
/// recorded (before the call's own result is known), then one of the
/// terminal states once [BrowserAgentTool.execute] sees the call's own JSON
/// result. [notFound] is a *display-only* distinction for `wait_for`: the
/// tool's own JSON contract with the model always reports `ok: true` with
/// `found: false` (that is not a failure the model needs to retry
/// differently), but the human-facing log still needs to say the element
/// was never found rather than showing the same look as a real success.
enum BrowserActivityOutcome { running, ok, failed, notFound }

/// One `browser_use` call, for the browser page's status line and its
/// activity log: [action] matches a `BrowserAgentAction.id` for its label,
/// [detail] is an optional short extra (a URL, a key, a truncated selector)
/// the label alone doesn't carry. [id] is unique per call (even repeats of
/// the same action), so a result can always be resolved against the exact
/// call it belongs to rather than "whatever is currently last".
class BrowserActivity {
  const BrowserActivity({
    required this.id,
    required this.action,
    this.detail,
    this.outcome = BrowserActivityOutcome.running,
    required this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String action;
  final String? detail;
  final BrowserActivityOutcome outcome;
  final DateTime startedAt;
  final DateTime? finishedAt;

  Duration? get duration => finishedAt?.difference(startedAt);

  BrowserActivity withOutcome(
    BrowserActivityOutcome outcome, {
    DateTime? finishedAt,
  }) => BrowserActivity(
    id: id,
    action: action,
    detail: detail,
    outcome: outcome,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
  );
}

/// The user pressed Stop while a `browser_use` action ran.
class BrowserStoppedException implements Exception {
  const BrowserStoppedException();

  @override
  String toString() => 'The user stopped this browser action.';
}

/// Shows a page's JavaScript dialog to the user. Returns `ok`, `accepted`,
/// `declined`, the prompt's text, or null when a prompt was cancelled.
typedef BrowserDialogPresenter =
    Future<String?> Function(String kind, String message, String? defaultText);

class BrowserAgentProtocolException implements Exception {
  const BrowserAgentProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Deterministic history for model-driven navigation.
///
/// Native WebView history can include redirects and entries created outside the
/// agent flow. The agent keeps its own committed-page stack so back/forward
/// always mean the pages the model actually reached.
///
/// ## Navigation contract
///
/// Native UI back/forward (the browser page's own buttons, and Android's
/// system back gesture) always call the real `WebViewController`'s
/// `goBack()`/`goForward()` directly and are authoritative for what the user
/// sees — this history is never used to drive those controls.
///
/// This history exists only so the model's own `browser_use` `back`/`forward`
/// actions ([BrowserAgentSession.goBack]/[goForward], which replay a URL via
/// `loadRequest` rather than native history, since that is required to keep
/// forms/POST state/SPA state intact) stay accurate even when the user
/// navigates manually in between. To make that possible, [reconcileCommitted]
/// must be called once for every committed navigation on the shared
/// controller — agent-initiated or not — typically from the WebView's
/// `onPageFinished` callback. It classifies the newly-committed URL against
/// this history's own back/forward targets:
///  - matches [backTarget]: a native back happened -> [commitBack] (no push)
///  - matches [forwardTarget]: a native forward happened -> [commitForward]
///  - anything else (a manual address-bar submit, an in-page link tap, a
///    fresh agent-initiated load, or a mid-load redirect that lands
///    somewhere new): a genuinely new page -> [push], which truncates any
///    stale forward entries the same way agent-initiated navigation does.
/// Because every committed navigation goes through the same reconciliation,
/// [BrowserAgentSession.goBack]/[goForward]/[load] and the click/type/submit/
/// press_key actions no longer need to push or commit history themselves —
/// doing so as well would double-count the very navigation this method just
/// reconciled.
class BrowserNavigationHistory {
  final List<String> _entries = <String>[];
  int _index = -1;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index < _entries.length - 1;
  String? get current =>
      _index >= 0 && _index < _entries.length ? _entries[_index] : null;
  String? get backTarget => canGoBack ? _entries[_index - 1] : null;
  String? get forwardTarget => canGoForward ? _entries[_index + 1] : null;

  void reset(String url) {
    _entries
      ..clear()
      ..add(url);
    _index = 0;
  }

  void push(String url) {
    if (url.isEmpty || current == url) return;
    if (canGoForward) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(url);
    _index = _entries.length - 1;
  }

  void commitBack() {
    if (canGoBack) _index--;
  }

  void commitForward() {
    if (canGoForward) _index++;
  }

  void clear() {
    _entries.clear();
    _index = -1;
  }

  /// Reconciles one committed navigation against this history. See the
  /// class doc comment above for the full contract; this is the single
  /// entry point every committed navigation on the shared controller must
  /// go through, so agent-initiated and manual navigation never drift apart.
  void reconcileCommitted(String url) {
    if (url.isEmpty) return;
    if (current == null) {
      reset(url);
      return;
    }
    if (url == current) return;
    if (url == backTarget) {
      commitBack();
    } else if (url == forwardTarget) {
      commitForward();
    } else {
      push(url);
    }
  }
}

/// Hard cap on the string `eval_js` puts in its result envelope, so evaluating something
/// like `document.body.outerHTML` can't dump megabytes into a turn.
const int evalJsMaxResultChars = 64 * 1024;

/// One shared browser session used by the visible WebView and the model.
///
/// Every action here but `eval_js` is a bounded, single-purpose script the model
/// cannot alter; `eval_js` is the one deliberate exception, gated the same way as
/// click/type/submit/press_key (requires approval unless global trusted mode is on)
/// plus a static block on the code itself for cookie/session-theft-shaped patterns.
class BrowserAgentSession {
  BrowserAgentSession._();

  static final BrowserAgentSession instance = BrowserAgentSession._();

  // ---------------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------------

  /// At most this many pages are open at once.
  static const int maxTabs = 5;

  /// A tab the model opened and has not used for this long is closed, unless
  /// it is the one on screen.
  static const Duration agentTabIdle = Duration(minutes: 15);

  final List<BrowserTab> _tabs = <BrowserTab>[];
  BrowserTab? _active;
  int _nextTabId = 0;
  Timer? _idleTimer;

  /// The open tabs, for the tab list, the mini window and the page, which
  /// shows the active one.
  final ValueNotifier<List<BrowserTabInfo>> tabs =
      ValueNotifier<List<BrowserTabInfo>>(const <BrowserTabInfo>[]);

  /// Makes the WebView of a new tab, set up like the browser page's own;
  /// set by the page, which knows how.
  WebViewController Function()? controllerFactory;

  /// Replaced in tests.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  WebViewController? get _controller => _active?.controller;

  static final BrowserNavigationHistory _noHistory = BrowserNavigationHistory();
  BrowserNavigationHistory get _history => _active?.history ?? _noHistory;

  Completer<void>? _attachedCompleter;
  Completer<void>? _readyCompleter;
  bool _loading = false;
  int _navigationSequence = 0;
  Future<void> Function()? _closeHandler;

  /// The conversation currently driving `browser_use` calls against this
  /// session, refreshed on every dispatch by [BrowserAgentTool.execute].
  /// Lets the browser page's approval prompt pick the one pending
  /// `browser_use` request that actually belongs to this session instead of
  /// any conversation's, and is cleared with everything else on [unregister].
  String? ownerConversationId;

  void setOwnerConversationId(String? conversationId) {
    ownerConversationId = conversationId;
  }

  /// True exactly when this session's own [WebViewPage] route is the
  /// current, foreground-visible route -- not covered by another push
  /// (Settings, the trust-settings link from an approval card, an image
  /// viewer) and not yet closed. Kept current by that page's own
  /// `RouteAware` hookup; never guessed from "is the browser attached"
  /// alone, since the session stays attached while covered by another
  /// screen.
  bool isRouteCurrent = false;

  /// taskId -> conversationId for every browser Ask-AI request this
  /// session has started but whose `MobileBackgroundCoordinator.finish()`
  /// notification decision hasn't run yet. [taskId] matches
  /// `MobileBackgroundCoordinator`'s own per-run id (`generationRunId`, or
  /// the assistant message id when no run id exists) exactly, so a lookup
  /// here can never partially match a different run for the same
  /// conversation.
  ///
  /// Written the moment `runBrowserAskAiRequest`'s `send()` call returns
  /// successfully -- well before that run's own terminal event, let alone
  /// `finish()` -- specifically so the notification decision never races
  /// `AskAiPanelController`'s own `activeRequestId` (which resets to null
  /// the instant an outcome arrives, often before `finish()` even runs).
  final Map<String, String> _askAiTasks = <String, String>{};

  /// Records that [taskId] (for [conversationId]) belongs to a browser
  /// Ask-AI request this session just started.
  void trackAskAiTask(String taskId, String conversationId) {
    _askAiTasks[taskId] = conversationId;
  }

  /// Consumes (removes) the tracked entry for [taskId], returning whether
  /// it belonged to this session, matches [conversationId], and this
  /// session's own browser page is right now the visible, current route.
  /// Called at most once per [taskId] -- `MobileBackgroundCoordinator`
  /// calls `finish()` exactly once per run -- so a stale entry can never
  /// linger past the one decision it exists for.
  bool consumeVisibleAskAiTask(String taskId, String conversationId) {
    final owner = _askAiTasks.remove(taskId);
    if (owner == null) return false;
    return isRouteCurrent && owner == conversationId;
  }

  /// The most recent `browser_use` call, for the browser page's status line.
  /// Null once the session closes; otherwise sticky until the next call.
  final ValueNotifier<BrowserActivity?> currentActivity =
      ValueNotifier<BrowserActivity?>(null);

  static const int _maxRecentActivity = 30;
  int _nextActivityId = 0;

  /// Bounded log behind "Show recent", oldest first, reactive: a "Recent"
  /// sheet built with `ValueListenableBuilder` on this updates live while
  /// open, both while a call is still [BrowserActivityOutcome.running] and
  /// after it resolves — it does not need to be reopened to see the result.
  final ValueNotifier<List<BrowserActivity>> recentActivityNotifier =
      ValueNotifier<List<BrowserActivity>>(const <BrowserActivity>[]);

  /// Read-only snapshot of the current log. Prefer [recentActivityNotifier]
  /// for anything that should stay live while visible.
  List<BrowserActivity> get recentActivity => recentActivityNotifier.value;

  /// Starts a new activity and returns its id, to later resolve via
  /// [resolveActivity]. ids are unique for the process lifetime (never
  /// reused across sessions), so a late resolution can never land on a
  /// newer, unrelated call that happens to be "last" by the time it arrives.
  String recordActivity({required String action, String? detail}) {
    final id = 'browser-activity-${_nextActivityId++}';
    final activity = BrowserActivity(
      id: id,
      action: action,
      detail: detail,
      startedAt: DateTime.now(),
    );
    currentActivity.value = activity;
    final next = <BrowserActivity>[...recentActivityNotifier.value, activity];
    recentActivityNotifier.value = next.length > _maxRecentActivity
        ? next.sublist(next.length - _maxRecentActivity)
        : next;
    return id;
  }

  /// Resolves the activity started by [id] (from [recordActivity]) to
  /// [outcome]. A no-op if [id] is not in the current log: either this
  /// session closed and reopened since (`unregister` clears the log
  /// entirely, so no id from a previous session can ever match again), the
  /// entry aged out of the bounded log, or it was already resolved — a late
  /// or duplicate result must never overwrite a newer outcome.
  void resolveActivity(String id, BrowserActivityOutcome outcome) {
    final list = recentActivityNotifier.value;
    final index = list.indexWhere((activity) => activity.id == id);
    if (index == -1) return;
    final existing = list[index];
    if (existing.outcome != BrowserActivityOutcome.running) return;
    final resolved = existing.withOutcome(outcome, finishedAt: DateTime.now());
    final next = List<BrowserActivity>.of(list);
    next[index] = resolved;
    recentActivityNotifier.value = next;
    if (currentActivity.value?.id == id) {
      currentActivity.value = resolved;
    }
  }

  bool get isAttached => _controller != null;

  // ---------------------------------------------------------------------------
  // Screenshots
  // ---------------------------------------------------------------------------

  static const MethodChannel _browserChannel = MethodChannel('app.browser');

  /// Screenshots kept on disk; older ones are deleted.
  static const int keptScreenshots = 40;

  /// A JPEG of what the WebView shows now. Replaced in tests.
  @visibleForTesting
  Future<Uint8List> Function(WebViewController controller) captureBytes =
      _nativeCapture;

  /// Where screenshots are saved. Replaced in tests.
  @visibleForTesting
  Future<Directory> Function() screenshotDirectory = () async => Directory(
    p.join((await AppDirectories.getImagesDirectory()).path, 'browser'),
  );

  static Future<Uint8List> _nativeCapture(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) {
      throw PlatformException(
        code: 'unsupported',
        message: 'Screenshots need the Android browser.',
      );
    }
    final bytes = await _browserChannel.invokeMethod<Uint8List>('capture', {
      'id': platform.webViewIdentifier,
    });
    if (bytes == null || bytes.isEmpty) {
      throw PlatformException(code: 'empty', message: 'The picture is empty.');
    }
    return bytes;
  }

  /// Saves a picture of the page as it shows now and returns its path with
  /// the viewport size in CSS pixels, so points in it map to click x/y.
  Future<Map<String, dynamic>> screenshot() async {
    await waitUntilReady();
    final controller = _requireController();
    final Uint8List bytes;
    try {
      bytes = await _interruptible(captureBytes(controller));
    } on PlatformException catch (error) {
      return {
        'ok': false,
        'error': 'screenshot_failed',
        'message': error.message ?? error.code,
      };
    }
    final dir = await screenshotDirectory();
    await dir.create(recursive: true);
    final file = File(
      p.join(dir.path, 'shot-${DateTime.now().microsecondsSinceEpoch}.jpg'),
    );
    await file.writeAsBytes(bytes, flush: true);
    await _pruneScreenshots(dir);
    Map<String, dynamic> viewport = const {};
    try {
      viewport = await _runJson(
        'JSON.stringify({width: window.innerWidth, height: window.innerHeight})',
      );
    } catch (_) {}
    return {
      'ok': true,
      'screenshot': file.path,
      'url': await controller.currentUrl(),
      if (viewport.isNotEmpty) 'viewport': viewport,
    };
  }

  static Future<void> _pruneScreenshots(Directory dir) async {
    final shots = <File>[
      await for (final entity in dir.list())
        if (entity is File && p.basename(entity.path).startsWith('shot-'))
          entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
    for (final old in shots.skip(keptScreenshots)) {
      try {
        await old.delete();
      } on FileSystemException {
        // Gone already.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Guard: challenge pages, JavaScript dialogs, pacing, Stop
  // ---------------------------------------------------------------------------

  /// The verification or refusal the current page shows, if any; the page
  /// shows a banner for it.
  final ValueNotifier<BrowserChallenge?> challenge =
      ValueNotifier<BrowserChallenge?>(null);

  String? _pageUrl;
  int? _mainFrameStatus;

  /// An HTTP error of a request; only the page's own one counts.
  void noteHttpError(Uri? uri, int? status) {
    if (uri != null && uri.toString() == _pageUrl) _mainFrameStatus = status;
  }

  /// Looks for a verification or refusal on the current page and publishes
  /// it on [challenge]. Never throws: a page that cannot be read has none.
  Future<BrowserChallenge?> checkChallenge() async {
    final controller = _controller;
    if (controller == null) return null;
    Map<String, dynamic>? signals;
    try {
      signals = await _runJson(BrowserGuard.challengeScript);
    } catch (_) {}
    final url = await controller.currentUrl();
    final found = BrowserGuard.classify(
      status: _mainFrameStatus,
      url: url,
      signals: signals,
    );
    challenge.value = found;
    return found;
  }

  /// Shows dialogs to the user while they look at the browser page and
  /// nothing runs; set by that page.
  BrowserDialogPresenter? dialogPresenter;

  final List<BrowserDialogRecord> _dialogs = <BrowserDialogRecord>[];

  /// Answers the page's `alert`, `confirm` and `prompt` so they never hang
  /// it: the user answers them while looking at the page, otherwise the page
  /// gets the default (OK, accept, the suggested text) and the model hears
  /// about it with its next result.
  void installDialogHandlers(WebViewController controller) {
    controller
      ..setOnJavaScriptAlertDialog((request) async {
        await _answerDialog('alert', request.message, null);
      })
      ..setOnJavaScriptConfirmDialog(
        (request) async =>
            await _answerDialog('confirm', request.message, null) == 'accepted',
      )
      ..setOnJavaScriptTextInputDialog(
        (request) async =>
            await _answerDialog(
              'prompt',
              request.message,
              request.defaultText ?? '',
            ) ??
            '',
      );
  }

  Future<String?> _answerDialog(
    String kind,
    String message,
    String? defaultText,
  ) async {
    final presenter = dialogPresenter;
    final agentRunning =
        currentActivity.value?.outcome == BrowserActivityOutcome.running;
    if (presenter != null && isRouteCurrent && !agentRunning) {
      return presenter(kind, message, defaultText);
    }
    final answer = switch (kind) {
      'alert' => 'ok',
      'confirm' => 'accepted',
      _ => defaultText ?? '',
    };
    _dialogs.add(
      BrowserDialogRecord(kind: kind, message: message, answer: answer),
    );
    if (_dialogs.length > 10) _dialogs.removeAt(0);
    return answer;
  }

  /// The dialogs answered for the model since it last asked, oldest first.
  List<Map<String, Object?>> drainDialogs() {
    final drained = [for (final dialog in _dialogs) dialog.toJson()];
    _dialogs.clear();
    return drained;
  }

  final Map<String, DateTime> _lastActionAt = <String, DateTime>{};
  final math.Random _random = math.Random();

  /// Waits as long as [BrowserGuard.throttle] asks before [action] on the
  /// site of [url] (the current page when null).
  Future<void> pace(String action, {String? url}) async {
    final target = url ?? await _controller?.currentUrl();
    final host = BrowserGuard.host(target);
    if (host == null) return;
    final last = _lastActionAt[host];
    final delay = BrowserGuard.throttle(
      action,
      target,
      sinceLast: last == null ? null : DateTime.now().difference(last),
      jitter: _random.nextDouble(),
    );
    if (delay > Duration.zero) {
      await _interruptible(Future<void>.delayed(delay));
    }
    _lastActionAt[host] = DateTime.now();
  }

  Completer<void>? _stopSignal;

  /// A `browser_use` action starts; [requestStop] ends its waits.
  void beginAction() {
    _active?.lastUsed = clock();
    _stopSignal = Completer<void>()..future.ignore();
  }

  void endAction() {
    _stopSignal = null;
  }

  /// Stops the running action at its next wait (loading, pacing, polling).
  void requestStop() {
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) {
      signal.completeError(const BrowserStoppedException());
    }
  }

  @visibleForTesting
  bool get stopRequested => _stopSignal?.isCompleted ?? false;

  Future<T> _interruptible<T>(Future<T> future) {
    final signal = _stopSignal;
    if (signal == null) return future;
    if (signal.isCompleted) {
      future.ignore();
      return Future<T>.error(const BrowserStoppedException());
    }
    return Future.any<T>([
      future,
      signal.future.then<T>((_) => throw const BrowserStoppedException()),
    ]);
  }

  /// The live controller, for the mini window and a page re-expanding it.
  WebViewController? get controller => _controller;

  /// True while the browser page is closed but its WebView lives on in the
  /// floating mini window. `browser_use` keeps working against it.
  final ValueNotifier<bool> minimized = ValueNotifier<bool>(false);

  /// The controller is parked for a page to take back. Separate from
  /// [minimized] because the mini window must drop its WebView a frame
  /// before the page shows the same native view.
  bool _parked = false;

  /// Hands the page's controller over to the mini window instead of closing
  /// the session: navigation keeps feeding [pageStarted]/[pageFinished], and
  /// `browser_use: close` or [closeMinimized] ends it.
  void minimize(WebViewController controller) {
    if (!identical(_controller, controller)) return;
    isRouteCurrent = false;
    _closeHandler = closeMinimized;
    unawaited(
      BrowserHandoffs.instance.setNavigationDelegate(
        controller,
        _tabDelegate(_active!),
      ),
    );
    _parked = true;
    // Called from the page's dispose, while the tree is locked: show the
    // mini window once this frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_parked && identical(_controller, controller)) minimized.value = true;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Hides the mini window and waits a frame so its WebView is gone before a
  /// page shows the same controller.
  Future<void> releaseMiniWindow() async {
    if (!minimized.value) return;
    minimized.value = false;
    await WidgetsBinding.instance.endOfFrame;
  }

  /// The page taking the parked controller back; it registers itself again
  /// as the session owner.
  WebViewController? takeMinimized() {
    if (!_parked) return null;
    _parked = false;
    // Normally already hidden by [releaseMiniWindow]; this runs from a
    // page's initState, so never notify synchronously here.
    if (minimized.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_parked) minimized.value = false;
      });
    }
    return _controller;
  }

  /// Closes a minimized browser: the same cleanup as closing the page.
  Future<void> closeMinimized() async {
    final controller = _controller;
    _parked = false;
    minimized.value = false;
    if (controller != null) unregister(controller);
  }

  void expectNavigation() {
    _loading = true;
    _readyCompleter = Completer<void>();
  }

  void register(
    WebViewController controller, {
    Future<void> Function()? onClose,
  }) {
    var tab = _tabFor(controller);
    if (tab == null) {
      tab = BrowserTab(
        id: 'tab${++_nextTabId}',
        controller: controller,
        byAgent: false,
        lastUsed: clock(),
      );
      _tabs.add(tab);
    }
    _active = tab;
    _publishTabsSoon();
    _closeHandler = onClose;
    final attached = _attachedCompleter;
    if (attached != null && !attached.isCompleted) attached.complete();
    _attachedCompleter = null;
  }

  void unregister(WebViewController controller) {
    if (!identical(_controller, controller)) return;
    for (final tab in _tabs) {
      if (!identical(tab.controller, controller)) {
        // Stop the background pages: their scripts and media keep running.
        unawaited(tab.controller.loadRequest(Uri.parse('about:blank')));
      }
    }
    _tabs.clear();
    _active = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _publishTabsSoon();
    _closeHandler = null;
    _attachedCompleter = null;
    _parked = false;
    minimized.value = false;
    _loading = false;
    _history.clear();
    ownerConversationId = null;
    isRouteCurrent = false;
    _askAiTasks.clear();
    challenge.value = null;
    _dialogs.clear();
    dialogPresenter = null;
    currentActivity.value = null;
    recentActivityNotifier.value = const <BrowserActivity>[];
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('Shared browser was closed.'));
    }
    _readyCompleter = null;
  }

  BrowserTab? _tabFor(WebViewController controller) {
    for (final tab in _tabs) {
      if (identical(tab.controller, controller)) return tab;
    }
    return null;
  }

  BrowserTab? _tabById(String id) {
    for (final tab in _tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  bool _tabsPublishScheduled = false;

  List<BrowserTabInfo> _tabInfos() => List<BrowserTabInfo>.unmodifiable([
    for (final tab in _tabs) tab.info(active: identical(tab, _active)),
  ]);

  void _publishTabs() {
    tabs.value = _tabInfos();
  }

  /// [_publishTabs] for [register] and [unregister]: a page calls them
  /// while widgets build, when listeners (the mini window) must not
  /// rebuild, so the update waits until that synchronous build is over.
  void _publishTabsSoon() {
    if (_tabsPublishScheduled) return;
    _tabsPublishScheduled = true;
    scheduleMicrotask(() {
      _tabsPublishScheduled = false;
      _publishTabs();
    });
  }

  List<Map<String, Object?>> _tabsJson() => [
    for (final info in _tabInfos()) info.toJson(),
  ];

  Future<void> _refreshTitle(BrowserTab tab) async {
    try {
      final title = await tab.controller.getTitle();
      if (!_tabs.contains(tab) || title == tab.title) return;
      tab.title = title;
      _publishTabs();
    } catch (_) {
      // The page went away meanwhile.
    }
  }

  /// Navigation of a tab while the browser page does not drive it (it is in
  /// the background, or the browser is minimized): the tab keeps its own
  /// address, title and history, and the active one feeds the session.
  NavigationDelegate _tabDelegate(BrowserTab tab) => NavigationDelegate(
    onPageStarted: (url) {
      if (identical(tab, _active)) {
        pageStarted(url);
        return;
      }
      tab
        ..url = url
        ..loading = true;
      _publishTabs();
    },
    onPageFinished: (url) {
      if (identical(tab, _active)) {
        pageFinished(url);
        return;
      }
      tab
        ..url = url
        ..loading = false;
      tab.history.reconcileCommitted(url);
      _publishTabs();
      unawaited(_refreshTitle(tab));
    },
    onHttpError: (error) {
      if (identical(tab, _active)) {
        noteHttpError(error.request?.uri, error.response?.statusCode);
      }
    },
  );

  /// Puts [tab] on screen: the session's page state becomes the tab's.
  void _activate(BrowserTab tab) {
    _active = tab;
    tab.lastUsed = clock();
    _navigationSequence++;
    _loading = tab.loading;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('The tab changed.'));
      ready.future.ignore();
    }
    _readyCompleter = tab.loading ? Completer<void>() : null;
    _pageUrl = tab.url;
    _mainFrameStatus = null;
    challenge.value = null;
    pageUrl.value = tab.url;
    pageLoading.value = tab.loading;
    _publishTabs();
  }

  /// Opens a new tab and puts it on screen, loading [url] when given.
  Future<Map<String, dynamic>> newTab({String? url, bool byAgent = false}) {
    return _newTab(
      url: url == null ? null : Uri.tryParse(url),
      byAgent: byAgent,
    );
  }

  Future<Map<String, dynamic>> _newTab({
    Uri? url,
    required bool byAgent,
  }) async {
    final factory = controllerFactory;
    if (!isAttached || factory == null) {
      return {
        'ok': false,
        'error': 'browser_not_open',
        'message': 'Open the browser first (action=open).',
      };
    }
    if (_tabs.length >= maxTabs) {
      return {
        'ok': false,
        'error': 'too_many_tabs',
        'message': 'At most $maxTabs tabs are open. Close one first.',
        'tabs': _tabsJson(),
      };
    }
    final controller = factory();
    final tab = BrowserTab(
      id: 'tab${++_nextTabId}',
      controller: controller,
      byAgent: byAgent,
      lastUsed: clock(),
    );
    _tabs.add(tab);
    await BrowserHandoffs.instance.setNavigationDelegate(
      controller,
      _tabDelegate(tab),
    );
    installDialogHandlers(controller);
    await _switchAway();
    _activate(tab);
    if (byAgent) _ensureIdleTimer();
    if (url != null) {
      await load(url);
    } else {
      expectNavigation();
      await controller.loadRequest(Uri.parse('about:blank'));
    }
    return {'ok': true, 'tab_id': tab.id, 'tabs': _tabsJson()};
  }

  /// The active tab stops being driven by the page before another one
  /// takes the screen.
  Future<void> _switchAway() async {
    final previous = _active;
    if (previous == null) return;
    await BrowserHandoffs.instance.setNavigationDelegate(
      previous.controller,
      _tabDelegate(previous),
    );
  }

  /// Puts the tab [id] on screen.
  Future<Map<String, dynamic>> switchTab(String id) async {
    final tab = _tabById(id);
    if (tab == null) {
      return {
        'ok': false,
        'error': 'no_such_tab',
        'message': 'There is no tab $id.',
        'tabs': _tabsJson(),
      };
    }
    if (!identical(tab, _active)) {
      await _switchAway();
      _activate(tab);
    }
    return {
      'ok': true,
      'tab_id': tab.id,
      if (tab.url != null) 'url': tab.url,
      'tabs': _tabsJson(),
    };
  }

  /// Closes the tab [id]; closing the last one closes the browser.
  Future<Map<String, dynamic>> closeTab(String id) async {
    final tab = _tabById(id);
    if (tab == null) {
      return {
        'ok': false,
        'error': 'no_such_tab',
        'message': 'There is no tab $id.',
        'tabs': _tabsJson(),
      };
    }
    if (_tabs.length == 1) return close();
    if (identical(tab, _active)) {
      final index = _tabs.indexOf(tab);
      final next = _tabs[index + 1 < _tabs.length ? index + 1 : index - 1];
      await _switchAway();
      _activate(next);
    }
    _removeTab(tab);
    return {'ok': true, 'closed': id, 'tabs': _tabsJson()};
  }

  void _removeTab(BrowserTab tab) {
    _tabs.remove(tab);
    unawaited(tab.controller.loadRequest(Uri.parse('about:blank')));
    if (!_tabs.any((t) => t.byAgent)) {
      _idleTimer?.cancel();
      _idleTimer = null;
    }
    _publishTabs();
  }

  void _ensureIdleTimer() {
    _idleTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => closeIdleAgentTabs(),
    );
  }

  /// Closes the tabs the model opened and left unused for [agentTabIdle],
  /// except the one on screen; returns their ids.
  List<String> closeIdleAgentTabs() {
    final now = clock();
    final idle = [
      for (final tab in _tabs)
        if (tab.byAgent &&
            !identical(tab, _active) &&
            now.difference(tab.lastUsed) >= agentTabIdle)
          tab,
    ];
    for (final tab in idle) {
      _removeTab(tab);
    }
    return [for (final tab in idle) tab.id];
  }

  /// The open tabs for the model.
  Map<String, dynamic> listTabs() => {
    'ok': true,
    'tabs': _tabsJson(),
    'max_tabs': maxTabs,
  };

  /// Shows the active tab's sites as on a computer or as on a phone, and
  /// reloads it.
  Future<Map<String, dynamic>> setDesktopMode(bool desktop) async {
    final tab = _active;
    if (tab == null) {
      return {
        'ok': false,
        'error': 'browser_not_open',
        'message': 'Shared browser is not open.',
      };
    }
    if (tab.desktop != desktop) {
      final controller = tab.controller;
      tab.mobileUserAgent ??= await controller.getUserAgent();
      await controller.setUserAgent(
        desktop ? desktopUserAgent(tab.mobileUserAgent) : null,
      );
      tab.desktop = desktop;
      _publishTabs();
      if (tab.url != null && tab.url != 'about:blank') {
        expectNavigation();
        await controller.reload();
        await waitUntilReady();
      }
    }
    return {
      'ok': true,
      'mode': desktop ? 'desktop' : 'mobile',
      if (tab.url != null) 'url': tab.url,
    };
  }

  /// Signs the active tab's site out: deletes its cookies and the page's
  /// storage in this browser, then reloads. Other sites keep theirs.
  Future<Map<String, dynamic>> clearSiteData() async {
    final tab = _active;
    final url = tab?.url;
    final host = BrowserGuard.host(url);
    if (tab == null || url == null || host == null) {
      return {'ok': false, 'error': 'no_site', 'message': 'No site is open.'};
    }
    try {
      await tab.controller.runJavaScript(_clearStorageScript);
    } catch (_) {
      // A page without storage access (an error page) has nothing to clear.
    }
    try {
      await _browserChannel.invokeMethod<int>('clearCookies', {'url': url});
    } on MissingPluginException {
      // Not on the phone (tests).
    }
    expectNavigation();
    await tab.controller.reload();
    await waitUntilReady();
    return {'ok': true, 'site': host};
  }

  static const String _clearStorageScript = r'''
(() => {
  try { localStorage.clear(); } catch (e) {}
  try { sessionStorage.clear(); } catch (e) {}
  try {
    if (indexedDB.databases) {
      indexedDB.databases().then((dbs) => dbs.forEach((db) => {
        if (db.name) indexedDB.deleteDatabase(db.name);
      }));
    }
  } catch (e) {}
  try {
    if (window.caches) caches.keys().then((keys) => keys.forEach((k) => caches.delete(k)));
  } catch (e) {}
  try {
    if (navigator.serviceWorker) {
      navigator.serviceWorker.getRegistrations().then((rs) => rs.forEach((r) => r.unregister()));
    }
  } catch (e) {}
})();
''';

  /// The page the shared browser shows, for the mini window.
  final ValueNotifier<String?> pageUrl = ValueNotifier<String?>(null);

  /// Whether that page is still loading.
  final ValueNotifier<bool> pageLoading = ValueNotifier<bool>(false);

  void pageStarted(String url) {
    final tab = _active;
    if (tab != null) {
      tab
        ..url = url
        ..loading = true;
      _publishTabs();
    }
    _navigationSequence++;
    _loading = true;
    pageLoading.value = true;
    pageUrl.value = url;
    _pageUrl = url;
    _mainFrameStatus = null;
    challenge.value = null;
    final previous = _readyCompleter;
    if (previous == null || previous.isCompleted) {
      _readyCompleter = Completer<void>();
    }
  }

  void pageFinished(String url) {
    final tab = _active;
    if (tab != null) {
      tab
        ..url = url
        ..loading = false;
      unawaited(_refreshTitle(tab));
    }
    _loading = false;
    pageLoading.value = false;
    pageUrl.value = url;
    // The single, central reconciliation point for every committed
    // navigation on the shared controller — see
    // BrowserNavigationHistory's doc comment for the full contract. This
    // fires for agent-initiated loads (open/back/forward/reload/a click or
    // submit that navigates) exactly as it does for the user editing the
    // address bar or tapping a link, so `_history` never drifts from what
    // native back/forward would actually do.
    _history.reconcileCommitted(url);
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  Future<void> waitUntilAttached({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_controller != null) return;
    _attachedCompleter ??= Completer<void>();
    await _attachedCompleter!.future.timeout(timeout);
  }

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_controller == null) {
      throw StateError('Shared browser is not open.');
    }
    if (!_loading) return;
    final ready = _readyCompleter ??= Completer<void>();
    await _interruptible(ready.future.timeout(timeout));
  }

  Future<void> load(Uri uri) async {
    final controller = _requireController();
    expectNavigation();
    await controller.loadRequest(uri);
    // waitUntilReady() only returns once pageFinished() has already run,
    // which is where `_history` is reconciled centrally — no separate push
    // needed here (see BrowserNavigationHistory's doc comment).
    await waitUntilReady();
  }

  Future<void> recordInitialPage() async {
    await waitUntilReady();
    final url = await _requireController().currentUrl();
    if (url != null && url.isNotEmpty) {
      _history.reset(url);
    }
  }

  Future<Map<String, dynamic>> close() async {
    if (!isAttached) {
      return {
        'ok': false,
        'error': 'browser_not_open',
        'message': 'Shared browser is not open.',
      };
    }
    final closeHandler = _closeHandler;
    if (closeHandler == null) {
      throw const BrowserAgentProtocolException(
        'Shared browser close handler is unavailable.',
      );
    }
    await closeHandler();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (isAttached && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (isAttached) {
      return {
        'ok': false,
        'error': 'browser_close_timeout',
        'message': 'Shared browser did not close in time.',
      };
    }
    return {'ok': true, 'closed': true};
  }

  Future<Map<String, dynamic>> observe({
    String scope = 'viewport',
    int maxTextChars = 3000,
    int maxElements = 36,
    bool includeText = true,
  }) async {
    await waitUntilReady();
    final normalizedScope = scope == 'document' ? 'document' : 'viewport';
    final textLimit = maxTextChars.clamp(256, 8000).toInt();
    final elementLimit = maxElements.clamp(1, 80).toInt();
    final script = _observeScript
        .replaceAll('__SCOPE__', jsonEncode(normalizedScope))
        .replaceAll('__TEXT_LIMIT__', '$textLimit')
        .replaceAll('__ELEMENT_LIMIT__', '$elementLimit')
        .replaceAll('__INCLUDE_TEXT__', includeText ? 'true' : 'false');
    return _runJson(script);
  }

  Future<Map<String, dynamic>> click(int elementId) async {
    await waitUntilReady();
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final result = await _runJson(
      _clickScript.replaceAll('__ELEMENT_ID__', '$elementId'),
    );
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: result['may_navigate'] == true
            ? const Duration(seconds: 1)
            : const Duration(milliseconds: 180),
      );
      // Any navigation this click caused was already reconciled into
      // `_history` by pageFinished() as part of the wait above.
    }
    final visibleResult = Map<String, dynamic>.from(result)
      ..remove('may_navigate');
    return _withCurrentUrl(visibleResult);
  }

  /// Clicks the page at viewport point ([x], [y]) in CSS pixels, for what
  /// observe lists no element for: canvases, maps, custom widgets.
  Future<Map<String, dynamic>> clickAt(num x, num y) async {
    await waitUntilReady();
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final result = await _runJson(_pointerScript('click', x: x, y: y));
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: const Duration(seconds: 1),
      );
    }
    return _withCurrentUrl(result);
  }

  /// Moves the pointer over an element from observe or a viewport point,
  /// which opens hover menus and tooltips.
  Future<Map<String, dynamic>> hover({int? elementId, num? x, num? y}) async {
    await waitUntilReady();
    final result = await _runJson(
      _pointerScript('hover', elementId: elementId, x: x, y: y),
    );
    // Menus open on the next frames.
    await _interruptible(
      Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    return result;
  }

  static String _pointerScript(String mode, {int? elementId, num? x, num? y}) =>
      _pointerScriptTemplate
          .replaceAll('__MODE__', jsonEncode(mode))
          .replaceAll('__ELEMENT_ID__', '${elementId ?? 0}')
          .replaceAll('__X__', '${x ?? -1}')
          .replaceAll('__Y__', '${y ?? -1}');

  Future<Map<String, dynamic>> type(int elementId, String text) async {
    await waitUntilReady();
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final script = _typeScript
        .replaceAll('__ELEMENT_ID__', '$elementId')
        .replaceAll('__TEXT__', jsonEncode(text));
    final result = await _runJson(script);
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: const Duration(milliseconds: 250),
      );
    }
    return _withCurrentUrl(result);
  }

  Future<Map<String, dynamic>> submit(int elementId) async {
    await waitUntilReady();
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final result = await _runJson(
      _submitScript.replaceAll('__ELEMENT_ID__', '$elementId'),
    );
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: const Duration(seconds: 1),
      );
    }
    return _withCurrentUrl(result);
  }

  Future<Map<String, dynamic>> pressKey(String key) async {
    await waitUntilReady();
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final result = await _runJson(
      _pressKeyScript.replaceAll('__KEY__', jsonEncode(key)),
    );
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: const Duration(milliseconds: 250),
      );
    }
    return _withCurrentUrl(result);
  }

  Future<Map<String, dynamic>> scroll({
    required String direction,
    int? amount,
  }) async {
    await waitUntilReady();
    const allowed = {'up', 'down', 'top', 'bottom'};
    if (!allowed.contains(direction)) {
      throw ArgumentError('direction must be up, down, top, or bottom.');
    }
    final safeAmount = (amount ?? 0).clamp(0, 5000).toInt();
    final script = _scrollScript
        .replaceAll('__DIRECTION__', jsonEncode(direction))
        .replaceAll('__AMOUNT__', '$safeAmount');
    return _runJson(script);
  }

  /// Reads the rendered page text for the browser research path.
  ///
  /// Implements [RenderedPageReader]: a whole-document read (no selector) is reported as
  /// [RenderedScope.fullPage] and doubles as the research corpus, so [browserTextEnvelope]
  /// can hand out a `source_id`. A selector-scoped read is [RenderedScope.selector] and is
  /// never cached as a page-level source. There is no article/Readability heuristic yet: the
  /// extract mode is honestly reported as `raw` rather than claiming a pass this layer does
  /// not run.
  Future<RenderedRead> read(ReadRequest request) async {
    if (!isAttached) return const RenderedReadNotOpen();
    await waitUntilReady();
    final selector = request.selector;
    Map<String, dynamic> result;
    try {
      result = await _runJson(
        _readScript
            .replaceAll('__SELECTOR__', jsonEncode(selector ?? ''))
            .replaceAll('__MAX_CHARS__', '$browserResearchMaxChars'),
      );
    } on BrowserAgentProtocolException catch (error) {
      return RenderedReadFailure(
        'browser_protocol_error',
        detail: error.message,
      );
    }
    if (result['ok'] != true) {
      return RenderedReadFailure(
        (result['error'] ?? 'read_failed').toString(),
        detail: result['message']?.toString(),
      );
    }
    final text = (result['text'] ?? '').toString();
    final truncated = result['truncated'] == true;
    final scope = selector == null
        ? RenderedScope.fullPage
        : RenderedScope.selector;
    return RenderedReadOk(
      RenderedPage(
        url: result['url']?.toString(),
        title: result['title']?.toString(),
        text: text,
        extractMode: 'raw',
        scope: scope,
        readTruncated: truncated,
        researchText: scope == RenderedScope.fullPage ? text : null,
        researchTruncated: truncated,
      ),
    );
  }

  /// Waits until [selector] reaches [state] (or [timeoutMs] elapses). Polls a synchronous
  /// JS check from the Dart side, matching this file's other actions, rather than an async
  /// IIFE returned through `evaluateJavascript`: Android WebView's completion value for a
  /// pending Promise is unreliable across versions, so the wait loop lives in Dart instead.
  Future<Map<String, dynamic>> waitFor({
    required String selector,
    String state = 'attached',
    String? containsText,
    int timeoutMs = 10000,
  }) async {
    await waitUntilReady();
    const allowedStates = {'attached', 'detached', 'visible', 'hidden'};
    if (!allowedStates.contains(state)) {
      throw ArgumentError(
        'state must be one of attached, detached, visible, or hidden.',
      );
    }
    final clampedTimeout = timeoutMs.clamp(200, 30000);
    final script = _waitForScript
        .replaceAll('__SELECTOR__', jsonEncode(selector))
        .replaceAll('__STATE__', jsonEncode(state))
        .replaceAll(
          '__CONTAINS_TEXT__',
          containsText == null ? 'null' : jsonEncode(containsText),
        );
    final start = DateTime.now();
    final deadline = start.add(Duration(milliseconds: clampedTimeout));
    while (true) {
      final result = await _runJson(script);
      // A selector the page's own querySelectorAll rejects will never be satisfied;
      // report it now instead of burning the whole timeout on a doomed poll.
      if (result['error'] != null) {
        return {
          'ok': false,
          'error': result['error'],
          'message':
              result['message'] ?? 'The selector could not be evaluated.',
        };
      }
      if (result['satisfied'] == true) {
        return {
          'ok': true,
          'found': true,
          'elapsed_ms': DateTime.now().difference(start).inMilliseconds,
        };
      }
      if (DateTime.now().isAfter(deadline)) {
        return {
          'ok': true,
          'found': false,
          'elapsed_ms': DateTime.now().difference(start).inMilliseconds,
        };
      }
      await _interruptible(
        Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    }
  }

  static int _fetchSequence = 0;

  /// Requests [url] from inside the page with its cookies and login, like
  /// the page's own scripts: an API the site calls, a JSON feed, a page of
  /// the same site without opening it. Other sites answer only when they
  /// allow it (CORS). Text answers come back cut to [maxChars]; binary ones
  /// only with their type and size.
  Future<Map<String, dynamic>> fetchInPage({
    required String url,
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    int maxChars = 20000,
    int timeoutMs = 20000,
  }) async {
    await waitUntilReady();
    final controller = _requireController();
    final base = Uri.tryParse(await controller.currentUrl() ?? '');
    final target = base == null ? Uri.tryParse(url) : base.resolve(url);
    if (target == null ||
        !(target.isScheme('http') || target.isScheme('https'))) {
      return {
        'ok': false,
        'error': 'invalid_url',
        'message': 'fetch needs an http(s) URL or a path of the open page.',
      };
    }
    final verb = method.toUpperCase();
    const verbs = {'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'};
    if (!verbs.contains(verb)) {
      return {
        'ok': false,
        'error': 'invalid_method',
        'message': 'method must be one of ${verbs.join(', ')}.',
      };
    }
    final id = 'f${++_fetchSequence}';
    final start = _fetchStartScript
        .replaceAll('__ID__', jsonEncode(id))
        .replaceAll('__URL__', jsonEncode(target.toString()))
        .replaceAll('__METHOD__', jsonEncode(verb))
        .replaceAll('__HEADERS__', jsonEncode(headers))
        .replaceAll(
          '__BODY__',
          body == null || verb == 'GET' || verb == 'HEAD'
              ? 'null'
              : jsonEncode(body),
        )
        .replaceAll('__MAX__', '${maxChars.clamp(100, 200000)}');
    await _runJson(start);
    final poll = _fetchPollScript.replaceAll('__ID__', jsonEncode(id));
    final deadline = DateTime.now().add(
      Duration(milliseconds: timeoutMs.clamp(1000, 60000)),
    );
    while (true) {
      final result = await _runJson(poll);
      if (result['done'] == true) {
        result.remove('done');
        if (result['ok'] != true) {
          result['error'] ??= 'fetch_failed';
          result['message'] =
              '${result['message'] ?? 'The request failed.'} Requests to '
              'other sites need them to allow it (CORS): open that site first.';
        }
        return result;
      }
      if (DateTime.now().isAfter(deadline)) {
        await _runJson(_fetchForgetScript.replaceAll('__ID__', jsonEncode(id)));
        return {
          'ok': false,
          'error': 'timeout',
          'message': 'No answer in time.',
        };
      }
      await _interruptible(
        Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    }
  }

  static const String _fetchStartScript = r'''
(() => {
  const store = window.__moruFetch = window.__moruFetch || {};
  const slot = store[__ID__] = {done: false};
  const init = {method: __METHOD__, credentials: 'include', headers: __HEADERS__};
  const body = __BODY__;
  if (body !== null) init.body = body;
  const textual = /^(text\/|application\/(json|xml|javascript|x-www-form-urlencoded|ld\+json|rss\+xml|atom\+xml))|\+(json|xml)(;|$)/i;
  fetch(__URL__, init).then(async (response) => {
    const type = response.headers.get('content-type') || '';
    const answer = {
      done: true, ok: true, status: response.status, url: response.url,
      content_type: type
    };
    if (init.method !== 'HEAD' && (type === '' || textual.test(type))) {
      const text = await response.text();
      answer.text = text.slice(0, __MAX__);
      answer.total_chars = text.length;
      answer.truncated = text.length > __MAX__;
    } else if (init.method !== 'HEAD') {
      const size = response.headers.get('content-length');
      answer.binary = true;
      if (size) answer.bytes = Number(size);
      answer.note = 'Binary answer: open or click it in the browser to download it.';
    }
    Object.assign(slot, answer);
  }).catch((error) => {
    Object.assign(slot, {done: true, ok: false, message: String(error && error.message || error)});
  });
  return JSON.stringify({started: true});
})()
''';

  static const String _fetchPollScript = r'''
(() => {
  const store = window.__moruFetch || {};
  const slot = store[__ID__];
  if (!slot) return JSON.stringify({done: true, ok: false, error: 'page_changed', message: 'The page changed during the request.'});
  if (!slot.done) return JSON.stringify({done: false});
  delete store[__ID__];
  return JSON.stringify(slot);
})()
''';

  static const String _fetchForgetScript = r'''
(() => { if (window.__moruFetch) delete window.__moruFetch[__ID__]; return JSON.stringify({ok: true}); })()
''';

  /// Runs [code] as the page's own script and returns its last expression, JSON-encoded.
  /// Caller (the `eval_js` tool) is responsible for pattern-blocking and approval.
  ///
  /// The code runs unwrapped, so a statement list works the same as an expression, but
  /// that also means a thrown exception is indistinguishable from a `null` result:
  /// Android's WebView resolves `evaluateJavascript` with the string `"null"` either
  /// way rather than reporting the throw, so `result: null` is reported for both and
  /// this method never claims to have detected a JS error it cannot see.
  Future<Map<String, dynamic>> evalJs(String code) async {
    if (!isAttached) {
      return {
        'ok': false,
        'error': 'browser_not_open',
        'message': 'Shared browser is not open.',
      };
    }
    await waitUntilReady();
    final controller = _requireController();
    Object? raw;
    try {
      raw = await controller.runJavaScriptReturningResult(code);
    } catch (error) {
      return {'ok': false, 'error': 'js_failed', 'message': error.toString()};
    }
    // The platform hands back the value already JSON-encoded (sometimes twice over),
    // which is why _runJson decodes up to two rounds. Re-encoding `raw` as-is would
    // ship `"\"Example\""` to the model instead of `"Example"`, so decode first and
    // encode exactly once.
    dynamic decoded = raw;
    for (var i = 0; i < 2 && decoded is String; i++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }
    final encoded = jsonEncode(decoded);
    final clipped = truncateHeadUtf16Safe(encoded, evalJsMaxResultChars);
    return {
      'ok': true,
      'result': clipped,
      'truncated': clipped.length < encoded.length,
    };
  }

  Future<Map<String, dynamic>> goBack() async {
    final controller = _requireController();
    await waitUntilReady();
    final target = _history.backTarget;
    if (target == null) {
      return {
        'ok': false,
        'error': 'no_history',
        'message': 'There is no previous page in browser history.',
      };
    }
    expectNavigation();
    await controller.loadRequest(Uri.parse(target));
    // waitUntilReady() only returns after pageFinished() has already
    // reconciled this exact URL against `_history.backTarget` and called
    // commitBack() itself — committing again here would double-step.
    await waitUntilReady(timeout: const Duration(seconds: 15));
    return _pageState();
  }

  Future<Map<String, dynamic>> goForward() async {
    final controller = _requireController();
    await waitUntilReady();
    final target = _history.forwardTarget;
    if (target == null) {
      return {
        'ok': false,
        'error': 'no_history',
        'message': 'There is no next page in browser history.',
      };
    }
    expectNavigation();
    await controller.loadRequest(Uri.parse(target));
    // Same reasoning as goBack(): pageFinished() already committed this
    // exact navigation via reconcileCommitted().
    await waitUntilReady(timeout: const Duration(seconds: 15));
    return _pageState();
  }

  Future<Map<String, dynamic>> reload() async {
    final controller = _requireController();
    await waitUntilReady();
    expectNavigation();
    await controller.reload();
    await waitUntilReady(timeout: const Duration(seconds: 15));
    return _pageState();
  }

  Future<void> _settleAfterInteraction({
    required int navigationSequence,
    required String? urlBefore,
    required Duration navigationGrace,
  }) async {
    final deadline = DateTime.now().add(navigationGrace);
    while (DateTime.now().isBefore(deadline)) {
      if (_navigationSequence != navigationSequence || _loading) {
        await waitUntilReady(timeout: const Duration(seconds: 15));
        return;
      }
      final currentUrl = await _requireController().currentUrl();
      if (urlBefore != null && currentUrl != null && currentUrl != urlBefore) {
        await _interruptible(
          Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        if (_loading) {
          await waitUntilReady(timeout: const Duration(seconds: 15));
        }
        return;
      }
      await _interruptible(
        Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
  }

  Future<Map<String, dynamic>> _withCurrentUrl(
    Map<String, dynamic> result,
  ) async {
    if (result['ok'] != true || _controller == null) return result;
    final url = await _controller!.currentUrl();
    return {...result, if (url != null) 'url': url};
  }

  Future<Map<String, dynamic>> _pageState() async {
    await waitUntilReady();
    final controller = _requireController();
    return {
      'ok': true,
      'url': await controller.currentUrl(),
      'can_go_back': _history.canGoBack,
      'can_go_forward': _history.canGoForward,
    };
  }

  WebViewController _requireController() {
    final controller = _controller;
    if (controller == null) throw StateError('Shared browser is not open.');
    return controller;
  }

  Future<Map<String, dynamic>> _runJson(String script) async {
    final result = await _requireController().runJavaScriptReturningResult(
      script,
    );
    dynamic decoded = result;
    for (var i = 0; i < 2 && decoded is String; i++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const BrowserAgentProtocolException(
      'Shared browser returned an invalid result.',
    );
  }

  static const String _clickScript = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const id = __ELEMENT_ID__;
  if (!(elements instanceof Map)) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before clicking.'
    });
  }
  if (!elements.has(id)) {
    return JSON.stringify({
      ok: false,
      error: 'invalid_element_id',
      message: 'Choose an element_id from the latest observe result.'
    });
  }
  const element = elements.get(id);
  if (!element || !element.isConnected) {
    return JSON.stringify({
      ok: false,
      error: 'stale_element',
      message: 'The element is no longer on the page. Observe again.'
    });
  }
  if (element.disabled) {
    return JSON.stringify({
      ok: false,
      error: 'disabled_element',
      message: 'The selected element is disabled.'
    });
  }
  const tag = element.tagName.toLowerCase();
  const inputType = tag === 'input'
      ? String(element.getAttribute('type') || 'text').toLowerCase()
      : '';
  const role = String(element.getAttribute('role') || '').toLowerCase();
  const mayNavigate = tag === 'a' || tag === 'button' ||
      role === 'link' || role === 'button' ||
      (tag === 'input' && ['submit', 'button', 'image'].includes(inputType)) ||
      Boolean(element.getAttribute('onclick'));
  element.scrollIntoView({block: 'center', inline: 'center'});
  element.click();
  return JSON.stringify({
    ok: true,
    element_id: id,
    may_navigate: mayNavigate
  });
})();
''';

  static const String _pointerScriptTemplate = r'''
(() => {
  const mode = __MODE__;
  const id = __ELEMENT_ID__;
  let x = __X__;
  let y = __Y__;
  let element = null;
  if (id > 0) {
    const elements = window.__moruBrowserElementRegistry;
    element = elements instanceof Map ? elements.get(id) : null;
    if (!element || !element.isConnected) {
      return JSON.stringify({
        ok: false,
        error: 'stale_element',
        message: 'The element is no longer on the page. Observe again.'
      });
    }
    element.scrollIntoView({block: 'center', inline: 'center'});
    const rect = element.getBoundingClientRect();
    x = rect.left + rect.width / 2;
    y = rect.top + rect.height / 2;
  } else {
    if (x < 0 || y < 0 || x > window.innerWidth || y > window.innerHeight) {
      return JSON.stringify({
        ok: false,
        error: 'point_outside_viewport',
        message: 'x and y are CSS pixels inside the viewport (' +
            window.innerWidth + 'x' + window.innerHeight + ').'
      });
    }
    element = document.elementFromPoint(x, y);
    if (!element) {
      return JSON.stringify({
        ok: false,
        error: 'nothing_at_point',
        message: 'There is no element at that point.'
      });
    }
  }
  // A point over a frame of the same site goes on to the element inside
  // it, in the frame's own coordinates; another site's frame is closed to
  // scripts, so the model is told to open it instead.
  let view = window;
  let fx = x;
  let fy = y;
  let framed = false;
  while (element && (element.tagName === 'IFRAME' || element.tagName === 'FRAME')) {
    let inner = null;
    try {
      inner = element.contentDocument;
    } catch (e) {}
    if (!inner) {
      return JSON.stringify({
        ok: false,
        error: 'cross_origin_frame',
        message: 'The point is inside a frame of another site, which the ' +
            'browser cannot reach. Open its address instead.',
        frame_src: String(element.src || '').slice(0, 300)
      });
    }
    const box = element.getBoundingClientRect();
    fx -= box.left + element.clientLeft;
    fy -= box.top + element.clientTop;
    const target = inner.elementFromPoint(fx, fy);
    if (!target) break;
    view = inner.defaultView || view;
    element = target;
    framed = true;
  }
  const base = {bubbles: true, cancelable: true, view, clientX: fx, clientY: fy};
  const pointer = (type) => {
    try {
      element.dispatchEvent(new PointerEvent(type, Object.assign({pointerType: 'touch', isPrimary: true}, base)));
    } catch (e) {}
  };
  const mouse = (type) => element.dispatchEvent(new MouseEvent(type, base));
  pointer('pointerover');
  pointer('pointerenter');
  mouse('mouseover');
  mouse('mouseenter');
  mouse('mousemove');
  if (mode === 'click') {
    pointer('pointerdown');
    mouse('mousedown');
    if (typeof element.focus === 'function') element.focus();
    pointer('pointerup');
    mouse('mouseup');
    element.click();
  }
  const tag = element.tagName.toLowerCase();
  const label = String(element.innerText || element.getAttribute('aria-label') ||
      element.getAttribute('title') || '').replace(/\s+/g, ' ').trim().slice(0, 80);
  const result = {ok: true, x: Math.round(x), y: Math.round(y), tag};
  if (framed) result.in_frame = true;
  if (label) result.text = label;
  return JSON.stringify(result);
})();
''';

  static const String _typeScript = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const id = __ELEMENT_ID__;
  const text = __TEXT__;
  if (!(elements instanceof Map)) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before typing.'
    });
  }
  if (!elements.has(id)) {
    return JSON.stringify({
      ok: false,
      error: 'invalid_element_id',
      message: 'Choose an element_id from the latest observe result.'
    });
  }
  const element = elements.get(id);
  if (!element || !element.isConnected) {
    return JSON.stringify({
      ok: false,
      error: 'stale_element',
      message: 'The element is no longer on the page. Observe again.'
    });
  }
  const tag = element.tagName.toLowerCase();
  const inputType = tag === 'input'
      ? String(element.getAttribute('type') || 'text').toLowerCase()
      : '';
  if (tag === 'input' && inputType === 'file') {
    return JSON.stringify({
      ok: false,
      error: 'unsupported_element_type',
      message: 'File inputs cannot be filled with browser_use type.'
    });
  }
  if (tag === 'select') {
    if (element.disabled) {
      return JSON.stringify({
        ok: false,
        error: 'not_editable',
        message: 'The selected element is disabled.'
      });
    }
    const wanted = String(text).trim().toLowerCase();
    const option = Array.from(element.options).find((item) =>
      String(item.value).trim().toLowerCase() === wanted ||
      String(item.textContent || '').trim().toLowerCase() === wanted
    );
    if (!option) {
      return JSON.stringify({
        ok: false,
        error: 'option_not_found',
        message: 'No select option matches the requested text or value.'
      });
    }
    element.focus();
    // Same native-setter trick as the text-input path below: React installs its own
    // setter on the element instance to track "last known value", so a direct
    // `element.value = ...` is invisible to it and the component silently keeps its
    // old selection even though the DOM (and this tool) say otherwise.
    const selectDescriptor = Object.getOwnPropertyDescriptor(
      window.HTMLSelectElement.prototype,
      'value'
    );
    if (selectDescriptor && selectDescriptor.set) {
      selectDescriptor.set.call(element, option.value);
    } else {
      element.value = option.value;
    }
    element.dispatchEvent(new Event('input', {bubbles: true}));
    element.dispatchEvent(new Event('change', {bubbles: true}));
    return JSON.stringify({
      ok: true,
      element_id: id,
      selected: String(option.textContent || option.value).trim().slice(0, 120)
    });
  }

  const editable = element.isContentEditable ||
      tag === 'input' || tag === 'textarea';
  if (!editable || element.disabled || element.readOnly) {
    return JSON.stringify({
      ok: false,
      error: 'not_editable',
      message: 'The selected element is not editable.'
    });
  }

  element.focus();
  if (element.isContentEditable) {
    element.textContent = text;
  } else {
    const proto = tag === 'textarea'
        ? window.HTMLTextAreaElement.prototype
        : window.HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
    if (descriptor && descriptor.set) {
      descriptor.set.call(element, text);
    } else {
      element.value = text;
    }
  }
  element.dispatchEvent(new Event('input', {bubbles: true}));
  element.dispatchEvent(new Event('change', {bubbles: true}));
  return JSON.stringify({
    ok: true,
    element_id: id,
    typed_length: text.length
  });
})();
''';

  static const String _submitScript = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const id = __ELEMENT_ID__;
  if (!(elements instanceof Map)) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before submitting.'
    });
  }
  if (!elements.has(id)) {
    return JSON.stringify({
      ok: false,
      error: 'invalid_element_id',
      message: 'Choose an element_id from the latest observe result.'
    });
  }
  const element = elements.get(id);
  if (!element || !element.isConnected) {
    return JSON.stringify({
      ok: false,
      error: 'stale_element',
      message: 'The element is no longer on the page. Observe again.'
    });
  }
  if (element.disabled) {
    return JSON.stringify({
      ok: false,
      error: 'not_editable',
      message: 'The selected element is disabled.'
    });
  }
  const tag = element.tagName.toLowerCase();
  const form = tag === 'form' ? element : (element.form || element.closest('form'));
  if (!form) {
    return JSON.stringify({
      ok: false,
      error: 'no_enclosing_form',
      message: 'No form contains this element.'
    });
  }
  const inputType = tag === 'input'
      ? String(element.getAttribute('type') || 'text').toLowerCase()
      : '';
  const isSubmitControl =
      (tag === 'button' && (element.type === 'submit' || element.type === '')) ||
      (tag === 'input' && (inputType === 'submit' || inputType === 'image'));
  if (isSubmitControl) {
    element.click();
    return JSON.stringify({ok: true, element_id: id, via: 'button_click'});
  }
  // requestSubmit() runs constraint validation and silently does nothing when the
  // form is invalid, so check first rather than reporting a submit that never happened.
  if (typeof form.checkValidity === 'function' && !form.checkValidity()) {
    if (typeof form.reportValidity === 'function') form.reportValidity();
    return JSON.stringify({
      ok: false,
      error: 'form_invalid',
      message: 'The form failed its own validation, so it was not submitted.'
    });
  }
  if (typeof form.requestSubmit === 'function') {
    form.requestSubmit();
  } else {
    form.submit();
  }
  return JSON.stringify({ok: true, element_id: id, via: 'form_submit'});
})();
''';

  static const String _pressKeyScript = r'''
(() => {
  const key = __KEY__;
  try {
    const el = document.activeElement || document.body;
    // Legacy keyCode/which are deprecated but still what a lot of handlers read
    // (`e.keyCode === 13`); without them Enter silently does nothing on those pages.
    const legacyCodes = {
      Enter: 13, Tab: 9, Escape: 27, Backspace: 8, Delete: 46, ' ': 32,
      ArrowUp: 38, ArrowDown: 40, ArrowLeft: 37, ArrowRight: 39,
      Home: 36, End: 35, PageUp: 33, PageDown: 34
    };
    const keyCode = Object.prototype.hasOwnProperty.call(legacyCodes, key)
        ? legacyCodes[key]
        : (key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0);
    const init = {
      key,
      code: key.length === 1 ? 'Key' + key.toUpperCase() : key,
      keyCode,
      which: keyCode,
      bubbles: true,
      cancelable: true
    };
    const down = new KeyboardEvent('keydown', init);
    el.dispatchEvent(down);
    if (key.length === 1) {
      el.dispatchEvent(new KeyboardEvent('keypress', init));
    }
    el.dispatchEvent(new KeyboardEvent('keyup', init));
    return JSON.stringify({ok: true, key, default_prevented: down.defaultPrevented});
  } catch (e) {
    return JSON.stringify({ok: false, error: 'js_failed', message: String(e)});
  }
})();
''';

  static const String _waitForScript = r'''
(() => {
  const selector = __SELECTOR__;
  const state = __STATE__;
  const containsText = __CONTAINS_TEXT__;
  // Same rule observe's hasBox uses: offsetParent/getClientRects stay truthy for
  // visibility:hidden and opacity:0, which would make state=visible fire on an
  // invisible element and state=hidden unsatisfiable.
  function visible(el) {
    const style = window.getComputedStyle(el);
    if (style.visibility === 'hidden' || style.display === 'none') return false;
    if (parseFloat(style.opacity || '1') === 0) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  function hasText(el) {
    if (!containsText) return true;
    const text = (el.innerText || el.textContent || '');
    return text.indexOf(containsText) !== -1;
  }
  try {
    if (state === 'detached') {
      return JSON.stringify({satisfied: document.querySelector(selector) === null});
    }
    const elements = document.querySelectorAll(selector);
    if (state === 'hidden') {
      for (const el of elements) {
        if (visible(el)) return JSON.stringify({satisfied: false});
      }
      return JSON.stringify({satisfied: true});
    }
    if (state === 'visible') {
      for (const el of elements) {
        if (visible(el) && hasText(el)) return JSON.stringify({satisfied: true});
      }
      return JSON.stringify({satisfied: false});
    }
    // 'attached' (default)
    for (const el of elements) {
      if (hasText(el)) return JSON.stringify({satisfied: true});
    }
    return JSON.stringify({satisfied: false});
  } catch (e) {
    return JSON.stringify({
      satisfied: false,
      error: 'invalid_selector',
      message: String(e)
    });
  }
})();
''';

  static const String _readScript = r'''
(() => {
  const selector = __SELECTOR__;
  const maxChars = __MAX_CHARS__;
  let root;
  if (selector) {
    root = document.querySelector(selector);
    if (!root) {
      return JSON.stringify({
        ok: false,
        error: 'selector_not_found',
        message: 'No element matches the given selector.'
      });
    }
  } else {
    root = document.body;
  }
  if (!root) {
    return JSON.stringify({
      ok: false,
      error: 'read_unavailable',
      message: 'The page has no readable content yet.'
    });
  }
  // textContent (not innerText) so a page that hides most sections behind
  // CSS until the user taps them (e.g. Wikipedia's mobile skin collapses
  // every section but the lead) still yields its full body text; innerText
  // is visibility-aware and would return only what's on-screen right now.
  // script/style/template are stripped first so their source code never
  // leaks into the "page text" the way textContent normally would.
  const clone = root.cloneNode(true);
  clone.querySelectorAll('script, style, noscript, template').forEach((el) => el.remove());
  const raw = (clone.textContent || '').toString();
  const truncated = raw.length > maxChars;
  const text = truncated ? raw.slice(0, maxChars) : raw;
  return JSON.stringify({
    ok: true,
    url: (document.location && document.location.href) || '',
    title: document.title || '',
    text,
    truncated
  });
})();
''';

  static const String _scrollScript = r'''
(() => {
  const direction = __DIRECTION__;
  const requested = __AMOUNT__;
  const defaultStep = Math.max(240, Math.floor(window.innerHeight * 0.78));
  const amount = requested > 0 ? requested : defaultStep;
  if (direction === 'top') {
    window.scrollTo({top: 0, behavior: 'instant'});
  } else if (direction === 'bottom') {
    window.scrollTo({top: document.documentElement.scrollHeight, behavior: 'instant'});
  } else {
    window.scrollBy({
      top: direction === 'up' ? -amount : amount,
      behavior: 'instant'
    });
  }
  const doc = document.documentElement;
  const maxY = Math.max(0, doc.scrollHeight - window.innerHeight);
  return JSON.stringify({
    ok: true,
    scroll_y: Math.round(window.scrollY),
    viewport_h: window.innerHeight,
    document_h: doc.scrollHeight,
    at_top: window.scrollY <= 1,
    at_bottom: window.scrollY >= maxY - 1
  });
})();
''';

  static const String _observeScript = r'''
(() => {
  const scope = __SCOPE__;
  const maxText = __TEXT_LIMIT__;
  const maxElements = __ELEMENT_LIMIT__;
  const includeText = __INCLUDE_TEXT__;
  const normalize = (value) => String(value || '')
      .replace(/\s+/g, ' ')
      .trim();
  const hasBox = (element) => {
    const style = window.getComputedStyle(element);
    if (style.visibility === 'hidden' || style.display === 'none') return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const inViewport = (element) => {
    if (!hasBox(element)) return false;
    const rect = element.getBoundingClientRect();
    return rect.bottom >= 0 && rect.top <= window.innerHeight &&
        rect.right >= 0 && rect.left <= window.innerWidth;
  };
  const visible = scope === 'document' ? hasBox : inViewport;

  const candidates = Array.from(document.querySelectorAll(
    'a,button,input,textarea,select,summary,[role="button"],[role="link"],[contenteditable="true"]'
  )).filter(visible).slice(0, maxElements);

  if (!(window.__moruBrowserElementRegistry instanceof Map)) {
    window.__moruBrowserElementRegistry = new Map();
    window.__moruBrowserElementIds = new WeakMap();
    window.__moruBrowserNextElementId = 1;
  }
  const registry = window.__moruBrowserElementRegistry;
  const ids = window.__moruBrowserElementIds;

  const elements = candidates.map((element) => {
    const tag = element.tagName.toLowerCase();
    const inputType = tag === 'input'
        ? String(element.getAttribute('type') || 'text').toLowerCase()
        : null;
    const password = inputType === 'password';
    const label = normalize(
      element.innerText ||
      element.getAttribute('aria-label') ||
      element.getAttribute('title') ||
      element.getAttribute('alt') ||
      (!password ? element.value : '') ||
      ''
    ).slice(0, 140);
    const placeholder = normalize(element.getAttribute('placeholder')).slice(0, 100);
    const value = password ? '' : normalize(element.value).slice(0, 120);
    const href = tag === 'a'
        ? normalize(element.getAttribute('href')).slice(0, 180)
        : '';
    let id = ids.get(element);
    if (!id) {
      id = window.__moruBrowserNextElementId++;
      ids.set(element, id);
    }
    registry.set(id, element);
    const item = {id, tag};
    if (inputType) item.type = inputType;
    if (label) item.text = label;
    if (placeholder) item.placeholder = placeholder;
    if (value) item.value = value;
    if (href) item.href = href;
    if (inputType === 'checkbox' || inputType === 'radio') {
      item.checked = Boolean(element.checked);
    }
    if (element.readOnly) item.readonly = true;
    if (tag === 'select') {
      item.selected_index = element.selectedIndex;
      item.options = Array.from(element.options).slice(0, 12).map((option) => ({
        value: normalize(option.value).slice(0, 80),
        text: normalize(option.textContent).slice(0, 80)
      }));
    }
    if (element.disabled) item.disabled = true;
    return item;
  });

  let text = '';
  if (includeText && document.body) {
    if (scope === 'document') {
      text = normalize(document.body.innerText).slice(0, maxText);
    } else {
      const chunks = [];
      let total = 0;
      const walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT
      );
      let node = walker.nextNode();
      while (node && total < maxText) {
        const parent = node.parentElement;
        const value = normalize(node.textContent);
        if (parent && value && inViewport(parent)) {
          const remaining = maxText - total;
          const piece = value.slice(0, remaining);
          chunks.push(piece);
          total += piece.length + 1;
        }
        node = walker.nextNode();
      }
      text = normalize(chunks.join(' ')).slice(0, maxText);
    }
  }

  const doc = document.documentElement;
  const maxY = Math.max(0, doc.scrollHeight - window.innerHeight);
  const result = {
    ok: true,
    url: location.href,
    title: document.title || '',
    page: {
      scroll_y: Math.round(window.scrollY),
      viewport_w: window.innerWidth,
      viewport_h: window.innerHeight,
      document_h: doc.scrollHeight,
      at_top: window.scrollY <= 1,
      at_bottom: window.scrollY >= maxY - 1
    },
    elements
  };
  if (text) result.text = text;
  return JSON.stringify(result);
})();
''';
}
