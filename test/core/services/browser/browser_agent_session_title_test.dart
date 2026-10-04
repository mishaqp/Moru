import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';

import '../../../support/fake_webview_platform.dart';

class _TitlePlatform extends FakeWebViewPlatform {
  late _TitleController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _TitleController(params);
}

class _TitleController extends FakeWebViewController {
  _TitleController(super.params);

  final reads = <Completer<String?>>[];

  @override
  Future<String?> getTitle() {
    final read = Completer<String?>();
    reads.add(read);
    return read.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = BrowserAgentSession.instance;

  test(
    'a late authentication title cannot be saved under the next page',
    () async {
      final platform = _TitlePlatform();
      WebViewPlatform.instance = platform;
      final controller = WebViewController();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: session.pageStarted,
          onPageFinished: session.pageFinished,
        ),
      );
      final originalLoaded = session.onPageLoaded;
      final originalVisit = session.onVisit;
      final visits = <(String, String?)>[];
      session
        ..onPageLoaded = (_, _) {}
        ..onVisit = (url, title) {
          visits.add((url, title));
        }
        ..register(controller, onClose: () async {});
      addTearDown(() {
        session
          ..unregister(controller)
          ..onPageLoaded = originalLoaded
          ..onVisit = originalVisit;
      });
      const authUrl = 'https://auth.openai.com/authorize?code=synthetic';
      const normalUrl = 'https://example.com/normal';
      await session.load(Uri.parse(authUrl));
      await session.load(Uri.parse(normalUrl));
      expect(platform.controller.reads, hasLength(2));

      platform.controller.reads.last.complete('Normal page');
      await pumpEventQueue();
      platform.controller.reads.first.complete('Private auth title');
      await pumpEventQueue();

      expect(session.tabs.value.single.title, 'Normal page');
      expect(visits, [(normalUrl, 'Normal page')]);
    },
  );
}
