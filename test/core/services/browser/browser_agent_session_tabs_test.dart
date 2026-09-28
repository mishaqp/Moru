import 'dart:convert';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_tabs.dart';
import 'package:Kelivo/features/home/services/browser_agent_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = BrowserAgentSession.instance;
  late FakeWebViewController first;
  late WebViewController firstController;
  final created = <FakeWebViewController>[];

  setUp(() async {
    installFakeWebViewPlatform();
    created.clear();
    session.controllerFactory = () {
      final controller = WebViewController();
      created.add(FakeWebViewPlatform.lastCreated!);
      return controller;
    };
    firstController = WebViewController();
    first = FakeWebViewPlatform.lastCreated!;
    // What the browser page does: its own delegate feeds the session.
    await firstController.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(
      firstController,
      onClose: () async {
        session.unregister(session.controller!);
      },
    );
    await session.load(Uri.parse('https://first.example/'));
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    if (session.isAttached) session.unregister(session.controller!);
    session.clock = DateTime.now;
    await Future<void>.delayed(Duration.zero);
  });

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async =>
      jsonDecode(await BrowserAgentTool.execute(args)) as Map<String, dynamic>;

  List<String?> urls() => [for (final t in session.tabs.value) t.url];

  test('a new tab opens alongside and the old one keeps its page', () async {
    final opened = await run({
      'action': 'new_tab',
      'url': 'https://second.example/',
    });
    expect(opened['ok'], isTrue);
    final second = created.single;
    expect(identical(session.controller!.platform, second), isTrue);
    expect(urls(), ['https://first.example/', 'https://second.example/']);
    expect([for (final t in session.tabs.value) t.active], [false, true]);

    // The background tab navigates on its own; the session's page is still
    // the second tab.
    await firstController.loadRequest(Uri.parse('https://first.example/b'));
    expect(urls().first, 'https://first.example/b');
    expect(session.pageUrl.value, 'https://second.example/');

    // Actions work on the active tab.
    second.jsHandler = (_) => jsonEncode({'ok': true, 'url': 'x'});
    first.jsHandler = (_) => throw StateError('the background tab was used');
    expect((await run({'action': 'observe'}))['ok'], isTrue);

    final firstId = session.tabs.value.first.id;
    final switched = await run({'action': 'switch_tab', 'tab_id': firstId});
    expect(switched['ok'], isTrue);
    expect(identical(session.controller, firstController), isTrue);
    expect(session.pageUrl.value, 'https://first.example/b');
    // Its history went on in the background.
    final back = await run({'action': 'back'});
    expect(back['url'], 'https://first.example/');
  });

  test('closing the active tab shows its neighbour; the last one closes the '
      'browser', () async {
    await run({'action': 'new_tab', 'url': 'https://second.example/'});
    final closed = await run({'action': 'close_tab'});
    expect(closed['ok'], isTrue);
    expect(urls(), ['https://first.example/']);
    expect(identical(session.controller, firstController), isTrue);
    // The closed tab stops its page.
    expect(await created.single.currentUrl(), 'about:blank');

    final last = await run({'action': 'close_tab'});
    expect(last['closed'], isTrue);
    expect(session.isAttached, isFalse);
  });

  test('at most five tabs; unknown ids are reported', () async {
    for (var i = 0; i < BrowserAgentSession.maxTabs - 1; i++) {
      expect((await run({'action': 'new_tab'}))['ok'], isTrue);
    }
    final refused = await run({'action': 'new_tab'});
    expect(refused['error'], 'too_many_tabs');
    expect(refused['tabs'], hasLength(BrowserAgentSession.maxTabs));
    expect(
      (await run({'action': 'switch_tab', 'tab_id': 'nope'}))['error'],
      'no_such_tab',
    );
    expect(
      (await run({'action': 'new_tab', 'url': 'file:///etc/passwd'}))['error'],
      'invalid_url',
    );
  });

  test('tabs the model left unused for 15 minutes close, except the one on '
      'screen and the user\'s', () async {
    var now = DateTime(2026, 9, 28, 12);
    session.clock = () => now;
    await run({'action': 'new_tab', 'url': 'https://a.example/'});
    await run({'action': 'new_tab', 'url': 'https://b.example/'});
    final ids = [for (final t in session.tabs.value) t.id];
    // The user's own first tab is on screen now; b was used last.
    await session.switchTab(ids.first);

    now = now.add(const Duration(minutes: 14));
    expect(session.closeIdleAgentTabs(), isEmpty);
    now = now.add(const Duration(minutes: 2));
    expect(session.closeIdleAgentTabs(), [ids[1], ids[2]]);
    expect([for (final t in session.tabs.value) t.id], [ids.first]);
  });

  test('desktop mode sets a desktop user agent of the same Chrome and '
      'reloads; mobile restores the WebView\'s own', () async {
    final desktop = await run({'action': 'set_mode', 'mode': 'desktop'});
    expect(desktop['mode'], 'desktop');
    expect(
      first.userAgent,
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.6778.39 Safari/537.36',
    );
    expect(session.tabs.value.single.desktop, isTrue);

    await run({'action': 'set_mode', 'mode': 'mobile'});
    expect(first.userAgent, isNull);
    expect(session.tabs.value.single.desktop, isFalse);
    expect(
      (await run({'action': 'set_mode', 'mode': 'tv'}))['error'],
      'invalid_mode',
    );
  });

  test('desktopUserAgent falls back to a current Chrome', () {
    expect(desktopUserAgent(null), contains('Chrome/'));
    expect(desktopUserAgent('x'), isNot(contains('Mobile')));
  });
}
