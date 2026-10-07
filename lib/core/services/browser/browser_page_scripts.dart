/// Page scripts behind `browser_use` collect, outline, wait_stable and
/// human-like typing. Each returns a JSON string; placeholders in capitals
/// are replaced (JSON-encoded) before it runs.
class BrowserPageScripts {
  const BrowserPageScripts._();

  /// The items of a list or feed now in the page: [__SELECTOR__] when given,
  /// otherwise the largest group of alike siblings (same tag and class)
  /// with text, like search results, posts or products.
  static const String collect = r'''
(() => {
  const selector = __SELECTOR__;
  let nodes = [];
  let used = selector;
  if (selector) {
    try {
      nodes = Array.from(document.querySelectorAll(selector));
    } catch (e) {
      return JSON.stringify({ok: false, error: 'invalid_selector', message: String(e.message || e)});
    }
  } else {
    const groups = new Map();
    document.querySelectorAll('body *').forEach((el) => {
      const parent = el.parentElement;
      if (!parent || el.children.length === 0 && (el.textContent || '').trim().length < 20) return;
      if (['SCRIPT', 'STYLE', 'NAV', 'OPTION', 'BR'].includes(el.tagName)) return;
      const key = parent.tagName + '>' + el.tagName + '.' + String(el.className || '').trim().split(/\s+/).slice(0, 2).join('.');
      let group = groups.get(parent);
      if (!group) { group = new Map(); groups.set(parent, group); }
      const list = group.get(key) || [];
      list.push(el);
      group.set(key, list);
    });
    let bestScore = 0;
    groups.forEach((group) => group.forEach((list) => {
      if (list.length < 3) return;
      const text = list.reduce((sum, el) => sum + Math.min((el.innerText || '').trim().length, 400), 0);
      const score = text * Math.min(list.length, 30);
      if (score > bestScore) { bestScore = score; nodes = list; }
    }));
    used = nodes.length ? 'auto' : null;
  }
  const items = [];
  nodes.forEach((el) => {
    const text = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 400);
    if (!text) return;
    // The item's own link is the one with the most text (its title), not
    // the first (often a vote arrow, an avatar or a menu).
    const links = (el.tagName === 'A' ? [el] : Array.from(el.querySelectorAll('a[href]')))
        .filter((a) => a.href && !a.href.startsWith('javascript:'));
    const words = (a) => (a.innerText || a.textContent || '').trim().length;
    const link = links.sort((a, b) => words(b) - words(a))[0];
    const item = {text};
    if (link && link.href) item.href = link.href;
    items.push(item);
  });
  const scroller = document.scrollingElement || document.documentElement;
  return JSON.stringify({
    ok: true,
    selector: used,
    items,
    at_bottom: window.scrollY + window.innerHeight >= scroller.scrollHeight - 4
  });
})()
''';

  /// A compact map of the page: landmarks, headings, forms, lists and
  /// tables with their sizes, at most [__MAX_LINES__] lines.
  static const String outline = r'''
(() => {
  const maxLines = __MAX_LINES__;
  const lines = [];
  const text = (el, n) => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, n);
  const visible = (el) => {
    const style = getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden';
  };
  const depthOf = (el) => {
    let depth = 0;
    for (let node = el.parentElement; node; node = node.parentElement) {
      if (node.matches('header, nav, main, aside, footer, form, section, article, [role]')) depth++;
    }
    return Math.min(depth, 4);
  };
  const push = (el, line) => {
    if (lines.length < maxLines) lines.push('  '.repeat(depthOf(el)) + line);
  };
  document.querySelectorAll(
    'header, nav, main, aside, footer, [role=navigation], [role=main], [role=search], ' +
    'h1, h2, h3, form, ul, ol, table, article, dialog[open], [role=dialog]'
  ).forEach((el) => {
    if (!visible(el)) return;
    const tag = el.tagName.toLowerCase();
    const role = el.getAttribute('role');
    if (/^h[1-3]$/.test(tag)) {
      const label = text(el, 90);
      if (label) push(el, tag + ': ' + label);
    } else if (tag === 'form' || role === 'search') {
      const fields = el.querySelectorAll('input:not([type=hidden]), textarea, select').length;
      const buttons = el.querySelectorAll('button, input[type=submit]').length;
      push(el, 'form' + (el.getAttribute('aria-label') ? ' "' + el.getAttribute('aria-label') + '"' : '') +
          ': ' + fields + ' fields, ' + buttons + ' buttons');
    } else if (tag === 'ul' || tag === 'ol') {
      const items = el.querySelectorAll(':scope > li').length;
      if (items >= 3) push(el, 'list: ' + items + ' items, first "' + text(el.querySelector('li'), 60) + '"');
    } else if (tag === 'table') {
      const rows = el.querySelectorAll('tr').length;
      const head = Array.from(el.querySelectorAll('th')).slice(0, 5).map((th) => text(th, 20)).join(' | ');
      push(el, 'table: ' + rows + ' rows' + (head ? ' [' + head + ']' : ''));
    } else if (tag === 'article') {
      const heading = el.querySelector('h1, h2, h3, h4');
      push(el, 'article' + (heading ? ': ' + text(heading, 80) : ''));
    } else {
      const links = el.querySelectorAll('a[href]').length;
      push(el, (role || tag) + (links ? ' (' + links + ' links)' : ''));
    }
  });
  const scroller = document.scrollingElement || document.documentElement;
  return JSON.stringify({
    ok: true,
    url: location.href,
    title: document.title,
    outline: lines.join('\n'),
    truncated: lines.length >= maxLines,
    links: document.querySelectorAll('a[href]').length,
    document_h: scroller.scrollHeight
  });
})()
''';

