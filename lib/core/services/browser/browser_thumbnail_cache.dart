import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import '../../../utils/authentication_uri.dart';
import '../acp/acp_secret_redactor.dart';
import '../api/tool_display_redaction.dart';
import '../logging/log_redactor.dart';
import '../workspace/workspace_file_access.dart';

/// A reduced JPEG copied from an existing browser screenshot. The original
/// image remains available to the screenshot tool at its original resolution.
class BrowserThumbnail {
  BrowserThumbnail._({
    required this.conversationId,
    required this.stepId,
    required this.sourcePath,
    required Uint8List bytes,
    required this.width,
    required this.height,
    required this.sequence,
    required this.historical,
    required this.pageUrl,
    required this.pageKey,
    required this.capturedAt,
    required this._retentionSequence,
  }) : bytes = bytes.asUnmodifiableView();

  final String conversationId;
  final String stepId;
  final String sourcePath;
  final Uint8List bytes;
  final int width;
  final int height;

  /// Native snapshot order, reserved before disk work starts.
  final int sequence;
  final bool historical;

  /// Display-safe identity captured with the screenshot, never the live page
  /// read after asynchronous reduction finishes.
  final String? pageUrl;
  final String? pageKey;
  final DateTime? capturedAt;
  final int _retentionSequence;
}

/// Process-local, per-conversation browser previews. It only ingests existing
/// app screenshots and never captures a native WebView or reads model files.
/// Retention follows ingestion requests; latest follows native snapshot order.
/// Restoring a historical preview cannot displace the native fallback.
class BrowserThumbnailCache extends ChangeNotifier {
  BrowserThumbnailCache();

  static final BrowserThumbnailCache instance = BrowserThumbnailCache();
  static const int maxEntriesPerChat = 24;
  static const int maxWidth = 480;
  static const int maxHeight = 1440;
  static const int maxEncodedBytes = 256 * 1024;
  static const int maxChats = 8;
  static const int _maxSourceBytes = 16 * 1024 * 1024;
  static const int _maxSourcePixels = 16 * 1024 * 1024;
  static const int _maxPending = 2;
  static final _authRedactor = AcpSecretRedactor(
    const [],
    protectAuthentication: true,
  );

  final LinkedHashMap<String, _ChatThumbnails> _chats = LinkedHashMap();
  final Map<(String, String, String, bool), Future<BrowserThumbnail?>>
  _pending = {};
  int _sequence = 0;
  int _retentionSequence = 0;
  bool _disposed = false;

  /// Exact step lookup. Null conversation IDs have no shared fallback bucket.
  BrowserThumbnail? forStep(String? conversationId, String stepId) =>
      _chats[conversationId]?.entries[stepId];

  /// Match the app-private screenshot reference when the browser's activity
  /// id differs from the chat's tool-call id. Never searches another chat.
  BrowserThumbnail? forSource(String? conversationId, String? sourcePath) {
    if (conversationId == null || sourcePath == null) return null;
    final entries = _chats[conversationId]?.entries.values;
    if (entries == null) return null;
    BrowserThumbnail? found;
    for (final thumbnail in entries) {
      if (thumbnail.sourcePath == sourcePath &&
          (found == null || _newerSnapshot(thumbnail, found))) {
        found = thumbnail;
      }
    }
    return found;
  }

  /// Newest native snapshot in exactly this conversation. Passive restoration
  /// supplies a fallback only when no native snapshot has been reduced yet.
  BrowserThumbnail? latestIn(String? conversationId) =>
      _chats[conversationId]?.latest;

