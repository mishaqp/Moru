import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'browser_agent_session.dart' show BrowserNavigationHistory;

/// One page of the shared browser. Only the active tab is on screen; the
/// others keep their WebView (and its scripts) alive in the background.
class BrowserTab {
  BrowserTab({
    required this.id,
    required this.controller,
    required this.byAgent,
    required this.lastUsed,
  });

  final String id;
  final WebViewController controller;

  /// Opened by the model; closed after a while unused (see
  /// [BrowserAgentSession.agentTabIdle]).
  final bool byAgent;

  DateTime lastUsed;
  String? url;
  String? title;
  bool loading = false;

  /// Shows sites as on a computer (see [desktopUserAgent]).
  bool desktop = false;

  /// The WebView's own user agent, kept to go back from desktop mode.
  String? mobileUserAgent;

  final BrowserNavigationHistory history = BrowserNavigationHistory();

  BrowserTabInfo info({required bool active}) => BrowserTabInfo(
    id: id,
    url: url,
    title: title,
    active: active,
    byAgent: byAgent,
    desktop: desktop,
    loading: loading,
  );
}

/// What the tab list and the model see of a [BrowserTab].
@immutable
class BrowserTabInfo {
  const BrowserTabInfo({
    required this.id,
    required this.url,
    required this.title,
    required this.active,
    required this.byAgent,
    required this.desktop,
    required this.loading,
  });

  final String id;
  final String? url;
  final String? title;
  final bool active;
  final bool byAgent;
  final bool desktop;
  final bool loading;

  Map<String, Object?> toJson() => {
    'tab_id': id,
    if (url != null) 'url': url,
    if (title != null && title!.isNotEmpty) 'title': title,
    'active': active,
    if (byAgent) 'opened_by': 'assistant',
    if (desktop) 'mode': 'desktop',
  };

  @override
  bool operator ==(Object other) =>
      other is BrowserTabInfo &&
      other.id == id &&
      other.url == url &&
      other.title == title &&
      other.active == active &&
      other.byAgent == byAgent &&
      other.desktop == desktop &&
      other.loading == loading;

  @override
  int get hashCode =>
      Object.hash(id, url, title, active, byAgent, desktop, loading);
}

/// The user agent of desktop Chrome on Linux with the same Chrome version
/// as [mobile] (the WebView's own), so sites serve their computer version.
String desktopUserAgent(String? mobile) {
  final version =
      RegExp(r'Chrome/([\d.]+)').firstMatch(mobile ?? '')?.group(1) ??
      '130.0.0.0';
  return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/$version Safari/537.36';
}
