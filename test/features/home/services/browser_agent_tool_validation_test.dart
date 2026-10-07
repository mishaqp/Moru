import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_agent_tool.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = BrowserAgentSession.instance;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installFakeWebViewPlatform();
    final onPageLoaded = session.onPageLoaded;
    final onVisit = session.onVisit;
    session
      ..onPageLoaded = (_, _) {}
      ..onVisit = (_, _) {};
    addTearDown(() {
      session
        ..onPageLoaded = onPageLoaded
        ..onVisit = onVisit;
    });
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<FakeWebViewController> attach() async {
    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(controller, onClose: () async {});
    addTearDown(() => session.unregister(controller));
    await session.load(Uri.parse('https://example.com/a'));
    return FakeWebViewPlatform.lastCreated!;
  }

  for (final value in <Object?>[
    null,
    42,
    true,
    <String>['text'],
  ]) {
    test(
      'type rejects non-string text $value before touching a field',
      () async {
        final fake = await attach();
        final scripts = <String>[];
        fake.jsHandler = (script) {
          scripts.add(script);
          return jsonEncode({'ok': true});
        };
        final result =
            jsonDecode(
                  await BrowserAgentTool.execute({
                    'action': 'type',
                    'element_id': 1,
                    'text': value,
                  }),
                )
                as Map<String, dynamic>;
        expect(result['error'], 'invalid_arguments');
        expect(
          scripts.any((script) => script.contains('const text = ')),
          isFalse,
        );
      },
    );
  }

  test('type requires text instead of clearing a field when omitted', () async {
    final fake = await attach();
    final scripts = <String>[];
    fake.jsHandler = (script) {
      scripts.add(script);
      return jsonEncode({'ok': true});
    };
    final result =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'type',
                'element_id': 1,
              }),
            )
            as Map<String, dynamic>;
    expect(result['error'], 'invalid_arguments');
    expect(scripts.any((script) => script.contains('const text = ')), isFalse);
  });

  test('type permits empty text to intentionally clear a field', () async {
    final fake = await attach();
    final scripts = <String>[];
    fake.jsHandler = (script) {
      scripts.add(script);
      return jsonEncode({'ok': true});
    };
    final result =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'type',
                'element_id': 1,
                'text': '',
              }),
            )
            as Map<String, dynamic>;
    expect(result['ok'], isTrue);
    expect(
      scripts.any((script) => script.contains('const text = "";')),
      isTrue,
    );
  });

  test(
    'nullable optional fields keep normal browser typing behavior',
    () async {
      final fake = await attach();
      final scripts = <String>[];
      fake.jsHandler = (script) {
        scripts.add(script);
        return jsonEncode({'ok': true});
      };
      final result =
          jsonDecode(
                await BrowserAgentTool.execute({
                  'action': 'type',
                  'element_id': 1,
                  'text': '  keep whitespace  ',
                  'human': null,
                  'screenshot': null,
                  'url': null,
                  'x': null,
                  'y': null,
                }),
              )
              as Map<String, dynamic>;
      expect(result['ok'], isTrue);
      expect(
        scripts.any(
          (script) => script.contains('const text = "  keep whitespace  ";'),
        ),
        isTrue,
      );
      expect(result.containsKey('screenshot'), isFalse);
    },
  );

  test('fetch caps the returned text at the schema maximum', () async {
    final fake = await attach();
    Map<String, dynamic>? answer;
    fake.jsHandlerAsync = (script) async {
      if (script.contains('const slot = store[') && script.contains('fetch(')) {
        // Execute the real page script against a fixed response. No browser or
        // network is needed, and the assertion observes the actual result cap.
        final execution = await Process.run('node', [
          '-e',
          '''
global.window = {};
global.fetch = async () => ({
  status: 200,
  url: 'https://example.com/data',
  headers: {get: (name) => name === 'content-type' ? 'text/plain' : null},
  text: async () => 'x'.repeat(100000)
});
const started = global.eval(${jsonEncode(script)});
setImmediate(() => process.stdout.write(JSON.stringify({
  started: JSON.parse(started),
  answer: Object.values(window.__moruFetch)[0]
})));
''',
        ]);
        expect(execution.exitCode, 0, reason: execution.stderr.toString());
        final evaluated = jsonDecode(execution.stdout as String) as Map;
        answer = Map<String, dynamic>.from(evaluated['answer'] as Map);
        return jsonEncode(evaluated['started']);
      }
      if (script.contains('delete store[')) return jsonEncode(answer);
      return jsonEncode({'ok': true});
    };
    final result =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'fetch',
                'url': '/data',
                'max_chars': 200000,
              }),
            )
            as Map<String, dynamic>;
    expect(result['ok'], isTrue);
    expect((result['text'] as String).length, 65536);
    expect(result['total_chars'], 100000);
    expect(result['truncated'], isTrue);
  });
}
