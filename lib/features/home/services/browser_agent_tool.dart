import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_handoffs.dart';
import '../../../core/services/browser/browser_guard.dart';
import '../../../core/services/browser/browser_research.dart';
import 'browser_agent_actions.dart';
import '../../../core/services/browser/web_source.dart';
import '../../../shared/pages/webview/webview_page.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/mcp_structured_image.dart';

/// Local-tool adapter for the visible shared browser.
class BrowserAgentTool {
  const BrowserAgentTool._();

  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  static Future<String> execute(
    Map<String, dynamic> args, {
    String? conversationId,
  }) async {
    if (!supported) {
      return jsonEncode({
        'ok': false,
        'error': 'unsupported_platform',
        'message': 'Shared Browser is available on Android only.',
      });
    }

    final action = (args['action'] ?? '').toString().trim().toLowerCase();
    final session = BrowserAgentSession.instance;
    // Refreshed on every call (not just 'open') so the approval prompt always
    // matches whichever conversation is currently driving this session, even
    // if the browser was opened by one conversation and is being scripted by
    // another that reused it (the session is a single shared instance).
    session.setOwnerConversationId(conversationId);
    // Recorded up front (not inside each case of `_dispatch`) so every known
    // action gets exactly one activity id, resolved below against that same
    // id rather than "whichever one is last" once the call returns.
    // An unrecognized action never gets an activity at all — there is
    // nothing of its own to show or resolve.
    final activityId = BrowserAgentActions.isKnown(action)
        ? session.recordActivity(
            action: action,
            detail: _activityDetail(action, args),
          )
        : null;
    session.beginAction();
    String result;
    try {
      result = await _guarded(action, args, session);
    } finally {
      session.endAction();
    }
    if (activityId != null) {
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final ok = decoded['ok'] == true;
      final outcome = ok && action == 'wait_for' && decoded['found'] == false
          ? BrowserActivityOutcome.notFound
          : (ok ? BrowserActivityOutcome.ok : BrowserActivityOutcome.failed);
      session.resolveActivity(activityId, outcome);
    }
    return result;
  }

  /// A short, safe-to-log extra for the activity entry — best-effort only,
  /// so a malformed argument here must never throw before the action's own
  /// (much stricter) argument validation gets a chance to report a proper
  /// error to the model.
  static String? _activityDetail(String action, Map<String, dynamic> args) {
    switch (action) {
      case 'open':
      case 'new_tab':
        return _stringArg(args, 'url');
      case 'switch_tab':
      case 'close_tab':
        return _stringArg(args, 'tab_id');
      case 'set_mode':
        return _stringArg(args, 'mode');
      case 'press_key':
        return _stringArg(args, 'key');
      case 'scroll':
        return _stringArg(args, 'direction');
      case 'wait_for':
        return _stringArg(args, 'selector');
      case 'done':
        return _stringArg(args, 'summary');
      default:
        return null;
    }
  }

  /// Actions after which the page may be a different one.
  static const Set<String> _navigating = {
    'open',
    'new_tab',
    'switch_tab',
    'set_mode',
    'back',
    'forward',
    'reload',
    'click',
    'submit',
    'press_key',
  };

  /// [_dispatch] with the guard around it: a blocking verification page
  /// refuses interaction, actions are paced per site, and the result says
  /// which check the page shows and which dialogs were answered.
  static Future<String> _guarded(
    String action,
    Map<String, dynamic> args,
    BrowserAgentSession session,
  ) async {
    try {
      if (BrowserGuard.blockedByChallenge.contains(action) &&
          session.isAttached &&
          session.challenge.value?.blocking == true &&
          (await session.checkChallenge())?.blocking == true) {
        return jsonEncode({
          'ok': false,
          'error': 'challenge_detected',
          'message':
              'The page is a verification check. Ask the user to complete it '
              'in the browser, then observe again.',
          'challenge': session.challenge.value!.toJson(),
        });
      }
      if (session.isAttached || action == 'open') {
        await session.pace(
          action,
          url: action == 'open' || action == 'new_tab'
              ? _stringArg(args, 'url')
              : null,
        );
      }
      final raw = await _dispatch(action, args, session);
      if (!session.isAttached) return raw;
      final result = jsonDecode(raw) as Map<String, dynamic>;
      if (_navigating.contains(action) || action == 'observe') {
        final found = await session.checkChallenge();
        if (found != null) result['challenge'] = found.toJson();
      }
      final dialogs = session.drainDialogs();
      if (dialogs.isNotEmpty) result['dialogs'] = dialogs;
      // Downloads and app links arrive after the click that started them,
      // so they ride on this result or the next one.
      final handoffs = BrowserHandoffs.instance.drainForModel();
      if (handoffs.isNotEmpty) result['handoffs'] = handoffs;
      // `screenshot: true` on any action: the page as it looks afterwards.
      if (action != 'screenshot' &&
          _boolArg(args, 'screenshot', false) &&
          result['ok'] == true) {
        final shot = await session.screenshot();
        if (shot['ok'] == true) result['screenshot'] = shot['screenshot'];
        if (shot['viewport'] != null) result['viewport'] = shot['viewport'];
      }
      return jsonEncode(result);
    } on BrowserStoppedException {
      return jsonEncode({
        'ok': false,
        'error': 'stopped_by_user',
        'message': 'The user stopped this browser action.',
      });
    }
  }

