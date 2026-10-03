import 'dart:async';

import 'package:Kelivo/core/services/browser/browser_handoffs.dart';
import 'package:Kelivo/core/services/browser/browser_http_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebViewController controller;
  late FakeWebViewController fake;
  late BrowserHttpAuth auth;
  setUp(() {
    installFakeWebViewPlatform();
    controller = WebViewController();
    fake = controller.platform as FakeWebViewController;
    fake.autoFinish = false;
    auth = BrowserHttpAuth(
      origin: Uri.parse('http://127.0.0.1:4321/'),
      username: 'opencode',
      password: 'test-password-of-at-least-32-characters',
    );
  });

  Future<void> loaded() async {
    await Future.doWhile(() async {
      await Future<void>.value();
      return fake.pending.isEmpty;
    });
  }

  HttpAuthRequest challenge({
    String host = '127.0.0.1',
    String realm = 'Secure Area',
    required void Function(WebViewCredential) proceed,
    required void Function() cancel,
  }) => HttpAuthRequest(
    host: host,
    realm: realm,
    onProceed: proceed,
    onCancel: cancel,
  );

  test('native cached auth may finish without a new challenge', () async {
    final booting = auth.bootstrap(controller);
    await loaded();
    fake.startNext();
    fake.finishNext();
    await booting;
    fake.simulateHttpAuthRequest(
      challenge(
        proceed: (_) => fail('cached bootstrap retained credentials'),
        cancel: () {},
      ),
    );
  });

  test(
    'stopping the server revokes a pending handoff and future bootstraps',
    () async {
      final booting = auth.bootstrap(controller);
      final rejected = expectLater(
        booting,
        throwsA(isA<BrowserHttpAuthException>()),
      );
      await loaded();
      fake.startNext();
      auth.dispose();
      var cancelled = false;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('stopped server received credentials'),
          cancel: () => cancelled = true,
        ),
      );
      await rejected;
      expect(cancelled, isTrue);
      await expectLater(
        auth.bootstrap(controller),
        throwsA(isA<BrowserHttpAuthException>()),
      );
    },
  );

  test(
    'JS-disabled JSON bootstrap authenticates once before normal browser',
    () async {
      final booting = auth.bootstrap(controller);
      await loaded();
      expect(fake.loadedUrls, ['http://127.0.0.1:4321/session']);
      expect(fake.javaScriptMode, JavaScriptMode.disabled);
      expect(fake.javaScriptChannels, isEmpty);
      fake.startNext();
      var proceeded = 0;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (credential) {
            proceeded++;
            expect(credential.user, 'opencode');
            expect(
              credential.password,
              'test-password-of-at-least-32-characters',
            );
          },
          cancel: () => fail('the sole expected challenge was cancelled'),
        ),
      );
      fake.finishNext();
      await booting;
      expect(proceeded, 1);
      var cancelled = 0;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('credentials outlived bootstrap'),
          cancel: () => cancelled++,
        ),
      );
      expect(cancelled, 1);
    },
  );

  for (final invalid in ['host', 'realm', 'before-start']) {
    test('rejects challenge with $invalid and releases credentials', () async {
      final booting = auth.bootstrap(controller);
      final rejected = expectLater(
        booting,
        throwsA(isA<BrowserHttpAuthException>()),
      );
      await loaded();
      if (invalid != 'before-start') fake.startNext();
      var cancelled = 0;
      fake.simulateHttpAuthRequest(
        challenge(
          host: invalid == 'host' ? 'foreign.test' : '127.0.0.1',
          realm: invalid == 'realm' ? 'foreign realm' : 'Secure Area',
          proceed: (_) => fail('unexpected credentials'),
          cancel: () => cancelled++,
        ),
      );
      await rejected;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('credentials retained after rejection'),
          cancel: () => cancelled++,
        ),
      );
      expect(cancelled, 2);
    });
  }

  test('consumes credentials before synchronous challenge reentry', () async {
    final booting = auth.bootstrap(controller);
    final rejected = expectLater(
      booting,
      throwsA(isA<BrowserHttpAuthException>()),
    );
    await loaded();
    fake.startNext();
    var cancelled = false;
    fake.simulateHttpAuthRequest(
      challenge(
        proceed: (_) => fake.simulateHttpAuthRequest(
          challenge(
            proceed: (_) => fail('credential reused'),
            cancel: () => cancelled = true,
          ),
        ),
        cancel: () => fail('first challenge'),
      ),
    );
    await rejected;
    expect(cancelled, isTrue);
  });

  for (final url in [
    'http://127.0.0.1:4322/session',
    'http://127.0.0.1:4321/',
    'http://127.0.0.1:4321/session?redirect=1',
    'https://127.0.0.1:4321/session',
    'http://foreign.test:4321/session',
  ]) {
    test('blocks navigation outside the exact bootstrap URL: $url', () async {
      final booting = auth.bootstrap(controller);
      final rejected = expectLater(
        booting,
        throwsA(isA<BrowserHttpAuthException>()),
      );
      await loaded();
      expect(
        await fake.simulateNavigationRequest(url),
        NavigationDecision.prevent,
      );
      await rejected;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('redirect received credentials'),
          cancel: () {},
        ),
      );
    });
  }

  test(
    'unexpected committed redirect fails without sending credentials',
    () async {
      final booting = auth.bootstrap(controller);
      final rejected = expectLater(
        booting,
        throwsA(isA<BrowserHttpAuthException>()),
      );
      await loaded();
      fake.simulateCommittedNavigation('http://127.0.0.1:4322/session');
      await rejected;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('redirect received credentials'),
          cancel: () {},
        ),
      );
    },
  );

  test('HTTP errors, including a wrong password, fail closed', () async {
    final booting = auth.bootstrap(controller);
    final rejected = expectLater(
      booting,
      throwsA(isA<BrowserHttpAuthException>()),
    );
    await loaded();
    fake.startNext();
    fake.simulateHttpAuthRequest(challenge(proceed: (_) {}, cancel: () {}));
    fake.simulateHttpError(const HttpResponseError());
    fake.finishNext();
    await rejected;
  });

  test(
    'timeout releases credentials even when native load never resolves',
    () async {
      fake.onLoadRequest = (_) => Completer<void>().future;
      await expectLater(
        auth.bootstrap(controller, timeout: Duration.zero),
        throwsA(isA<BrowserHttpAuthException>()),
      );
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('timeout retained credentials'),
          cancel: () {},
        ),
      );
    },
  );

  test(
    'ordinary delegate always cancels challenges after any replacement',
    () async {
      await BrowserHandoffs.instance.setNavigationDelegate(
        controller,
        NavigationDelegate(
          onHttpAuthRequest: (request) => fail('ordinary auth'),
        ),
      );
      var cancelled = false;
      fake.simulateHttpAuthRequest(
        challenge(
          proceed: (_) => fail('ordinary browser auth'),
          cancel: () => cancelled = true,
        ),
      );
      expect(cancelled, isTrue);
    },
  );
}