  /// How long ago the page last changed: a MutationObserver installed on
  /// the first call keeps the time of the last change.
  static const String quietFor = r'''
(() => {
  if (!window.__moruMutationWatch) {
    window.__moruLastMutation = Date.now();
    window.__moruMutationWatch = new MutationObserver(() => { window.__moruLastMutation = Date.now(); });
    window.__moruMutationWatch.observe(document.documentElement, {
      childList: true, subtree: true, characterData: true, attributes: true
    });
  }
  return JSON.stringify({
    quiet_ms: Date.now() - window.__moruLastMutation,
    ready: document.readyState === 'complete'
  });
})()
''';

  /// Focuses element [__ELEMENT_ID__] of the latest observe and empties it,
  /// before typing into it key by key.
  static const String typingStart = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const element = elements instanceof Map ? elements.get(__ELEMENT_ID__) : null;
  if (!element || !element.isConnected) {
    return JSON.stringify({ok: false, error: 'stale_element', message: 'Observe the page again before typing.'});
  }
  const tag = element.tagName.toLowerCase();
  const editable = element.isContentEditable || tag === 'textarea' ||
      (tag === 'input' && !['file', 'checkbox', 'radio', 'submit', 'button'].includes(String(element.type).toLowerCase()));
  if (!editable || element.disabled || element.readOnly) {
    return JSON.stringify({ok: false, error: 'not_editable', message: 'The selected element is not editable.'});
  }
  element.focus();
  if (element.isContentEditable) {
    element.textContent = '';
  } else {
    const proto = tag === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(element, '');
  }
  element.dispatchEvent(new Event('input', {bubbles: true}));
  window.__moruTypingTarget = element;
  return JSON.stringify({ok: true});
})()
''';

  /// Types [__TEXT__] (a few characters) into the element [typingStart]
  /// chose, with the key events a person's keyboard sends.
  static const String typingKeys = r'''
(() => {
  const element = window.__moruTypingTarget;
  if (!element || !element.isConnected) {
    return JSON.stringify({ok: false, error: 'stale_element', message: 'The field went away while typing.'});
  }
  const tag = element.tagName.toLowerCase();
  for (const ch of __TEXT__) {
    const init = {key: ch, bubbles: true, cancelable: true};
    element.dispatchEvent(new KeyboardEvent('keydown', init));
    element.dispatchEvent(new KeyboardEvent('keypress', init));
    if (element.isContentEditable) {
      document.execCommand('insertText', false, ch);
    } else {
      const proto = tag === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(element, element.value + ch);
      element.dispatchEvent(new InputEvent('input', {data: ch, inputType: 'insertText', bubbles: true}));
    }
    element.dispatchEvent(new KeyboardEvent('keyup', init));
  }
  return JSON.stringify({ok: true});
})()
''';

  /// Ends human-like typing with the change event a field sends on blur.
  static const String typingEnd = r'''
(() => {
  const element = window.__moruTypingTarget;
  if (element && element.isConnected) element.dispatchEvent(new Event('change', {bubbles: true}));
  delete window.__moruTypingTarget;
  return JSON.stringify({ok: true});
})()
''';

  /// The center of element [__ELEMENT_ID__] of the latest observe, scrolled
  /// into the middle of the view, for a real tap on it.
  static const String elementCenter = r'''
(() => {
  const elements = window.__moruBrowserElementRegistry;
  const element = elements instanceof Map ? elements.get(__ELEMENT_ID__) : null;
  if (!element || !element.isConnected) {
    return JSON.stringify({ok: false, error: 'stale_element', message: 'Observe the page again before clicking.'});
  }
  element.scrollIntoView({block: 'center', inline: 'center'});
  const rect = element.getBoundingClientRect();
  return JSON.stringify({ok: true, x: rect.left + rect.width / 2, y: rect.top + rect.height / 2});
})()
''';
}
