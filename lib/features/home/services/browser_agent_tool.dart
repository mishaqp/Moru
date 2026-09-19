import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_research.dart';
import '../../../core/services/browser/web_source.dart';
import '../../../shared/pages/webview_page.dart';
import '../../../shared/widgets/snackbar.dart';

/// Local-tool adapter for the visible shared browser.
class BrowserAgentTool {
  const BrowserAgentTool._();

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<String> execute(Map<String, dynamic> args) async {
    if (!supported) {
      return jsonEncode({
        'ok': false,
        'error': 'unsupported_platform',
        'message': 'Shared Browser is available on Android only.',
      });
    }

    final action = (args['action'] ?? '').toString().trim().toLowerCase();
    final session = BrowserAgentSession.instance;
    try {
      switch (action) {
        case 'open':
          return jsonEncode(await _open((args['url'] ?? '').toString()));
        case 'observe':
          return jsonEncode(
            await session.observe(
              scope: (args['scope'] ?? 'viewport').toString().toLowerCase(),
              maxTextChars: _intArg(args, 'max_text_chars', 3000),
              maxElements: _intArg(args, 'max_elements', 36),
              includeText: _boolArg(args, 'include_text', true),
            ),
          );
        case 'click':
          return jsonEncode(await session.click(_elementId(args)));
        case 'type':
          return jsonEncode(
            await session.type(
              _elementId(args),
              (args['text'] ?? '').toString(),
            ),
          );
        case 'scroll':
          return jsonEncode(
            await session.scroll(
              direction: (args['direction'] ?? 'down')
                  .toString()
                  .trim()
                  .toLowerCase(),
              amount: _nullableIntArg(args, 'amount'),
            ),
          );
        case 'back':
          return jsonEncode(await session.goBack());
        case 'forward':
          return jsonEncode(await session.goForward());
        case 'reload':
          return jsonEncode(await session.reload());
        case 'read':
          return jsonEncode(await _read(args));
        case 'wait_for':
          return jsonEncode(
            await session.waitFor(
              selector: _selector(args),
              state: (args['state'] ?? 'attached')
                  .toString()
                  .trim()
                  .toLowerCase(),
              containsText: _stringArg(args, 'contains_text'),
              timeoutMs: _intArg(args, 'timeout_ms', 10000),
            ),
          );
        case 'close':
          return jsonEncode(await _close());
        default:
          return jsonEncode({
            'ok': false,
            'error': 'invalid_action',
            'message':
                'Use action open, observe, click, type, scroll, back, forward, reload, read, wait_for, or close.',
          });
      }
    } on TimeoutException {
      return jsonEncode({
        'ok': false,
        'error': 'browser_timeout',
        'message': 'The shared browser did not become ready in time.',
      });
    } on BrowserAgentProtocolException catch (error) {
      return jsonEncode({
        'ok': false,
        'error': 'browser_protocol_error',
        'message': error.message,
      });
    } on StateError catch (error) {
      return jsonEncode({
        'ok': false,
        'error': 'browser_not_open',
        'message': error.message,
      });
    } on ArgumentError catch (error) {
      return jsonEncode({
        'ok': false,
        'error': 'invalid_arguments',
        'message': error.message,
      });
    }
  }

  static Future<Map<String, dynamic>> _close() {
    return BrowserAgentSession.instance.close();
  }

  /// Reads the current page, or reuses a page already read this session via `source_id` -
  /// no network, no re-render. Both paths go through [_normalizeReadResult] so `read` reports
  /// `ok` like every other `browser_use` action, even though the ported research envelopes
  /// (kept identical to RikkaHub's) signal failure by an `error` key instead.
  static Future<Map<String, dynamic>> _read(Map<String, dynamic> args) async {
    final sourceId = _stringArg(args, 'source_id');
    if (sourceId != null) {
      return _normalizeReadResult(_readCachedSource(sourceId, args));
    }
    final result = await runBrowserRead(
      args: args,
      reader: BrowserAgentSession.instance.read,
      timeoutMs: const Duration(seconds: 20).inMilliseconds,
      notOpen: () => const {
        'error': 'browser_not_open',
        'message': 'Shared browser is not open.',
      },
    );
    return _normalizeReadResult(result);
  }

  static Map<String, dynamic> _readCachedSource(
    String sourceId,
    Map<String, dynamic> args,
  ) {
    final cached = browserSourceCache.get(sourceId);
    if (cached == null) return unknownSourceEnvelope(sourceId);
    final maxChars = _intArg(
      args,
      'max_chars',
      browserReadDefaultMaxChars,
    ).clamp(browserReadMinChars, browserReadMaxChars);
    return cachedSourceEnvelope(
      source: cached,
      maxChars: maxChars,
      focus: _stringArg(args, 'focus'),
      startIndex: _nullableIntArg(args, 'start_index'),
    );
  }

  /// The research envelopes (ported as-is from RikkaHub) signal failure with an `error` key
  /// and carry no `ok` field. Every other `browser_use` action always returns `ok`, so this
  /// normalizes `read`'s result to the same contract without touching the ported envelopes.
  static Map<String, dynamic> _normalizeReadResult(
    Map<String, dynamic> result,
  ) {
    return {'ok': !result.containsKey('error'), ...result};
  }

  static Future<Map<String, dynamic>> _open(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Shared Browser only accepts http or https URLs.');
    }

    final session = BrowserAgentSession.instance;
    if (session.isAttached) {
      await session.load(uri);
      return {'ok': true, 'url': uri.toString(), 'reused': true};
    }

    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      throw StateError('The app navigator is not ready.');
    }

    session.expectNavigation();
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WebViewPage(url: uri.toString(), agentSession: true),
        ),
      ),
    );
    await session.waitUntilAttached();
    await session.waitUntilReady();
    await session.recordInitialPage();
    return {'ok': true, 'url': uri.toString(), 'reused': false};
  }

  static int _elementId(Map<String, dynamic> args) {
    final id = _nullableIntArg(args, 'element_id');
    if (id == null || id < 1) {
      throw ArgumentError(
        'element_id must be a positive integer from observe.',
      );
    }
    return id;
  }

  static String _selector(Map<String, dynamic> args) {
    final selector = _stringArg(args, 'selector');
    if (selector == null) {
      throw ArgumentError('selector is required for action=wait_for.');
    }
    return selector;
  }

  static int _intArg(Map<String, dynamic> args, String key, int fallback) {
    return _nullableIntArg(args, key) ?? fallback;
  }

  static String? _stringArg(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _nullableIntArg(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  static bool _boolArg(Map<String, dynamic> args, String key, bool fallback) {
    final raw = args[key];
    if (raw == null) return fallback;
    if (raw is bool) return raw;
    final normalized = raw.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return fallback;
  }
}
