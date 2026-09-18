import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// One shared browser session used by the visible WebView and the model.
///
/// The model never gets arbitrary JavaScript execution. It can only observe the
/// current document and use the bounded actions implemented here.
class BrowserAgentSession {
  BrowserAgentSession._();

  static final BrowserAgentSession instance = BrowserAgentSession._();

  WebViewController? _controller;
  Completer<void>? _attachedCompleter;
  Completer<void>? _readyCompleter;
  bool _loading = false;

  bool get isAttached => _controller != null;

  void expectNavigation() {
    _loading = true;
    _readyCompleter = Completer<void>();
  }

  void register(WebViewController controller) {
    _controller = controller;
    final attached = _attachedCompleter;
    if (attached != null && !attached.isCompleted) attached.complete();
    _attachedCompleter = null;
  }

  void unregister(WebViewController controller) {
    if (!identical(_controller, controller)) return;
    _controller = null;
    _attachedCompleter = null;
    _loading = false;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('Shared browser was closed.'));
    }
    _readyCompleter = null;
  }

  void pageStarted(String url) {
    _loading = true;
    final previous = _readyCompleter;
    if (previous == null || previous.isCompleted) {
      _readyCompleter = Completer<void>();
    }
  }

  void pageFinished(String url) {
    _loading = false;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  Future<void> waitUntilAttached({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_controller != null) return;
    _attachedCompleter ??= Completer<void>();
    await _attachedCompleter!.future.timeout(timeout);
  }

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_controller == null) {
      throw StateError('Shared browser is not open.');
    }
    if (!_loading) return;
    final ready = _readyCompleter ??= Completer<void>();
    await ready.future.timeout(timeout);
  }

  Future<void> load(Uri uri) async {
    final controller = _requireController();
    expectNavigation();
    await controller.loadRequest(uri);
    await waitUntilReady();
  }

  Future<Map<String, dynamic>> observe({
    String scope = 'viewport',
    int maxTextChars = 3000,
    int maxElements = 36,
    bool includeText = true,
  }) async {
    await waitUntilReady();
    final normalizedScope = scope == 'document' ? 'document' : 'viewport';
    final textLimit = maxTextChars.clamp(256, 8000).toInt();
    final elementLimit = maxElements.clamp(1, 80).toInt();
    final script = _observeScript
        .replaceAll('__SCOPE__', jsonEncode(normalizedScope))
        .replaceAll('__TEXT_LIMIT__', '$textLimit')
        .replaceAll('__ELEMENT_LIMIT__', '$elementLimit')
        .replaceAll('__INCLUDE_TEXT__', includeText ? 'true' : 'false');
    return _runJson(script);
  }

  Future<Map<String, dynamic>> click(int elementId) async {
    await waitUntilReady();
    final result = await _runJson(
      _clickScript.replaceAll('__ELEMENT_ID__', '$elementId'),
    );
    await _settleAfterInteraction();
    return _withCurrentUrl(result);
  }

  Future<Map<String, dynamic>> type(int elementId, String text) async {
    await waitUntilReady();
    final script = _typeScript
        .replaceAll('__ELEMENT_ID__', '$elementId')
        .replaceAll('__TEXT__', jsonEncode(text));
    final result = await _runJson(script);
    return _withCurrentUrl(result);
  }

  Future<Map<String, dynamic>> scroll({
    required String direction,
    int? amount,
  }) async {
    await waitUntilReady();
    const allowed = {'up', 'down', 'top', 'bottom'};
    if (!allowed.contains(direction)) {
      throw ArgumentError('direction must be up, down, top, or bottom.');
    }
    final safeAmount = (amount ?? 0).clamp(0, 5000).toInt();
    final script = _scrollScript
        .replaceAll('__DIRECTION__', jsonEncode(direction))
        .replaceAll('__AMOUNT__', '$safeAmount');
    return _runJson(script);
  }

  Future<Map<String, dynamic>> goBack() async {
    final controller = _requireController();
    await waitUntilReady();
    if (!await controller.canGoBack()) {
      return {
        'ok': false,
        'error': 'no_history',
        'message': 'There is no previous page in browser history.',
      };
    }
    await controller.goBack();
    await _settleAfterInteraction();
    return _pageState();
  }

  Future<Map<String, dynamic>> goForward() async {
    final controller = _requireController();
    await waitUntilReady();
    if (!await controller.canGoForward()) {
      return {
        'ok': false,
        'error': 'no_history',
        'message': 'There is no next page in browser history.',
      };
    }
    await controller.goForward();
    await _settleAfterInteraction();
    return _pageState();
  }

  Future<Map<String, dynamic>> reload() async {
    final controller = _requireController();
    await waitUntilReady();
    await controller.reload();
    await _settleAfterInteraction();
    return _pageState();
  }

  Future<void> _settleAfterInteraction() async {
    // A click/navigation callback can arrive just after the JavaScript result.
    // Give WebView a short turn, then wait only when navigation actually began.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_loading) {
      await waitUntilReady(timeout: const Duration(seconds: 15));
    }
  }

  Future<Map<String, dynamic>> _withCurrentUrl(
    Map<String, dynamic> result,
  ) async {
    if (result['ok'] != true || _controller == null) return result;
    final url = await _controller!.currentUrl();
    return {...result, if (url != null) 'url': url};
  }

  Future<Map<String, dynamic>> _pageState() async {
    await waitUntilReady();
    final controller = _requireController();
    return {
      'ok': true,
      'url': await controller.currentUrl(),
      'can_go_back': await controller.canGoBack(),
      'can_go_forward': await controller.canGoForward(),
    };
  }

  WebViewController _requireController() {
    final controller = _controller;
    if (controller == null) throw StateError('Shared browser is not open.');
    return controller;
  }

  Future<Map<String, dynamic>> _runJson(String script) async {
    final result = await _requireController().runJavaScriptReturningResult(
      script,
    );
    dynamic decoded = result;
    for (var i = 0; i < 2 && decoded is String; i++) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        break;
      }
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw StateError('Shared browser returned an invalid result.');
  }

  static const String _clickScript = r'''
(() => {
  const elements = window.__moruBrowserElements;
  const id = __ELEMENT_ID__;
  if (!Array.isArray(elements) || id < 1 || id > elements.length) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before clicking.'
    });
  }
  const element = elements[id - 1];
  if (!element || !element.isConnected) {
    return JSON.stringify({
      ok: false,
      error: 'stale_element',
      message: 'The element is no longer on the page. Observe again.'
    });
  }
  if (element.disabled) {
    return JSON.stringify({
      ok: false,
      error: 'disabled_element',
      message: 'The selected element is disabled.'
    });
  }
  element.scrollIntoView({block: 'center', inline: 'center'});
  element.click();
  return JSON.stringify({ok: true, element_id: id});
})();
''';

  static const String _typeScript = r'''
(() => {
  const elements = window.__moruBrowserElements;
  const id = __ELEMENT_ID__;
  const text = __TEXT__;
  if (!Array.isArray(elements) || id < 1 || id > elements.length) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before typing.'
    });
  }
  const element = elements[id - 1];
  if (!element || !element.isConnected) {
    return JSON.stringify({
      ok: false,
      error: 'stale_element',
      message: 'The element is no longer on the page. Observe again.'
    });
  }
  const tag = element.tagName.toLowerCase();
  if (tag === 'select') {
    if (element.disabled) {
      return JSON.stringify({
        ok: false,
        error: 'not_editable',
        message: 'The selected element is disabled.'
      });
    }
    const wanted = String(text).trim().toLowerCase();
    const option = Array.from(element.options).find((item) =>
      String(item.value).trim().toLowerCase() === wanted ||
      String(item.textContent || '').trim().toLowerCase() === wanted
    );
    if (!option) {
      return JSON.stringify({
        ok: false,
        error: 'option_not_found',
        message: 'No select option matches the requested text or value.'
      });
    }
    element.focus();
    element.value = option.value;
    element.dispatchEvent(new Event('input', {bubbles: true}));
    element.dispatchEvent(new Event('change', {bubbles: true}));
    return JSON.stringify({
      ok: true,
      element_id: id,
      selected: String(option.textContent || option.value).trim().slice(0, 120)
    });
  }

  const editable = element.isContentEditable ||
      tag === 'input' || tag === 'textarea';
  if (!editable || element.disabled || element.readOnly) {
    return JSON.stringify({
      ok: false,
      error: 'not_editable',
      message: 'The selected element is not editable.'
    });
  }

  element.focus();
  if (element.isContentEditable) {
    element.textContent = text;
  } else {
    const proto = tag === 'textarea'
        ? window.HTMLTextAreaElement.prototype
        : window.HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
    if (descriptor && descriptor.set) {
      descriptor.set.call(element, text);
    } else {
      element.value = text;
    }
  }
  element.dispatchEvent(new Event('input', {bubbles: true}));
  element.dispatchEvent(new Event('change', {bubbles: true}));
  return JSON.stringify({
    ok: true,
    element_id: id,
    typed_length: text.length
  });
})();
''';

  static const String _scrollScript = r'''
(() => {
  const direction = __DIRECTION__;
  const requested = __AMOUNT__;
  const defaultStep = Math.max(240, Math.floor(window.innerHeight * 0.78));
  const amount = requested > 0 ? requested : defaultStep;
  if (direction === 'top') {
    window.scrollTo({top: 0, behavior: 'instant'});
  } else if (direction === 'bottom') {
    window.scrollTo({top: document.documentElement.scrollHeight, behavior: 'instant'});
  } else {
    window.scrollBy({
      top: direction === 'up' ? -amount : amount,
      behavior: 'instant'
    });
  }
  const doc = document.documentElement;
  const maxY = Math.max(0, doc.scrollHeight - window.innerHeight);
  return JSON.stringify({
    ok: true,
    scroll_y: Math.round(window.scrollY),
    viewport_h: window.innerHeight,
    document_h: doc.scrollHeight,
    at_top: window.scrollY <= 1,
    at_bottom: window.scrollY >= maxY - 1
  });
})();
''';

  static const String _observeScript = r'''
(() => {
  const scope = __SCOPE__;
  const maxText = __TEXT_LIMIT__;
  const maxElements = __ELEMENT_LIMIT__;
  const includeText = __INCLUDE_TEXT__;
  const normalize = (value) => String(value || '')
      .replace(/\s+/g, ' ')
      .trim();
  const hasBox = (element) => {
    const style = window.getComputedStyle(element);
    if (style.visibility === 'hidden' || style.display === 'none') return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const inViewport = (element) => {
    if (!hasBox(element)) return false;
    const rect = element.getBoundingClientRect();
    return rect.bottom >= 0 && rect.top <= window.innerHeight &&
        rect.right >= 0 && rect.left <= window.innerWidth;
  };
  const visible = scope === 'document' ? hasBox : inViewport;

  const candidates = Array.from(document.querySelectorAll(
    'a,button,input,textarea,select,summary,[role="button"],[role="link"],[contenteditable="true"]'
  )).filter(visible).slice(0, maxElements);

  window.__moruBrowserElements = candidates;

  const elements = candidates.map((element, index) => {
    const tag = element.tagName.toLowerCase();
    const inputType = tag === 'input'
        ? String(element.getAttribute('type') || 'text').toLowerCase()
        : null;
    const password = inputType === 'password';
    const label = normalize(
      element.innerText ||
      element.getAttribute('aria-label') ||
      element.getAttribute('title') ||
      element.getAttribute('alt') ||
      (!password ? element.value : '') ||
      ''
    ).slice(0, 140);
    const placeholder = normalize(element.getAttribute('placeholder')).slice(0, 100);
    const value = password ? '' : normalize(element.value).slice(0, 120);
    const href = tag === 'a'
        ? normalize(element.getAttribute('href')).slice(0, 180)
        : '';
    const item = {id: index + 1, tag};
    if (inputType) item.type = inputType;
    if (label) item.text = label;
    if (placeholder) item.placeholder = placeholder;
    if (value) item.value = value;
    if (href) item.href = href;
    if (tag === 'select') {
      item.options = Array.from(element.options).slice(0, 12).map((option) => ({
        value: normalize(option.value).slice(0, 80),
        text: normalize(option.textContent).slice(0, 80)
      }));
    }
    if (element.disabled) item.disabled = true;
    return item;
  });

  let text = '';
  if (includeText && document.body) {
    if (scope === 'document') {
      text = normalize(document.body.innerText).slice(0, maxText);
    } else {
      const chunks = [];
      let total = 0;
      const walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT
      );
      let node = walker.nextNode();
      while (node && total < maxText) {
        const parent = node.parentElement;
        const value = normalize(node.textContent);
        if (parent && value && inViewport(parent)) {
          const remaining = maxText - total;
          const piece = value.slice(0, remaining);
          chunks.push(piece);
          total += piece.length + 1;
        }
        node = walker.nextNode();
      }
      text = normalize(chunks.join(' ')).slice(0, maxText);
    }
  }

  const doc = document.documentElement;
  const maxY = Math.max(0, doc.scrollHeight - window.innerHeight);
  const result = {
    ok: true,
    url: location.href,
    title: document.title || '',
    page: {
      scroll_y: Math.round(window.scrollY),
      viewport_h: window.innerHeight,
      document_h: doc.scrollHeight,
      at_top: window.scrollY <= 1,
      at_bottom: window.scrollY >= maxY - 1
    },
    elements
  };
  if (text) result.text = text;
  return JSON.stringify(result);
})();
''';
}
