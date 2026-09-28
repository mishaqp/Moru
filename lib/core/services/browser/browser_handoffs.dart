import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'browser_agent_session.dart';

/// A file a page downloaded (or failed to).
@immutable
class BrowserDownload {
  const BrowserDownload({
    required this.file,
    required this.url,
    this.path,
    this.error,
    this.status = 'downloading',
  });

  factory BrowserDownload.fromMap(Map<Object?, Object?> map) => BrowserDownload(
    file: map['file'] as String? ?? 'download',
    url: map['url'] as String? ?? '',
    path: map['path'] as String?,
    error: map['error'] as String?,
    status: map['status'] as String? ?? 'downloading',
  );

  final String file;
  final String url;

  /// Where the file ended up in Downloads, once it is `done`: the download
  /// manager adds `-1` to a name that is taken.
  final String? path;

  /// Why it did not start: `unsupported_scheme` for files a page makes
  /// itself (`blob:`, `data:`), otherwise the system's message.
  final String? error;

  /// `downloading`, `done` or `failed`.
  final String status;

  Map<String, Object?> toJson() => {
    'file': file,
    if (path case final String saved) ...{
      'path': saved,
      // The Linux terminal sees the Downloads folder at /downloads.
      'terminal_path': '/downloads/${saved.split('/').last}',
    },
    if (error != null) 'error': error,
    if (error == null) 'status': status,
  };
}

/// What leaves a browser page for the rest of the phone: downloads, which
/// the system download manager saves to Downloads, and links that belong to
/// other apps (`intent:`, `tel:`, `mailto:`, `market:` ...).
class BrowserHandoffs {
  BrowserHandoffs._();

  static final BrowserHandoffs instance = BrowserHandoffs._();

  static const MethodChannel _channel = MethodChannel('app.browser');

  static const Set<String> _webSchemes = {
    'http',
    'https',
    'about',
    'data',
    'blob',
    'javascript',
    'file',
    'content',
  };

  /// The newest download, for the page's message.
  final ValueNotifier<BrowserDownload?> latestDownload =
      ValueNotifier<BrowserDownload?>(null);

  final List<Map<String, Object?>> _forModel = [];
  bool _handling = false;

  /// Whether [url] is a link for another app rather than a web page.
  static bool isAppLink(String? url) {
    final scheme = Uri.tryParse(url?.trim() ?? '')?.scheme.toLowerCase();
    return scheme != null && scheme.isNotEmpty && !_webSchemes.contains(scheme);
  }

  /// The native WebView id of [controller], null off Android. Replaced in
  /// tests.
  @visibleForTesting
  int? Function(WebViewController controller) webViewId = (controller) {
    final platform = controller.platform;
    return platform is AndroidWebViewController
        ? platform.webViewIdentifier
        : null;
  };

  /// Sets [delegate] on [controller] and then sends its pages' downloads to
  /// the download manager. Always use this instead of
  /// `setNavigationDelegate`: the plugin installs its own download listener
  /// with every delegate, which would silently replace ours.
  Future<void> setNavigationDelegate(
    WebViewController controller,
    NavigationDelegate delegate,
  ) async {
    await controller.setNavigationDelegate(delegate);
    await _watchDownloads(controller);
  }

  Future<void> _watchDownloads(WebViewController controller) async {
    final id = webViewId(controller);
    if (id == null) return;
    if (!_handling) {
      _handling = true;
      _channel.setMethodCallHandler(handleNativeCall);
    }
    try {
      await _channel.invokeMethod<bool>('watchDownloads', {'id': id});
    } on MissingPluginException {
      // Not on the phone (tests).
    }
  }

  @visibleForTesting
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method != 'download' && call.method != 'downloadFinished') {
      return;
    }
    final args = call.arguments;
    if (args is! Map) return;
    final download = BrowserDownload.fromMap(args);
    latestDownload.value = download;
    if (call.method == 'download') {
      BrowserAgentSession.instance.downloadStarted(download.url);
    }
    _forModel.add({'kind': 'download', ...download.toJson()});
  }

  /// Opens an app link in its app. When no app takes it, the link's web
  /// fallback (an `intent:` link's `browser_fallback_url`) is returned for
  /// the page to load instead.
  Future<({bool opened, String? fallback})> openAppLink(String url) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'openExternal',
        {'url': url},
      );
      return (
        opened: result?['opened'] == true,
        fallback: result?['fallback'] as String?,
      );
    } on MissingPluginException {
      return (opened: false, fallback: null);
    } on PlatformException {
      return (opened: false, fallback: null);
    }
  }

  /// An app link the page tried while the model drove it: not opened, so
  /// the model can tell the user.
  void noteBlockedAppLink(String url) {
    _forModel.add({
      'kind': 'app_link',
      'url': url.length > 300 ? url.substring(0, 300) : url,
      'status': 'not_opened_while_assistant_works',
    });
  }

  /// A page whose certificate is not valid was not opened; the model is
  /// told why.
  void noteSslError(String host, String problem) {
    _forModel.add({
      'kind': 'ssl_error',
      'site': host,
      'problem': problem,
      'status': 'not_opened',
      'next':
          'The connection is not secure. Do not work around it; tell the '
          'user, who can open the site themselves and decide.',
    });
  }

  /// Downloads and app links since the last call, once each, for the next
  /// tool result.
  List<Map<String, Object?>> drainForModel() {
    final events = List<Map<String, Object?>>.of(_forModel);
    _forModel.clear();
    return events;
  }
}
