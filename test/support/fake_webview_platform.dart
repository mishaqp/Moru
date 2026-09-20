import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Minimal, test-only [WebViewPlatform] good enough to drive a real
/// [WebViewController]/[WebViewWidget] inside `flutter_test`, where no actual
/// native platform view exists.
///
/// Install once (e.g. in `setUpAll`) via [installFakeWebViewPlatform]. Every
/// [WebViewController] constructed afterwards is backed by a
/// [FakeWebViewController] with its own tiny linear "native history", so
/// `loadRequest`/`goBack`/`goForward`/`reload` all fire realistic
/// `onPageStarted`/`onPageFinished` pairs the same way a real WebView would —
/// which lets tests exercise [BrowserAgentSession]'s navigation reconciliation
/// and `webview_page.dart`'s lifecycle without a device or emulator.
class FakeWebViewPlatform extends WebViewPlatform {
  /// The most recently created controller -- lets a test reach the fake
  /// controller behind a `WebViewController` it did not construct itself
  /// (e.g. one built inside a private `State`), as long as nothing else
  /// creates a `WebViewController` in between.
  static FakeWebViewController? lastCreated;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);
    lastCreated = controller;
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebViewWidget(params);
}

/// Sets [WebViewPlatform.instance] to a fresh [FakeWebViewPlatform]. Safe to
/// call more than once (e.g. once per test) since a new instance is always
/// installed.
void installFakeWebViewPlatform() {
  WebViewPlatform.instance = FakeWebViewPlatform();
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;
  ProgressCallback? onProgress;
  NavigationRequestCallback? onNavigationRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    this.onProgress = onProgress;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }
}

/// One queued navigation, used only when [FakeWebViewController.autoFinish]
/// is false so a test can control exactly when `onPageStarted`/
/// `onPageFinished` fire (e.g. to simulate a slow load racing something
/// else).
class PendingFakeNavigation {
  PendingFakeNavigation(this.url);
  final String url;
  bool started = false;
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  FakeNavigationDelegate? _delegate;
  final List<String> _history = <String>[];
  int _index = -1;
  final Map<String, void Function(JavaScriptMessage)> _channels =
      <String, void Function(JavaScriptMessage)>{};

  /// When true (the default), every navigating call fires
  /// `onPageStarted`+`onPageFinished` synchronously. Set to false to control
  /// timing manually through [pending] and [finishNext].
  bool autoFinish = true;
  final List<PendingFakeNavigation> pending = <PendingFakeNavigation>[];

  /// Returns a canned result for `runJavaScriptReturningResult` (e.g. for
  /// `document.title`). Defaults to an empty JSON string.
  Object Function(String script)? jsHandler;

  /// Preferred over [jsHandler] when set -- lets a test control exactly
  /// when `runJavaScriptReturningResult` resolves (e.g. to simulate a slow
  /// title fetch racing a new navigation).
  Future<Object> Function(String script)? jsHandlerAsync;

  String? get currentUrlSync => _index >= 0 ? _history[_index] : null;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _delegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    _channels[javaScriptChannelParams.name] =
        javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    _channels.remove(javaScriptChannelName);
  }

  /// Delivers [message] on [channelName] as if the page's own JS had called
  /// `<channelName>.postMessage(message)`.
  void emitChannelMessage(String channelName, String message) {
    _channels[channelName]?.call(JavaScriptMessage(message: message));
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    _navigateTo(params.uri.toString());
  }

  /// The most recent HTML string passed to [loadHtmlString].
  String? lastLoadedHtml;

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    lastLoadedHtml = html;
    _navigateTo(baseUrl ?? 'about:blank');
  }

  void _navigateTo(String url) {
    if (currentUrlSync != url) {
      if (_index < _history.length - 1) {
        _history.removeRange(_index + 1, _history.length);
      }
      _history.add(url);
      _index = _history.length - 1;
    }
    _fireNavigation(url);
  }

  void _fireNavigation(String url) {
    if (autoFinish) {
      _delegate?.onPageStarted?.call(url);
      _delegate?.onPageFinished?.call(url);
    } else {
      pending.add(PendingFakeNavigation(url));
    }
  }

  /// Fires `onPageStarted` for the oldest not-yet-started pending navigation
  /// (see [autoFinish]).
  void startNext() {
    final next = pending.firstWhere(
      (p) => !p.started,
      orElse: () => throw StateError('No pending navigation to start.'),
    );
    next.started = true;
    _delegate?.onPageStarted?.call(next.url);
  }

  /// Fires `onPageFinished` for the oldest started-and-unfinished pending
  /// navigation and removes it from the queue (see [autoFinish]).
  void finishNext() {
    final next = pending.firstWhere(
      (p) => p.started,
      orElse: () => throw StateError('No started navigation to finish.'),
    );
    pending.remove(next);
    _delegate?.onPageFinished?.call(next.url);
  }

  /// Fires a full started+finished pair for [url] directly, regardless of
  /// [autoFinish] — used to simulate an out-of-band navigation (e.g. a
  /// redirect) without going through [loadRequest].
  void simulateCommittedNavigation(String url) {
    if (currentUrlSync != url) {
      if (_index < _history.length - 1) {
        _history.removeRange(_index + 1, _history.length);
      }
      _history.add(url);
      _index = _history.length - 1;
    }
    _delegate?.onPageStarted?.call(url);
    _delegate?.onPageFinished?.call(url);
  }

  void simulateWebResourceError(WebResourceError error) {
    _delegate?.onWebResourceError?.call(error);
  }

  @override
  Future<bool> canGoBack() async => _index > 0;

  @override
  Future<bool> canGoForward() async =>
      _index >= 0 && _index < _history.length - 1;

  @override
  Future<void> goBack() async {
    if (_index <= 0) return;
    _index--;
    _fireNavigation(_history[_index]);
  }

  @override
  Future<void> goForward() async {
    if (_index < 0 || _index >= _history.length - 1) return;
    _index++;
    _fireNavigation(_history[_index]);
  }

  /// Incremented on every [reload] call.
  int reloadCount = 0;

  @override
  Future<void> reload() async {
    reloadCount++;
    final url = currentUrlSync;
    if (url != null) _fireNavigation(url);
  }

  @override
  Future<String?> currentUrl() async => currentUrlSync;

  @override
  Future<void> runJavaScript(String javaScript) async {
    jsHandler?.call(javaScript);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final asyncHandler = jsHandlerAsync;
    if (asyncHandler != null) return asyncHandler(javaScript);
    final handler = jsHandler;
    if (handler != null) return handler(javaScript);
    return '""';
  }
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
