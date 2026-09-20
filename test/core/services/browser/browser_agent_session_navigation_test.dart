import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

/// Exercises the navigation contract (AGENTS.md section 8) end to end
/// through the real [BrowserAgentSession] and a [WebViewController] backed
/// by [FakeWebViewController] -- as opposed to
/// `browser_navigation_history_test.dart`, which drives
/// [BrowserNavigationHistory] directly.
void main() {
  final session = BrowserAgentSession.instance;

  setUp(installFakeWebViewPlatform);

  /// Registers a fresh controller wired exactly the way
  /// `webview_page.dart` wires the real one: page navigation callbacks
  /// forward straight into the session, which is where reconciliation
  /// happens centrally.
  Future<WebViewController> attach() async {
    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(controller, onClose: () async {});
    addTearDown(() => session.unregister(controller));
    return controller;
  }

  test(
    'load() then agent back() lands on the previously loaded page',
    () async {
      await attach();
      await session.load(Uri.parse('https://example.com/a'));
      await session.load(Uri.parse('https://example.com/b'));

      final result = await session.goBack();

      expect(result['ok'], isTrue);
      expect(result['url'], 'https://example.com/a');
      expect(result['can_go_forward'], isTrue);
    },
  );

  test('goBack() steps exactly one page at a time -- regression for the '
      'double-commit bug where pageFinished\'s own reconciliation and a '
      'second, explicit commitBack() used to both fire for the same '
      'navigation', () async {
    await attach();
    await session.load(Uri.parse('https://example.com/a'));
    await session.load(Uri.parse('https://example.com/b'));
    await session.load(Uri.parse('https://example.com/c'));

    final first = await session.goBack();
    expect(first['url'], 'https://example.com/b');
    // If back had double-stepped, this would already be false (skipped
    // straight past "a" to a nonexistent entry).
    expect(first['can_go_back'], isTrue);

    final second = await session.goBack();
    expect(second['url'], 'https://example.com/a');
    expect(second['can_go_back'], isFalse);
  });

  test('forward() steps exactly one page at a time after two backs', () async {
    await attach();
    await session.load(Uri.parse('https://example.com/a'));
    await session.load(Uri.parse('https://example.com/b'));
    await session.load(Uri.parse('https://example.com/c'));

    await session.goBack();
    await session.goBack();
    final forward = await session.goForward();

    expect(forward['url'], 'https://example.com/b');
    expect(forward['can_go_forward'], isTrue);
  });

  test('a manual navigation (e.g. the address-bar editor calling loadRequest '
      'directly, bypassing session.load) is still reconciled, so a later '
      'agent back() finds it instead of reporting no_history', () async {
    final controller = await attach();
    await session.load(Uri.parse('https://example.com/a'));

    // The address editor calls `_controller.loadRequest` directly, not
    // `session.load` -- this is exactly that path.
    await controller.loadRequest(Uri.parse('https://example.com/manual'));

    final result = await session.goBack();
    expect(result['ok'], isTrue);
    expect(result['url'], 'https://example.com/a');
  });

  test(
    'native UI back (controller.goBack(), not session.goBack()) is '
    'reconciled too, so the model\'s next back() call stays consistent',
    () async {
      final controller = await attach();
      await session.load(Uri.parse('https://example.com/a'));
      await session.load(Uri.parse('https://example.com/b'));

      // Simulates the PopScope/back-button handler, which calls the
      // controller's native goBack() directly -- never session.goBack().
      await controller.goBack();

      // The model's own forward() must now see "b" as the forward target.
      final result = await session.goForward();
      expect(result['ok'], isTrue);
      expect(result['url'], 'https://example.com/b');
    },
  );

  test(
    'goBack() reports no_history once there is nothing further back',
    () async {
      await attach();
      await session.load(Uri.parse('https://example.com/a'));

      final result = await session.goBack();

      expect(result['ok'], isFalse);
      expect(result['error'], 'no_history');
    },
  );
}