  /// A saved source owns its exact preview. Activity/latest snapshots may be
  /// reused only for the same public page, captured after this step started.
  /// Historical disk restoration cannot prove native capture time.
  BrowserThumbnail? previewForStep(
    String? conversationId, {
    String? sourcePath,
    String? activityId,
    String? pageUrl,
    String? pageKey,
    DateTime? startedAt,
  }) {
    final exact = forSource(conversationId, sourcePath);
    if (exact != null) return exact;
    bool matches(BrowserThumbnail? candidate) {
      if (candidate == null ||
          candidate.historical ||
          startedAt == null ||
          candidate.capturedAt == null ||
          candidate.capturedAt!.isBefore(startedAt) ||
          pageUrl == null ||
          !canPreviewPage(pageUrl)) {
        return false;
      }
      final host = Uri.tryParse(pageUrl)?.host;
      final capturedHost = Uri.tryParse(candidate.pageUrl ?? '')?.host;
      if (host == null || host.isEmpty || host != capturedHost) return false;
      return pageKey == null || candidate.pageKey == pageKey;
    }

    final activity = activityId == null
        ? null
        : forStep(conversationId, activityId);
    if (matches(activity)) return activity;
    final latest = latestIn(conversationId);
    return matches(latest) ? latest : null;
  }

  /// Reserve at native capture start, before asynchronous disk/decode work.
  /// Pass this as [captureSequence] to preserve actual snapshot chronology.
  int reserveCaptureSequence() => _sequence++;

  /// Authentication links, credential URLs and filtered addresses cannot
  /// produce previews. Null is allowed for an already-saved screenshot.
  static bool canPreviewPage(String? pageUrl) {
    if (pageUrl == null || pageUrl.isEmpty) return true;
    final uri = Uri.tryParse(pageUrl);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !isAuthenticationUri(uri) &&
        _displayText(pageUrl) == pageUrl &&
        !pageUrl.contains('[REDACTED]');
  }

  static String _displayText(String text) => LogRedactor.redactText(
    _authRedactor.text(ToolDisplayRedaction.current?.text(text) ?? text),
  );

  /// Ingests an existing screenshot through a checked open descriptor.
  /// [sourceDirectory], when supplied by the session, must be its trusted
  /// app-private screenshot directory; it is never a model-provided root.
  /// Otherwise the standard app images/browser directory is used.
  /// [historical] marks passive UI restoration: the requested entry is retained
  /// without changing an existing fallback. Native sessions may reserve a
  /// [captureSequence] before file writes, so a delayed older file stays older.
  /// [capturedAt] and [pageKey] retain the ready page's native capture identity.
  /// Historical restoration without that identity has no capture timestamp.
  /// Missing, oversized, invalid, auth-page and late-cleared images return null
  /// without replacing the last usable preview. This never modifies [sourcePath].
  Future<BrowserThumbnail?> capture({
    required String conversationId,
    required String stepId,
    required String sourcePath,
    Directory? sourceDirectory,
    String? pageUrl,
    bool historical = false,
    int? captureSequence,
    String? pageKey,
    DateTime? capturedAt,
  }) {
    if (_disposed ||
        conversationId.isEmpty ||
        stepId.isEmpty ||
        !canPreviewPage(pageUrl) ||
        _displayText(sourcePath) != sourcePath) {
      return Future.value(null);
    }
    final key = (conversationId, stepId, sourcePath, historical);
    final pending = _pending[key];
    if (pending != null) return pending;
    // Native actions are paced already. Bound even overlapping decode work.
    if (_pending.length >= _maxPending) return Future.value(null);
    final chat = _chats.remove(conversationId) ?? _ChatThumbnails();
    _chats[conversationId] = chat;
    while (_chats.length > maxChats) {
      _chats.remove(_chats.keys.first);
    }
    final sequence = captureSequence ?? reserveCaptureSequence();
    final retentionSequence = _retentionSequence++;
    final future = _capture(
      conversationId,
      stepId,
      sourcePath,
      sourceDirectory,
      chat,
      sequence,
      historical,
      pageUrl,
      pageKey,
      capturedAt ?? (historical ? null : DateTime.now()),
      retentionSequence,
    );
    _pending[key] = future;
    _removePendingWhenDone(future, key);
    return future;
  }

  void _removePendingWhenDone(
    Future<BrowserThumbnail?> future,
    (String, String, String, bool) key,
  ) {
    future.then((_) {
      if (identical(_pending[key], future)) _pending.remove(key);
    });
  }

