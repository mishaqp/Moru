import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_agent_session.dart';
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
        case 'close':
          return jsonEncode(await _close());
        default:
          return jsonEncode({
            'ok': false,
            'error': 'invalid_action',
            'message':
                'Use action open, observe, click, type, scroll, back, forward, reload, or close.',
          });
      }
    } on TimeoutException {
      return jsonEncode({
        'ok': false,
        'error': 'browser_timeout',
        'message': 'The shared browser did not become ready in time.',
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

  static Future<Map<String, dynamic>> _close() async {
    final session = BrowserAgentSession.instance;
    if (!session.isAttached) {
      return {
        'ok': false,
        'error': 'browser_not_open',
        'message': 'Shared browser is not open.',
      };
    }
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      throw StateError('The app navigator is not ready.');
    }
    final closed = await navigator.maybePop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return {'ok': closed, 'closed': closed};
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

  static int _intArg(Map<String, dynamic> args, String key, int fallback) {
    return _nullableIntArg(args, key) ?? fallback;
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
