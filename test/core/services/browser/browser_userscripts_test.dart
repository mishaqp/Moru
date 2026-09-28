import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_userscripts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

const _script = '''
// ==UserScript==
// @name         Dark Wiki
// @version      1.2
// @description  Dark Wikipedia
// @match        https://*.wikipedia.org/wiki/*
// @include      https://example.com/*
// @exclude      https://example.com/private*
// @grant        GM_addStyle
// ==/UserScript==
GM_addStyle('body { background: black }');
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the header says what the script is and where it runs', () {
    final script = Userscript.parse(_script, id: 'a')!;
    expect(script.name, 'Dark Wiki');
    expect(script.version, '1.2');
    expect(script.matches, ['https://*.wikipedia.org/wiki/*']);

    expect(script.runsOn('https://en.wikipedia.org/wiki/Moon'), isTrue);
    expect(script.runsOn('https://wikipedia.org/wiki/Moon'), isTrue);
    expect(script.runsOn('http://en.wikipedia.org/wiki/Moon'), isFalse);
    expect(script.runsOn('https://en.wikipedia.org/w/index.php'), isFalse);
    expect(script.runsOn('https://evilwikipedia.org/wiki/x'), isFalse);
    expect(script.runsOn('https://example.com/page'), isTrue);
    expect(script.runsOn('https://example.com/private/1'), isFalse);

    expect(Userscript.parse('alert(1)', id: 'x'), isNull);
    final any = Userscript.parse(
      '// ==UserScript==\n// @name All\n// @match <all_urls>\n'
      '// @include /^https://re\\.example/\n// ==/UserScript==\n',
      id: 'b',
    )!;
    expect(any.runsOn('https://anything.example/'), isTrue);
    expect(any.runsOn('file:///etc/passwd'), isFalse);
  });

  group('installed scripts', () {
    late Directory dir;
    late BrowserUserscripts store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('userscripts');
      store = BrowserUserscripts(directory: () async => dir);
    });

    tearDown(() => dir.delete(recursive: true));

    test('install from a link, switch off, update by name, remove; they '
        'survive a restart', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response
          ..write(request.uri.path == '/dark.user.js' ? _script : 'nope')
          ..close();
      });
      final base = 'http://127.0.0.1:${server.port}';

      // The Flutter test binding answers every HTTP request with 400; this
      // test talks to its own local server.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      final installed = await store.installFrom(
        Uri.parse('$base/dark.user.js'),
      );
      expect(installed?.name, 'Dark Wiki');
      expect(await store.installFrom(Uri.parse('$base/other.js')), isNull);

      await store.setEnabled(installed!.id, false);
      final reopened = BrowserUserscripts(directory: () async => dir);
      await reopened.load();
      expect(reopened.scripts.value.single.enabled, isFalse);
      expect(reopened.scripts.value.single.sourceUrl, '$base/dark.user.js');

      // Same name: an update, not a second script.
      await store.install(_script.replaceFirst('1.2', '1.3'));
      expect(store.scripts.value.single.version, '1.3');

      await store.remove(installed.id);
      expect(store.scripts.value, isEmpty);
      expect(File('${dir.path}/${installed.id}.user.js').existsSync(), isFalse);
    });

    test(
      'matching enabled scripts run in the page, wrapped once per page',
      () async {
        installFakeWebViewPlatform();
        final controller = WebViewController();
        final fake = FakeWebViewPlatform.lastCreated!;
        final ran = <String>[];
        fake.jsHandler = (script) {
          ran.add(script);
          return 'null';
        };
        final script = (await store.install(_script))!;

        expect(
          await store.runIn(controller, 'https://en.wikipedia.org/wiki/Moon'),
          ['Dark Wiki'],
        );
        expect(
          ran.single,
          contains("GM_addStyle('body { background: black }')"),
        );
        expect(ran.single, contains('window.__moruUserscripts'));
        expect(
          await store.runIn(controller, 'https://other.example/'),
          isEmpty,
        );

        await store.setEnabled(script.id, false);
        expect(
          await store.runIn(controller, 'https://en.wikipedia.org/wiki/Moon'),
          isEmpty,
        );
      },
    );
  });

  test('a finished page runs the user scripts of its tab', () async {
    installFakeWebViewPlatform();
    final session = BrowserAgentSession.instance;
    final loaded = <String>[];
    final original = session.onPageLoaded;
    session.onPageLoaded = (_, url) => loaded.add(url);
    addTearDown(() => session.onPageLoaded = original);
    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session.register(controller, onClose: () async {});
    addTearDown(() => session.unregister(controller));
    await session.load(Uri.parse('https://en.wikipedia.org/wiki/Moon'));
    expect(loaded, ['https://en.wikipedia.org/wiki/Moon']);
  });
}
