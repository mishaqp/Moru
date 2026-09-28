import 'dart:convert';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_agent_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = BrowserAgentSession.instance;

  setUp(installFakeWebViewPlatform);

  Future<FakeWebViewController> attach() async {
    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: session.pageStarted,
        onPageFinished: session.pageFinished,
      ),
    );
    session
      ..register(controller, onClose: () async {})
      ..installDialogHandlers(controller);
    addTearDown(() => session.unregister(controller));
    await session.load(Uri.parse('https://example.com/a'));
    return FakeWebViewPlatform.lastCreated!;
  }

  test('dialogs the page opens while the model drives it are answered and '
      'reported once', () async {
    final fake = await attach();
    await fake.onAlert!(
      const JavaScriptAlertDialogRequest(message: 'Saved', url: ''),
    );
    expect(
      await fake.onConfirm!(
        const JavaScriptConfirmDialogRequest(message: 'Delete?', url: ''),
      ),
      isTrue,
    );
    expect(
      await fake.onPrompt!(
        const JavaScriptTextInputDialogRequest(
          message: 'Name',
          url: '',
          defaultText: 'Ann',
        ),
      ),
      'Ann',
    );
    expect(session.drainDialogs(), [
      {'kind': 'alert', 'message': 'Saved', 'answer': 'ok'},
      {'kind': 'confirm', 'message': 'Delete?', 'answer': 'accepted'},
      {'kind': 'prompt', 'message': 'Name', 'answer': 'Ann'},
    ]);
    expect(session.drainDialogs(), isEmpty);

    // The user answers them while looking at an idle browser page.
    session
      ..isRouteCurrent = true
      ..dialogPresenter = (kind, message, defaultText) async => 'declined';
    expect(
      await fake.onConfirm!(
        const JavaScriptConfirmDialogRequest(message: 'Leave?', url: ''),
      ),
      isFalse,
    );
    expect(session.drainDialogs(), isEmpty);
  });

  test('Stop ends a waiting action with stopped_by_user', () async {
    final fake = await attach();
    fake.jsHandler = (_) => jsonEncode({'satisfied': false});
    final running = BrowserAgentTool.execute({
      'action': 'wait_for',
      'selector': '#never',
      'timeout_ms': 30000,
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    session.requestStop();
    final result = jsonDecode(await running) as Map<String, dynamic>;
    expect(result['error'], 'stopped_by_user');
    // Nothing left to stop afterwards.
    session.requestStop();
  });

  test('a verification page refuses clicks until the user solves it', () async {
    final fake = await attach();
    var cloudflare = true;
    fake.jsHandler = (script) {
      if (script.contains('captcha_frames')) {
        return jsonEncode({
          'cloudflare': cloudflare,
          'captcha_frames': 0,
          'unusual_traffic': false,
          'text_length': 40,
        });
      }
      return jsonEncode({'ok': true, 'url': 'https://example.com/a'});
    };
    final observed =
        jsonDecode(await BrowserAgentTool.execute({'action': 'observe'}))
            as Map<String, dynamic>;
    expect(observed['challenge'], containsPair('kind', 'cloudflare'));
    expect(session.challenge.value?.blocking, isTrue);

    final refused =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'click',
                'x': 10,
                'y': 10,
              }),
            )
            as Map<String, dynamic>;
    expect(refused['error'], 'challenge_detected');

    // Solved: the check is gone, so the click goes through.
    cloudflare = false;
    final clicked =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'click',
                'x': 10,
                'y': 10,
              }),
            )
            as Map<String, dynamic>;
    expect(clicked['ok'], isTrue);
    expect(clicked.containsKey('challenge'), isFalse);
    expect(session.challenge.value, isNull);
  });
}
