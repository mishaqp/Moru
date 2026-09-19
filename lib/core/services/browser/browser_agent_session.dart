import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import 'browser_research.dart';

class BrowserAgentProtocolException implements Exception {
  const BrowserAgentProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Deterministic history for model-driven navigation.
///
/// Native WebView history can include redirects and entries created outside the
/// agent flow. The agent keeps its own committed-page stack so back/forward
/// always mean the pages the model actually reached.
class BrowserNavigationHistory {
  final List<String> _entries = <String>[];
  int _index = -1;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index < _entries.length - 1;
  String? get current =>
      _index >= 0 && _index < _entries.length ? _entries[_index] : null;
  String? get backTarget => canGoBack ? _entries[_index - 1] : null;
  String? get forwardTarget => canGoForward ? _entries[_index + 1] : null;

  void reset(String url) {
    _entries
      ..clear()
      ..add(url);
    _index = 0;
  }

  void push(String url) {
    if (url.isEmpty || current == url) return;
    if (canGoForward) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(url);
    _index = _entries.length - 1;
  }

  void commitBack() {
    if (canGoBack) _index--;
  }

  void commitForward() {
    if (canGoForward) _index++;
  }

  void clear() {
    _entries.clear();
    _index = -1;
  }
}

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
  int _navigationSequence = 0;
  Future<void> Function()? _closeHandler;
  final BrowserNavigationHistory _history = BrowserNavigationHistory();

  bool get isAttached => _controller != null;

  void expectNavigation() {
    _loading = true;
    _readyCompleter = Completer<void>();
  }

  void register(
    WebViewController controller, {
    Future<void> Function()? onClose,
  }) {
    _controller = controller;
    _closeHandler = onClose;
    final attached = _attachedCompleter;
    if (attached != null && !attached.isCompleted) attached.complete();
    _attachedCompleter = null;
  }

