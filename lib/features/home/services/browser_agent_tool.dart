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
    try {
      switch (action) {
        case 'open':
          return jsonEncode(await _open((args['url'] ?? '').toString()));
        case 'observe':
          return jsonEncode(await BrowserAgentSession.instance.observe());
        case 'click':
          return jsonEncode(
            await BrowserAgentSession.instance.click(_elementId(args)),
          );
        case 'type':
          return jsonEncode(
            await BrowserAgentSession.instance.type(
              _elementId(args),
              (args['text'] ?? '').toString(),
            ),
          );
        default:
          return jsonEncode({
            'ok': false,
            'error': 'invalid_action',
            'message': 'Use action open, observe, click, or type.',
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
    final raw = args['element_id'];
    final id = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    if (id == null || id < 1) {
      throw ArgumentError(
        'element_id must be a positive integer from observe.',
      );
    }
    return id;
  }
}
