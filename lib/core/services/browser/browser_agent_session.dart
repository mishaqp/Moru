import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// One shared browser session used by the visible WebView and the model.
///
/// The model never gets arbitrary JavaScript execution. It can only observe the
/// current document and act on elements returned by the latest observation.
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

  Future<Map<String, dynamic>> observe() async {
    await waitUntilReady();
    return _runJson(_observeScript);
  }

  Future<Map<String, dynamic>> click(int elementId) async {
    await waitUntilReady();
    final script = '''
(() => {
  const elements = window.__moruBrowserElements;
  const id = $elementId;
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
  element.scrollIntoView({block: 'center', inline: 'center'});
  element.click();
  return JSON.stringify({ok: true, element_id: id});
})();
''';
    return _runJson(script);
  }

  Future<Map<String, dynamic>> type(int elementId, String text) async {
    await waitUntilReady();
    final encodedText = jsonEncode(text);
    final script = '''
(() => {
  const elements = window.__moruBrowserElements;
  const id = $elementId;
  const text = $encodedText;
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
  const editable = element.isContentEditable ||
      tag === 'input' || tag === 'textarea';
  if (!editable) {
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
    return _runJson(script);
  }

  WebViewController _requireController() {
    final controller = _controller;
    if (controller == null) throw StateError('Shared browser is not open.');
    return controller;
  }

  Future<Map<String, dynamic>> _runJson(String script) async {
    final result = await _requireController().runJavaScriptReturningResult(script);
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

  static const String _observeScript = r'''
(() => {
  const normalize = (value) => String(value || '')
      .replace(/\s+/g, ' ')
      .trim();
  const visible = (element) => {
    const style = window.getComputedStyle(element);
    if (style.visibility === 'hidden' || style.display === 'none') return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  const candidates = Array.from(document.querySelectorAll(
    'a,button,input,textarea,select,summary,[role="button"],[contenteditable="true"]'
  )).filter(visible).slice(0, 80);

  window.__moruBrowserElements = candidates;

  const elements = candidates.map((element, index) => {
    const tag = element.tagName.toLowerCase();
    const inputType = tag === 'input'
        ? String(element.getAttribute('type') || 'text').toLowerCase()
        : null;
    const password = inputType === 'password';
    return {
      id: index + 1,
      tag,
      type: inputType,
      text: normalize(
        element.innerText ||
        element.getAttribute('aria-label') ||
        element.getAttribute('title') ||
        element.getAttribute('alt') ||
        element.value ||
        ''
      ).slice(0, 240),
      placeholder: normalize(element.getAttribute('placeholder')).slice(0, 160),
      value: password ? '' : normalize(element.value).slice(0, 240),
      disabled: !!element.disabled
    };
  });

  return JSON.stringify({
    ok: true,
    url: location.href,
    title: document.title || '',
    text: normalize(document.body ? document.body.innerText : '').slice(0, 12000),
    elements
  });
})();
''';
}