  void unregister(WebViewController controller) {
    if (!identical(_controller, controller)) return;
    _controller = null;
    _closeHandler = null;
    _attachedCompleter = null;
    _loading = false;
    _history.clear();
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('Shared browser was closed.'));
    }
    _readyCompleter = null;
  }

  void pageStarted(String url) {
    _navigationSequence++;
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
    await _recordCurrentPage();
  }

  Future<void> recordInitialPage() async {
    await waitUntilReady();
    final url = await _requireController().currentUrl();
    if (url != null && url.isNotEmpty) {
      _history.reset(url);
    }
  }

  Future<Map<String, dynamic>> close() async {
    if (!isAttached) {
      return {
        'ok': false,
        'error': 'browser_not_open',
        'message': 'Shared browser is not open.',
      };
    }
    final closeHandler = _closeHandler;
    if (closeHandler == null) {
      throw const BrowserAgentProtocolException(
        'Shared browser close handler is unavailable.',
      );
    }
    await closeHandler();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (isAttached && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (isAttached) {
      return {
        'ok': false,
        'error': 'browser_close_timeout',
        'message': 'Shared browser did not close in time.',
      };
    }
    return {'ok': true, 'closed': true};
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
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final result = await _runJson(
      _clickScript.replaceAll('__ELEMENT_ID__', '$elementId'),
    );
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: result['may_navigate'] == true
            ? const Duration(seconds: 1)
            : const Duration(milliseconds: 180),
      );
      await _recordCurrentPageIfChanged(beforeUrl);
    }
    final visibleResult = Map<String, dynamic>.from(result)
      ..remove('may_navigate');
    return _withCurrentUrl(visibleResult);
  }

  Future<Map<String, dynamic>> type(int elementId, String text) async {
    await waitUntilReady();
    final controller = _requireController();
    final beforeUrl = await controller.currentUrl();
    final beforeSequence = _navigationSequence;
    final script = _typeScript
        .replaceAll('__ELEMENT_ID__', '$elementId')
        .replaceAll('__TEXT__', jsonEncode(text));
    final result = await _runJson(script);
    if (result['ok'] == true) {
      await _settleAfterInteraction(
        navigationSequence: beforeSequence,
        urlBefore: beforeUrl,
        navigationGrace: const Duration(milliseconds: 250),
      );
      await _recordCurrentPageIfChanged(beforeUrl);
    }
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

  /// Reads the rendered page text for the browser research path.
  ///
  /// Implements [RenderedPageReader]: a whole-document read (no selector) is reported as
  /// [RenderedScope.fullPage] and doubles as the research corpus, so [browserTextEnvelope]
  /// can hand out a `source_id`. A selector-scoped read is [RenderedScope.selector] and is
  /// never cached as a page-level source. There is no article/Readability heuristic yet: the
  /// extract mode is honestly reported as `raw` rather than claiming a pass this layer does
  /// not run.
  Future<RenderedRead> read(ReadRequest request) async {
    if (!isAttached) return const RenderedReadNotOpen();
    await waitUntilReady();
    final selector = request.selector;
    Map<String, dynamic> result;
    try {
      result = await _runJson(
        _readScript
            .replaceAll('__SELECTOR__', jsonEncode(selector ?? ''))
            .replaceAll('__MAX_CHARS__', '$browserResearchMaxChars'),
      );
    } on BrowserAgentProtocolException catch (error) {
      return RenderedReadFailure(
        'browser_protocol_error',
        detail: error.message,
      );
    }
    if (result['ok'] != true) {
      return RenderedReadFailure(
        (result['error'] ?? 'read_failed').toString(),
        detail: result['message']?.toString(),
      );
    }
    final text = (result['text'] ?? '').toString();
    final truncated = result['truncated'] == true;
    final scope = selector == null
        ? RenderedScope.fullPage
        : RenderedScope.selector;
    return RenderedReadOk(
      RenderedPage(
        url: result['url']?.toString(),
        title: result['title']?.toString(),
        text: text,
        extractMode: 'raw',
        scope: scope,
        readTruncated: truncated,
        researchText: scope == RenderedScope.fullPage ? text : null,
        researchTruncated: truncated,
      ),
    );
  }

  Future<Map<String, dynamic>> goBack() async {
    final controller = _requireController();
    await waitUntilReady();
    final target = _history.backTarget;
    if (target == null) {
      return {
        'ok': false,
        'error': 'no_history',
        'message': 'There is no previous page in browser history.',
      };
    }
    expectNavigation();
    await controller.loadRequest(Uri.parse(target));
    await waitUntilReady(timeout: const Duration(seconds: 15));
    _history.commitBack();
    return _pageState();
  }

  Future<Map<String, dynamic>> goForward() async {
    final controller = _requireController();
    await waitUntilReady();
    final target = _history.forwardTarget;
    if (target == null) {
      return {
        'ok': false,
        'error': 'no_history',
        'message': 'There is no next page in browser history.',
      };
    }
    expectNavigation();
    await controller.loadRequest(Uri.parse(target));
    await waitUntilReady(timeout: const Duration(seconds: 15));
    _history.commitForward();
    return _pageState();
  }

  Future<Map<String, dynamic>> reload() async {
    final controller = _requireController();
    await waitUntilReady();
    expectNavigation();
    await controller.reload();
    await waitUntilReady(timeout: const Duration(seconds: 15));
    return _pageState();
  }

  Future<void> _settleAfterInteraction({
    required int navigationSequence,
    required String? urlBefore,
    required Duration navigationGrace,
  }) async {
    final deadline = DateTime.now().add(navigationGrace);
    while (DateTime.now().isBefore(deadline)) {
      if (_navigationSequence != navigationSequence || _loading) {
        await waitUntilReady(timeout: const Duration(seconds: 15));
        return;
      }
      final currentUrl = await _requireController().currentUrl();
      if (urlBefore != null && currentUrl != null && currentUrl != urlBefore) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (_loading) {
          await waitUntilReady(timeout: const Duration(seconds: 15));
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _recordCurrentPage() async {
    final url = await _requireController().currentUrl();
    if (url != null && url.isNotEmpty) {
      _history.push(url);
    }
  }

  Future<void> _recordCurrentPageIfChanged(String? beforeUrl) async {
    final url = await _requireController().currentUrl();
    if (url != null && url.isNotEmpty && url != beforeUrl) {
      _history.push(url);
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
      'can_go_back': _history.canGoBack,
      'can_go_forward': _history.canGoForward,
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
    throw const BrowserAgentProtocolException(
      'Shared browser returned an invalid result.',
    );
  }

  static const String _clickScript = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const id = __ELEMENT_ID__;
  if (!(elements instanceof Map)) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before clicking.'
    });
  }
  if (!elements.has(id)) {
    return JSON.stringify({
      ok: false,
      error: 'invalid_element_id',
      message: 'Choose an element_id from the latest observe result.'
    });
  }
  const element = elements.get(id);
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
  const tag = element.tagName.toLowerCase();
  const inputType = tag === 'input'
      ? String(element.getAttribute('type') || 'text').toLowerCase()
      : '';
  const role = String(element.getAttribute('role') || '').toLowerCase();
  const mayNavigate = tag === 'a' || tag === 'button' ||
      role === 'link' || role === 'button' ||
      (tag === 'input' && ['submit', 'button', 'image'].includes(inputType)) ||
      Boolean(element.getAttribute('onclick'));
  element.scrollIntoView({block: 'center', inline: 'center'});
  element.click();
  return JSON.stringify({
    ok: true,
    element_id: id,
    may_navigate: mayNavigate
  });
})();
''';

  static const String _typeScript = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const id = __ELEMENT_ID__;
  const text = __TEXT__;
  if (!(elements instanceof Map)) {
    return JSON.stringify({
      ok: false,
      error: 'stale_observation',
      message: 'Observe the page again before typing.'
    });
  }
  if (!elements.has(id)) {
    return JSON.stringify({
      ok: false,
      error: 'invalid_element_id',
      message: 'Choose an element_id from the latest observe result.'
    });
  }
  const element = elements.get(id);
  if (!element || !element.isConnected) {
    return JSON.stringify({
      ok: false,
      error: 'stale_element',
      message: 'The element is no longer on the page. Observe again.'
    });
  }
  const tag = element.tagName.toLowerCase();
  const inputType = tag === 'input'
      ? String(element.getAttribute('type') || 'text').toLowerCase()
      : '';
  if (tag === 'input' && inputType === 'file') {
    return JSON.stringify({
      ok: false,
      error: 'unsupported_element_type',
      message: 'File inputs cannot be filled with browser_use type.'
    });
  }
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

  static const String _readScript = r'''
