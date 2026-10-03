import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'browser_guard.dart';

/// What a page asks for: `camera`, `microphone`, `location` or
/// `protected_media` (DRM video).
typedef SitePermissionKind = String;

/// Asks the user whether [host] may use [kinds]; true allows.
typedef SitePermissionPresenter =
    Future<bool> Function(String host, Set<SitePermissionKind> kinds);

/// Asks Android for the app's own runtime permissions behind [kinds]; true
/// when all are granted.
typedef RuntimePermissionRequester =
    Future<bool> Function(Set<SitePermissionKind> kinds);

/// Camera, microphone, location and protected media for pages in the
/// browser, like Chrome's site settings: the user decides once per site and
/// kind for as long as the app runs. Nothing is granted while no browser
/// page is on screen (a minimized browser, the model driving it unseen), so
/// a page can never switch on the camera behind the user's back.
class BrowserSitePermissions {
  BrowserSitePermissions({RuntimePermissionRequester? requestRuntime})
    : requestRuntime = requestRuntime ?? _requestAndroid;

  static final BrowserSitePermissions instance = BrowserSitePermissions();

  /// Replaced in tests.
  @visibleForTesting
  RuntimePermissionRequester requestRuntime;
  final Map<String, bool> _decisions = <String, bool>{};

  /// Set by the browser page the user is looking at; null otherwise.
  SitePermissionPresenter? presenter;

  /// Whether [url]'s site may use [kinds] now.
  Future<bool> decide(String? url, Set<SitePermissionKind> kinds) async {
    final host = BrowserGuard.host(url);
    if (host == null || kinds.isEmpty) return false;
    final undecided = <SitePermissionKind>{};
    for (final kind in kinds) {
      final decision = _decisions['$host|$kind'];
      if (decision == false) return false;
      if (decision == null) undecided.add(kind);
    }
    final ask = presenter;
    if (undecided.isNotEmpty) {
      if (ask == null) return false;
      final allowed = await ask(host, undecided);
      for (final kind in undecided) {
        _decisions['$host|$kind'] = allowed;
      }
      if (!allowed) return false;
    }
    // The site may; Android still has to let the app itself.
    return requestRuntime(kinds);
  }

  /// Forgets every decision, for tests.
  @visibleForTesting
  void reset() {
    _decisions.clear();
    presenter = null;
  }

  static Future<bool> _requestAndroid(Set<SitePermissionKind> kinds) async {
    final needed = <Permission>[
      if (kinds.contains('camera')) Permission.camera,
      if (kinds.contains('microphone')) Permission.microphone,
      if (kinds.contains('location')) Permission.locationWhenInUse,
    ];
    if (needed.isEmpty) return true;
    final statuses = await needed.request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }
}
