import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

/// Exercises `BrowserAgentSession.close()`'s own contract directly (a plain
/// `test()`, not `testWidgets()`): it awaits whatever `onClose` handler was
/// registered, then polls until the session is detached, or reports a
/// timeout. `webview_page_test.dart` separately proves the real UI-level
/// close path (a manual tap on the close button, which reuses the same
/// `_closeAgentSession` the registered `onClose` handler calls) cancels an
/// in-flight Ask-AI request; this file proves `close()` itself correctly
/// drives whatever handler ends up registered, independent of Flutter's
/// widget-test frame timing (real `Future.delayed` calls need a real event
/// loop, which a plain `test()` already provides without `runAsync`
/// gymnastics).
void main() {
  final session = BrowserAgentSession.instance;

  setUp(installFakeWebViewPlatform);

  test('close() invokes the registered onClose handler and waits for it to '
      'actually detach the session', () async {
    final controller = WebViewController();
    var onCloseCalled = false;
    session.register(
      controller,
      onClose: () async {
        onCloseCalled = true;
        // Simulates what the real UI does once its own close logic
        // finishes: unregister once the page has torn down.
        session.unregister(controller);
      },
    );

    final result = await session.close();

    expect(onCloseCalled, isTrue);
    expect(result['ok'], isTrue);
    expect(result['closed'], isTrue);
    expect(session.isAttached, isFalse);
  });

  test('close() reports browser_close_timeout when the handler never actually '
      'detaches the session', () async {
    final controller = WebViewController();
    session.register(controller, onClose: () async {});
    addTearDown(() => session.unregister(controller));

    final result = await session.close();

    expect(result['ok'], isFalse);
    expect(result['error'], 'browser_close_timeout');
  });

  test('close() reports browser_not_open when nothing is attached', () async {
    final result = await session.close();
    expect(result['ok'], isFalse);
    expect(result['error'], 'browser_not_open');
  });
}
