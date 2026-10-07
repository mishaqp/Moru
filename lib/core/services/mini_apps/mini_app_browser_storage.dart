import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'mini_app_browser_storage_script.dart';
import 'mini_app_browser_storage_state.dart';
import 'mini_app_store.dart';

/// Transfers legacy data between two trusted empty top-level documents. App
/// startup waits for committed transactions. The source is retained unchanged
/// for retries; postMessage keeps every IndexedDB structured-clone value intact.
class MiniAppBrowserStorage {
  MiniAppBrowserStorage({
    required this.controller,
    required this.app,
    required this.origin,
    required this.nativeId,
  });

  static const channel = MethodChannel('app.miniAppOrigin');
  static const transferPath = '/.moru-storage-transfer';
  static const _javaScriptChannel = 'MoruStorageMigration';
  static const _timeout = Duration(minutes: 2);
  static final _preparations = <String, Future<void>>{};
  static final _legacyReaders = <int, MiniAppBrowserStorage>{};
  static bool _listening = false;

  final WebViewController controller;
  final MiniApp app;
  final Uri origin;
  final int nativeId;
  bool isMigrating = false;
  bool _closed = false;
  String? _expectedPage;
  String? _legacyUrl;
  String? _nonce;
  Completer<void>? _page;
  Completer<void>? _reply;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (args is! Map) return;
      final storage = _legacyReaders[args['id']];
      if (storage == null || storage._closed) return;
      if (call.method == 'legacyPageFinished' && args['url'] is String) {
        storage.pageFinished(args['url'] as String);
      } else if (call.method == 'legacyMessage' && args['message'] is String) {
        storage._message(args['message'] as String);
      }
    });
  }

  void _message(String message) {
    final Object? raw;
    try {
      raw = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (raw is! Map || raw['nonce'] != _nonce || _closed) return;
    if (raw['type'] == 'complete') {
      if (!(_reply?.isCompleted ?? true)) _reply!.complete();
    } else if (raw['type'] == 'error') {
      for (final pending in [_page, _reply]) {
        if (pending != null && !pending.isCompleted) {
          pending.completeError(StateError('Browser storage: ${raw['value']}'));
        }
      }
    }
  }

  /// Migration loads must not count as the app finishing startup.
  bool pageFinished(String url) {
    if (!isMigrating) return false;
    if (url == _expectedPage && !(_page?.isCompleted ?? true)) {
      _page!.complete();
    }
    return true;
  }

  Future<void> prepare({required Uri backend, required bool ephemeral}) async {
    // One Dart isolate owns all WebViews; serialize upgrade imports of an app
    // opened by a background job and the visible page at the same time.
    final previous = _preparations[app.directory] ?? Future<void>.value();
    final pending = previous.catchError((_) {}).then((_) async {
      _checkOpen();
      final state = ephemeral
          ? null
          : await MiniAppBrowserStorageState.read(app);
      _checkOpen();
      _legacyUrl = state?.complete == false ? state?.legacyUrl : null;
      final result = await channel.invokeMapMethod<String, dynamic>('attach', {
        'id': nativeId,
        'origin': origin.origin,
        'backend': backend.toString(),
        'legacyUrl': _legacyUrl,
        'transferPath': transferPath,
      });
      if (_closed) {
        await channel.invokeMethod<void>('detach', {'id': nativeId});
      }
      _checkOpen();
      if (state != null && !state.complete) {
        await _migrate(state, '${result?['cookies'] ?? ''}');
      } else {
        await channel.invokeMethod<void>('finishMigration', {'id': nativeId});
      }
    });
    _preparations[app.directory] = pending;
    try {
      await pending;
    } finally {
      if (identical(_preparations[app.directory], pending)) {
        _preparations.remove(app.directory);
      }
    }
  }

  Future<void> _migrate(
    MiniAppBrowserStorageState state,
    String cookies,
  ) async {
    final oldUrl = _legacyUrl;
    if (oldUrl == null || Uri.parse(oldUrl).scheme != 'file') {
      throw const FormatException('Missing legacy browser storage address.');
    }
    isMigrating = true;
    _listen();
    _legacyReaders[nativeId] = this;
    final nonce = _newNonce();
    await controller.addJavaScriptChannel(
      _javaScriptChannel,
      onMessageReceived: (message) => _message(message.message),
    );
    try {
      await _waitForPage(
        oldUrl,
        () => channel.invokeMethod<void>('loadLegacy', {'id': nativeId}),
      );
      await _waitForPage(
        origin.replace(path: transferPath).toString(),
        () => _evaluateLegacy(
          '$miniAppBrowserStorageScript\n'
          'window.__moruStorageTransfer.openPopup('
          '${jsonEncode(nonce)}, ${jsonEncode(origin.origin)});',
        ),
      );
      await controller.runJavaScript(
        '$miniAppBrowserStorageScript\n'
        'window.__moruStorageTransfer.receive('
        '${jsonEncode(nonce)}, "file://", ${jsonEncode(origin.origin)});',
      );
      await _execute(
        'window.__moruStorageTransfer.sendToPopup('
        '${jsonEncode(nonce)}, ${jsonEncode(origin.origin)}, '
        '${jsonEncode(cookies)}, '
        '${jsonEncode(Uri.directory(app.codeDirectory).toString())});',
      );
      _checkOpen();
      // Native flushes cookies and removes the legacy URL grant first. The
      // marker is committed only after the browser has finished importing.
      await channel.invokeMethod<void>('finishMigration', {'id': nativeId});
      _checkOpen();
      await state.markComplete();
    } catch (_) {
      // A failed import must also destroy the temporarily privileged reader.
      // The unchanged source and pending marker allow a new WebView to retry.
      await channel.invokeMethod<void>('detach', {'id': nativeId});
      rethrow;
    } finally {
      _nonce = null;
      _reply = null;
      _page = null;
      _expectedPage = null;
      if (identical(_legacyReaders[nativeId], this)) {
        _legacyReaders.remove(nativeId);
      }
      await controller.removeJavaScriptChannel(_javaScriptChannel);
      isMigrating = false;
    }
  }

  String _newNonce() {
    final random = Random.secure();
    return _nonce = base64Url.encode(
      List.generate(24, (_) => random.nextInt(256)),
    );
  }

  Future<void> _execute(String script) async {
    _checkOpen();
    final reply = _reply = Completer<void>();
    try {
      await Future.wait([
        reply.future.timeout(_timeout),
        _evaluateLegacy(script),
      ], eagerError: true);
    } catch (error, stack) {
      if (!reply.isCompleted) reply.completeError(error, stack);
      rethrow;
    }
  }

  Future<void> _evaluateLegacy(String script) => channel.invokeMethod<void>(
    'evaluateLegacy',
    {'id': nativeId, 'script': script},
  );

  Future<void> _waitForPage(String url, Future<void> Function() start) async {
    _checkOpen();
    _expectedPage = url;
    final page = _page = Completer<void>();
    try {
      await Future.wait([
        page.future.timeout(_timeout),
        start(),
      ], eagerError: true);
    } catch (error, stack) {
      if (!page.isCompleted) page.completeError(error, stack);
      rethrow;
    }
    _checkOpen();
  }

  void _checkOpen() {
    if (_closed) throw StateError('The mini app session is closed.');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(_legacyReaders[nativeId], this)) {
      _legacyReaders.remove(nativeId);
    }
    for (final pending in [_page, _reply]) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(StateError('The mini app session is closed.'));
      }
    }
    try {
      await controller.loadHtmlString('<!doctype html><html></html>');
    } finally {
      await channel.invokeMethod<void>('detach', {'id': nativeId});
    }
  }
}