  static Future<String> _dispatch(
    String action,
    Map<String, dynamic> args,
    BrowserAgentSession session,
  ) async {
    try {
      switch (action) {
        case 'open':
          final url = (args['url'] ?? '').toString();
          return jsonEncode(await _open(url));
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
          final point = _point(args);
          if (point != null && _nullableIntArg(args, 'element_id') == null) {
            return jsonEncode(await session.clickAt(point.x, point.y));
          }
          final elementId = _elementId(args);
          if (_boolArg(args, 'trusted', false)) {
            // A real tap on the element's center, for pages that ignore
            // script clicks.
            final center = await session.elementCenter(elementId);
            if (center['ok'] != true) return jsonEncode(center);
            final tapped = await session.clickAt(
              center['x'] as num,
              center['y'] as num,
            );
            return jsonEncode({...tapped, 'element_id': elementId});
          }
          return jsonEncode(await session.click(elementId));
        case 'hover':
          final at = _point(args);
          final id = _nullableIntArg(args, 'element_id');
          if (at == null && id == null) {
            throw ArgumentError('hover needs element_id or x and y.');
          }
          return jsonEncode(
            await session.hover(elementId: id, x: at?.x, y: at?.y),
          );
        case 'type':
          final text = (args['text'] ?? '').toString();
          return jsonEncode(
            _boolArg(args, 'human', false)
                ? await session.typeLikeHuman(_elementId(args), text)
                : await session.type(_elementId(args), text),
          );
        case 'collect':
          return jsonEncode(
            await session.collect(
              selector: _stringArg(args, 'selector'),
              maxItems: _intArg(args, 'max_items', 50),
              maxScrolls: _intArg(args, 'max_scrolls', 10),
            ),
          );
        case 'outline':
          return jsonEncode(await session.outline());
        case 'wait_stable':
          return jsonEncode(
            await session.waitStable(
              quietMs: _intArg(args, 'quiet_ms', 600),
              timeoutMs: _intArg(args, 'timeout_ms', 10000),
            ),
          );
        case 'submit':
          return jsonEncode(await session.submit(_elementId(args)));
        case 'press_key':
          return jsonEncode(await session.pressKey(_key(args)));
        case 'scroll':
          final direction = (args['direction'] ?? 'down')
              .toString()
              .trim()
              .toLowerCase();
          return jsonEncode(
            await session.scroll(
              direction: direction,
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
          final selector = _selector(args);
          return jsonEncode(
            await session.waitFor(
              selector: selector,
              state: (args['state'] ?? 'attached')
                  .toString()
                  .trim()
                  .toLowerCase(),
              containsText: _stringArg(args, 'contains_text'),
              timeoutMs: _intArg(args, 'timeout_ms', 10000),
            ),
          );
        case 'screenshot':
          return jsonEncode(await session.screenshot());
        case 'eval_js':
          return jsonEncode(await _evalJs(args));
        case 'tabs':
          return jsonEncode(session.listTabs());
        case 'new_tab':
          final url = _stringArg(args, 'url');
          if (url != null) {
            final uri = Uri.tryParse(url);
            if (uri == null ||
                !(uri.isScheme('http') || uri.isScheme('https'))) {
              return jsonEncode({
                'ok': false,
                'error': 'invalid_url',
                'message': 'new_tab only opens http or https URLs.',
              });
            }
          }
          return jsonEncode(await session.newTab(url: url, byAgent: true));
        case 'switch_tab':
        case 'close_tab':
          final tabId = _stringArg(args, 'tab_id');
          if (tabId == null && action == 'switch_tab') {
            return jsonEncode({
              'ok': false,
              'error': 'missing_tab_id',
              'message': 'switch_tab needs tab_id from action=tabs.',
            });
          }
          if (action == 'switch_tab') {
            return jsonEncode(await session.switchTab(tabId!));
          }
          final active = [
            for (final tab in session.tabs.value)
              if (tab.active) tab.id,
          ];
          final target = tabId ?? (active.isEmpty ? null : active.first);
          if (target == null) {
            return jsonEncode({
              'ok': false,
              'error': 'browser_not_open',
              'message': 'Shared browser is not open.',
            });
          }
          return jsonEncode(await session.closeTab(target));
        case 'set_mode':
          final mode = _stringArg(args, 'mode');
          if (mode != 'desktop' && mode != 'mobile') {
            return jsonEncode({
              'ok': false,
              'error': 'invalid_mode',
              'message': 'mode is desktop or mobile.',
            });
          }
          return jsonEncode(await session.setDesktopMode(mode == 'desktop'));
        case 'fetch':
          final url = _stringArg(args, 'url');
          if (url == null) {
            return jsonEncode({
              'ok': false,
              'error': 'missing_url',
              'message': 'fetch needs url.',
            });
          }
          final rawHeaders = args['headers'];
          return jsonEncode(
            await session.fetchInPage(
              url: url,
              method: _stringArg(args, 'method') ?? 'GET',
              body: _stringArg(args, 'body'),
              headers: {
                if (rawHeaders is Map)
                  for (final entry in rawHeaders.entries)
                    '${entry.key}': '${entry.value}',
              },
              maxChars: _intArg(args, 'max_chars', 20000),
            ),
          );
        case 'close':
          return jsonEncode(await _close());
        case 'done':
          final summary = _stringArg(args, 'summary');
          return jsonEncode({
            'ok': true,
            'action': 'done',
            if (summary != null) 'summary': summary,
          });
        default:
          return jsonEncode({
            'ok': false,
            'error': 'invalid_action',
            'message':
                'Use action open, observe, screenshot, click, hover, type, submit, press_key, scroll, back, forward, reload, read, collect, outline, wait_for, wait_stable, eval_js, fetch, export_cookies, tabs, new_tab, switch_tab, close_tab, set_mode, done, or close.',
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

  /// The result as the model gets it: a screenshot path becomes an image
  /// attached to the tool result (shown in the chat, and sent to models
  /// that read images) instead of a path the model cannot open.
  static Object forModel(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return raw;
    }
    if (decoded is! Map<String, dynamic>) return raw;
    final path = decoded['screenshot'];
    if (path is! String || path.isEmpty) return raw;
    decoded
      ..['screenshot'] = 'attached'
      ..['screenshot_note'] =
          'The picture of the viewport is attached as an image. Points in it '
          'map to click/hover x and y after scaling to the viewport size. If '
          'you see no image, your model cannot read images: use observe.';
    return ClientToolResult(
      jsonEncode(decoded),
      metadata: {
        kMcpResultMetadataKey: mcpResultMetadata([path]),
      },
    );
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

  /// Viewport point in CSS pixels from `x` and `y`, when both are given.
  static ({num x, num y})? _point(Map<String, dynamic> args) {
    num? read(String key) {
      final raw = args[key];
      return raw is num ? raw : num.tryParse('${raw ?? ''}');
    }

    final x = read('x');
    final y = read('y');
    return x == null || y == null ? null : (x: x, y: y);
  }

  static int _elementId(Map<String, dynamic> args) {
    final id = _nullableIntArg(args, 'element_id');
    if (id == null || id < 1) {
      throw ArgumentError(
        'element_id must be a positive integer from observe (or give x and '
        'y for click).',
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

  static String _key(Map<String, dynamic> args) {
    final key = _stringArg(args, 'key');
    if (key == null) {
      throw ArgumentError('key is required for action=press_key.');
    }
    // KeyboardEvent.key values ('Enter', 'ArrowDown', ...) are short; a longer
    // string suggests misuse, so clamp before it reaches the JS payload.
    return key.length > 32 ? key.substring(0, 32) : key;
  }

  /// Best-effort source-text guard for `eval_js`, checked before the code reaches the
  /// WebView. It matches the literal source, so it stops a model that reaches for
  /// `document.cookie` by name — not a determined bypass like
  /// `document['coo' + 'kie']`. It is a guardrail against the obvious mistake, not a
  /// sandbox, and the approval prompt (when trust is off) remains the real boundary.
  /// Covers cookie access (session risk on whatever page the browser is logged into),
  /// eval/Function construction, and string-form setTimeout/setInterval.
  static final Map<String, RegExp> _evalBlockedPatterns = {
    'cookie_access': RegExp(r'document\s*\.\s*cookie', caseSensitive: false),
    'dynamic_eval': RegExp(
      r'\beval\s*\(|\bnew\s+Function\s*\(|\bFunction\s*\(',
      caseSensitive: false,
    ),
    'string_timer': RegExp(
      r'''\b(setTimeout|setInterval)\s*\(\s*['"`]''',
      caseSensitive: false,
    ),
  };

  static String? _blockedEvalPattern(String code) {
    for (final entry in _evalBlockedPatterns.entries) {
      if (entry.value.hasMatch(code)) return entry.key;
    }
    return null;
  }

  static Future<Map<String, dynamic>> _evalJs(Map<String, dynamic> args) {
    final code = _stringArg(args, 'code');
    if (code == null) {
      throw ArgumentError('code is required for action=eval_js.');
    }
    final blocked = _blockedEvalPattern(code);
    if (blocked != null) {
      return Future.value({
        'ok': false,
        'error': 'blocked_pattern',
        'message':
            'This script matches a blocked pattern ($blocked) and was not run. '
            'eval_js cannot access document.cookie, use eval/Function, or pass a '
            'string to setTimeout/setInterval.',
      });
    }
    return BrowserAgentSession.instance.evalJs(code);
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
