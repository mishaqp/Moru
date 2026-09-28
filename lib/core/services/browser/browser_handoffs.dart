import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// A file a page downloaded (or failed to).
@immutable
class BrowserDownload {
  const BrowserDownload({
    required this.file,
    required this.url,
    this.path,
    this.error,
  });

  factory BrowserDownload.fromMap(Map<Object?, Object?> map) => BrowserDownload(
    file: map['file'] as String? ?? 'download',
    url: map['url'] as String? ?? '',
    path: map['path'] as String?,
    error: map['error'] as String?,
  );

  final String file;
  final String url;

  /// Where the system download manager saves it (in Downloads).
  final String? path;

  /// Why it did not start: `unsupported_scheme` for files a page makes
  /// itself (`blob:`, `data:`), otherwise the system's message.
  final String? error;

  Map<String, Object?> toJson() => {
    'file': file,
    if (path != null) 'path': path,
    if (error != null) 'error': error,
    if (error == null) 'status': 'downloading',
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

  /// Sends the downloads of [controller]'s pages to the download manager.
  Future<void> watchDownloads(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return;
    if (!_handling) {
      _handling = true;
      _channel.setMethodCallHandler(handleNativeCall);
    }
    try {
      await _channel.invokeMethod<bool>('watchDownloads', {
        'id': platform.webViewIdentifier,
      });
    } on MissingPluginException {
      // Not on the phone (tests).
    }
  }

  @visibleForTesting
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method != 'download') return;
    final args = call.arguments;
    if (args is! Map) return;
    final download = BrowserDownload.fromMap(args);
    latestDownload.value = download;
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

  /// Downloads and app links since the last call, once each, for the next
  /// tool result.
  List<Map<String, Object?>> drainForModel() {
    final events = List<Map<String, Object?>>.of(_forModel);
    _forModel.clear();
    return events;
  }
}
