import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'fake_webview_platform.dart';

void main() {
  setUp(installFakeWebViewPlatform);

  test('loadRequest fires onPageStarted then onPageFinished', () async {
    final controller = WebViewController();
    final started = <String>[];
    final finished = <String>[];
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: started.add,
        onPageFinished: finished.add,
      ),
    );

    await controller.loadRequest(Uri.parse('https://example.com/a'));

    expect(started, ['https://example.com/a']);
    expect(finished, ['https://example.com/a']);
    expect(await controller.currentUrl(), 'https://example.com/a');
  });

  test('native goBack/goForward walk the fake history', () async {
    final controller = WebViewController();
    final finished = <String>[];
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: finished.add),
    );

    await controller.loadRequest(Uri.parse('https://example.com/a'));
    await controller.loadRequest(Uri.parse('https://example.com/b'));
    expect(await controller.canGoBack(), isTrue);

    await controller.goBack();
    expect(await controller.currentUrl(), 'https://example.com/a');
    expect(await controller.canGoForward(), isTrue);

    await controller.goForward();
    expect(await controller.currentUrl(), 'https://example.com/b');
    expect(finished, [
      'https://example.com/a',
      'https://example.com/b',
      'https://example.com/a',
      'https://example.com/b',
    ]);
  });

  test('web resource errors are delivered to the delegate', () async {
    final controller = WebViewController();
    WebResourceError? seen;
    await controller.setNavigationDelegate(
      NavigationDelegate(onWebResourceError: (e) => seen = e),
    );
    final platform = controller.platform as FakeWebViewController;

    platform.simulateWebResourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'net::ERR_NAME_NOT_RESOLVED',
        isForMainFrame: true,
      ),
    );

    expect(seen?.isForMainFrame, isTrue);
    expect(seen?.description, 'net::ERR_NAME_NOT_RESOLVED');
  });
}
