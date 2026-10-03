import 'dart:convert';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_agent_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = BrowserAgentSession.instance;
  late FakeWebViewController fake;

  setUp(() async {
    installFakeWebViewPlatform();
    final controller = WebViewController();
    fake = FakeWebViewPlatform.lastCreated!;
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(controller, onClose: () async {});
    await session.load(Uri.parse('https://feed.example/'));
  });

  tearDown(() {
    if (session.isAttached) session.unregister(session.controller!);
    session.keyPause = () => const Duration(milliseconds: 60);
  });

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async =>
      jsonDecode(await BrowserAgentTool.execute(args)) as Map<String, dynamic>;

  test('collect scrolls a feed, keeps each item once and stops when '
      'scrolling brings nothing new', () async {
    final pages = [
      [
        {'text': 'Post 1', 'href': 'https://feed.example/1'},
        {'text': 'Post 2', 'href': 'https://feed.example/2'},
      ],
      [
        {'text': 'Post 2', 'href': 'https://feed.example/2'},
        {'text': 'Post 3', 'href': 'https://feed.example/3'},
      ],
      [
        {'text': 'Post 3', 'href': 'https://feed.example/3'},
      ],
    ];
    var shown = 0;
    var scrolls = 0;
    fake.jsHandler = (script) {
      if (script.contains('scrollBy')) {
        scrolls++;
        if (shown < pages.length - 1) shown++;
        return jsonEncode({'ok': true});
      }
      if (script.contains('__moruMutationWatch')) {
        return jsonEncode({'quiet_ms': 1000, 'ready': true});
      }
      if (script.contains('alike') || script.contains('at_bottom')) {
        return jsonEncode({
          'ok': true,
          'selector': 'auto',
          'items': pages[shown],
          'at_bottom': false,
        });
      }
      return jsonEncode({'ok': true, 'url': 'https://feed.example/'});
    };

    final result = await run({'action': 'collect'});
    expect(result['ok'], isTrue);
    expect(
      [for (final item in result['items']) item['text']],
      ['Post 1', 'Post 2', 'Post 3'],
    );
    expect(result['selector'], 'auto');
    // Two scrolls in a row brought nothing new: it stopped.
    expect(scrolls, 3);

    final capped = await run({'action': 'collect', 'max_items': 1});
    expect(capped['count'], 1);
  });

  test('wait_stable waits for a quiet page and reports one that keeps '
      'changing', () async {
    var quiet = 0;
    fake.jsHandler = (script) {
      if (script.contains('__moruMutationWatch')) {
        quiet += 300;
        return jsonEncode({'quiet_ms': quiet, 'ready': true});
      }
      return jsonEncode({'ok': true, 'url': 'x'});
    };
    final stable = await run({'action': 'wait_stable', 'quiet_ms': 600});
    expect(stable['stable'], isTrue);

    fake.jsHandler = (script) =>
        jsonEncode({'quiet_ms': 0, 'ready': true, 'ok': true, 'url': 'x'});
    final busy = await run({
      'action': 'wait_stable',
      'quiet_ms': 600,
      'timeout_ms': 500,
    });
    expect(busy['ok'], isTrue);
    expect(busy['stable'], isFalse);
  });

  test('human typing empties the field, then types two keys at a time with '
      'pauses, and ends with change', () async {
    session.keyPause = () => Duration.zero;
    final scripts = <String>[];
    fake.jsHandler = (script) {
      scripts.add(script);
      return jsonEncode({'ok': true, 'url': 'x'});
    };
    final typed = await run({
      'action': 'type',
      'element_id': 3,
      'text': 'hello',
      'human': true,
    });
    expect(typed, containsPair('human', true));
    expect(typed['typed_length'], 5);
    final keys = [
      for (final script in scripts)
        if (script.contains('KeyboardEvent'))
          RegExp(r'for \(const ch of ("[^"]*")\)').firstMatch(script)!.group(1),
    ];
    expect(keys, ['"he"', '"ll"', '"o"']);
    expect(
      scripts.any((s) => s.contains('__moruTypingTarget = element')),
      isTrue,
    );
    expect(scripts.any((s) => s.contains("new Event('change'")), isTrue);

    final tooLong = await run({
      'action': 'type',
      'element_id': 3,
      'text': 'x' * (BrowserAgentSession.humanTypingMaxChars + 1),
      'human': true,
    });
    expect(tooLong['error'], 'text_too_long');
  });

  test('read in reader mode asks the page for the article only', () async {
    String? readScript;
    fake.jsHandler = (script) {
      if (script.contains('__MAX_CHARS__') || script.contains('boilerplate')) {
        readScript = script;
        return jsonEncode({
          'ok': true,
          'url': 'https://feed.example/',
          'title': 'Feed',
          'text': 'The article text.',
          'truncated': false,
        });
      }
      return jsonEncode({'ok': true, 'url': 'x'});
    };
    final result = await run({'action': 'read', 'extract_mode': 'readability'});
    expect(result['ok'], isTrue);
    expect(readScript, contains('const mode = "readability"'));
  });

  test('outline passes the page map through', () async {
    fake.jsHandler = (script) => script.contains('outline')
        ? jsonEncode({'ok': true, 'outline': 'main (3 links)\n  h1: Feed'})
        : jsonEncode({'ok': true, 'url': 'x'});
    final result = await run({'action': 'outline'});
    expect(result['outline'], contains('h1: Feed'));
  });
}