  Future<BrowserThumbnail?> _capture(
    String conversationId,
    String stepId,
    String sourcePath,
    Directory? sourceDirectory,
    _ChatThumbnails chat,
    int sequence,
    bool historical,
    String? pageUrl,
    String? pageKey,
    DateTime? capturedAt,
    int retentionSequence,
  ) async {
    try {
      final directory =
          sourceDirectory ??
          Directory(
            p.join((await AppDirectories.getImagesDirectory()).path, 'browser'),
          );
      final access = WorkspaceFileAccess(roots: [directory.path]);
      final opened = await access.openRead(sourcePath);
      final Uint8List bytes;
      try {
        if (await opened.handle.length() > _maxSourceBytes) return null;
        bytes = await opened.readBytes(maxBytes: _maxSourceBytes);
      } finally {
        await opened.close();
      }
      final reduced = await compute(_reduceScreenshot, bytes);
      if (reduced == null ||
          _disposed ||
          !identical(_chats[conversationId], chat)) {
        return null;
      }
      final thumbnail = BrowserThumbnail._(
        conversationId: conversationId,
        stepId: stepId,
        sourcePath: sourcePath,
        bytes: reduced.$1,
        width: reduced.$2,
        height: reduced.$3,
        sequence: sequence,
        historical: historical,
        pageUrl: pageUrl,
        pageKey: pageKey,
        capturedAt: capturedAt,
        retentionSequence: retentionSequence,
      );
      final previous = chat.entries[stepId];
      if (previous != null && !_newerSnapshot(thumbnail, previous)) {
        return previous;
      }
      chat.entries[stepId] = thumbnail;
      final latest = chat.latest;
      if (latest == null ||
          identical(latest, previous) ||
          (!historical && _newerSnapshot(thumbnail, latest))) {
        chat.latest = thumbnail;
      }
      while (chat.entries.length > maxEntriesPerChat) {
        // Keep the fallback while requested historical images turn over.
        final oldest = chat.entries.values
            .where((entry) => !identical(entry, chat.latest))
            .reduce(
              (a, b) => a._retentionSequence < b._retentionSequence ? a : b,
            );
        chat.entries.remove(oldest.stepId);
      }
      notifyListeners();
      return thumbnail;
    } on Object {
      // Preview failure must never change a tool's original result.
      return null;
    }
  }

  /// Drops this chat and invalidates any reduction still in flight for it.
  void clearConversation(String conversationId) {
    if (_disposed) return;
    if (_chats.remove(conversationId) != null) notifyListeners();
  }

  void clear() {
    if (_disposed || _chats.isEmpty) return;
    _chats.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _chats.clear();
    super.dispose();
  }
}

class _ChatThumbnails {
  final Map<String, BrowserThumbnail> entries = {};
  BrowserThumbnail? latest;
}

bool _newerSnapshot(BrowserThumbnail candidate, BrowserThumbnail previous) =>
    candidate.historical != previous.historical
    ? previous.historical
    : candidate.sequence > previous.sequence;

(Uint8List, int, int)? _reduceScreenshot(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > BrowserThumbnailCache._maxSourcePixels) {
      return null;
    }
    final original = decoder!.decodeFrame(0);
    if (original == null) return null;
    final scale = math.min(
      1.0,
      math.min(
        BrowserThumbnailCache.maxWidth / original.width,
        BrowserThumbnailCache.maxHeight / original.height,
      ),
    );
    final thumbnail = scale == 1.0
        ? original
        : img.copyResize(
            original,
            width: math.max(1, (original.width * scale).round()),
            height: math.max(1, (original.height * scale).round()),
            interpolation: img.Interpolation.average,
          );
    final encoded = img.encodeJpg(thumbnail, quality: 72);
    if (encoded.length > BrowserThumbnailCache.maxEncodedBytes) return null;
    return (encoded, thumbnail.width, thumbnail.height);
  } on Object {
    return null;
  }
}