(() => {
  const selector = __SELECTOR__;
  const maxChars = __MAX_CHARS__;
  let root;
  if (selector) {
    root = document.querySelector(selector);
    if (!root) {
      return JSON.stringify({
        ok: false,
        error: 'selector_not_found',
        message: 'No element matches the given selector.'
      });
    }
  } else {
    root = document.body;
  }
  if (!root) {
    return JSON.stringify({
      ok: false,
      error: 'read_unavailable',
      message: 'The page has no readable content yet.'
    });
  }
  // textContent (not innerText) so a page that hides most sections behind
  // CSS until the user taps them (e.g. Wikipedia's mobile skin collapses
  // every section but the lead) still yields its full body text; innerText
  // is visibility-aware and would return only what's on-screen right now.
  // script/style/template are stripped first so their source code never
  // leaks into the "page text" the way textContent normally would.
  const clone = root.cloneNode(true);
  clone.querySelectorAll('script, style, noscript, template').forEach((el) => el.remove());
  const raw = (clone.textContent || '').toString();
  const truncated = raw.length > maxChars;
  const text = truncated ? raw.slice(0, maxChars) : raw;
  return JSON.stringify({
    ok: true,
    url: (document.location && document.location.href) || '',
    title: document.title || '',
    text,
    truncated
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

  if (!(window.__moruBrowserElementRegistry instanceof Map)) {
    window.__moruBrowserElementRegistry = new Map();
    window.__moruBrowserElementIds = new WeakMap();
    window.__moruBrowserNextElementId = 1;
  }
  const registry = window.__moruBrowserElementRegistry;
  const ids = window.__moruBrowserElementIds;

  const elements = candidates.map((element) => {
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
    let id = ids.get(element);
    if (!id) {
      id = window.__moruBrowserNextElementId++;
      ids.set(element, id);
    }
    registry.set(id, element);
    const item = {id, tag};
    if (inputType) item.type = inputType;
    if (label) item.text = label;
    if (placeholder) item.placeholder = placeholder;
    if (value) item.value = value;
    if (href) item.href = href;
    if (inputType === 'checkbox' || inputType === 'radio') {
      item.checked = Boolean(element.checked);
    }
    if (element.readOnly) item.readonly = true;
    if (tag === 'select') {
      item.selected_index = element.selectedIndex;
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
