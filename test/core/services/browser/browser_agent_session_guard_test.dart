import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/api/generation/tool_result_images.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
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
      // A point probe says where the point is on the visible page.
      return jsonEncode({
        'ok': true,
        'url': 'https://example.com/a',
        'fx': 0.1,
        'fy': 0.1,
      });
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

  test('screenshot saves the viewport and reaches the model as an image, '
      'keeping only the newest pictures', () async {
    final fake = await attach();
    fake.jsHandler = (script) => script.contains('innerWidth')
        ? jsonEncode({'width': 412, 'height': 800})
        : jsonEncode({'ok': true, 'url': 'https://example.com/a'});
    final dir = await Directory.systemTemp.createTemp('browser-shots');
    addTearDown(() => dir.delete(recursive: true));
    final originalCapture = session.captureBytes;
    final originalDirectory = session.screenshotDirectory;
    addTearDown(() {
      session
        ..captureBytes = originalCapture
        ..screenshotDirectory = originalDirectory;
    });
    session
      ..captureBytes = ((_) async => Uint8List.fromList([0xff, 0xd8, 1, 2]))
      ..screenshotDirectory = (() async => dir);

    final raw = await BrowserAgentTool.execute({'action': 'screenshot'});
    final shot = jsonDecode(raw) as Map<String, dynamic>;
    expect(shot['ok'], isTrue);
    expect(shot['viewport'], {'width': 412, 'height': 800});
    expect(File(shot['screenshot'] as String).readAsBytesSync(), [
      0xff,
      0xd8,
      1,
      2,
    ]);

    final forModel = BrowserAgentTool.forModel(raw) as ClientToolResult;
    final text = jsonDecode(forModel.content) as Map<String, dynamic>;
    expect(text['screenshot'], 'attached');
    final images = await loadToolResultImages(forModel.metadata);
    expect(images.single.mime, 'image/jpeg');
    expect(base64Decode(images.single.base64), [0xff, 0xd8, 1, 2]);

    // A flag on another action attaches a picture taken after it.
    final scrolled =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'scroll',
                'direction': 'down',
                'screenshot': true,
              }),
            )
            as Map<String, dynamic>;
    expect(scrolled['screenshot'], isA<String>());

    // Results without a picture stay plain text.
    expect(BrowserAgentTool.forModel('{"ok":true}'), '{"ok":true}');

    for (var i = 0; i < BrowserAgentSession.keptScreenshots + 3; i++) {
      await session.screenshot();
    }
    expect(
      dir.listSync().whereType<File>().length,
      BrowserAgentSession.keptScreenshots,
    );
  });

  test(
    'fetch runs inside the page with its login and returns the text',
    () async {
      final fake = await attach();
      final started = <String>[];
      var polls = 0;
      fake.jsHandler = (script) {
        if (script.contains('credentials')) {
          started.add(script);
          return jsonEncode({'started': true});
        }
        if (script.contains('__moruFetch') && script.contains('slot.done')) {
          polls++;
          if (polls < 2) return jsonEncode({'done': false});
          return jsonEncode({
            'done': true,
            'ok': true,
            'status': 200,
            'url': 'https://example.com/api/items',
            'content_type': 'application/json',
            'text': '[1,2]',
            'total_chars': 5,
            'truncated': false,
          });
        }
        return jsonEncode({'ok': true, 'url': 'https://example.com/a'});
      };

      final result =
          jsonDecode(
                await BrowserAgentTool.execute({
                  'action': 'fetch',
                  'url': '/api/items',
                  'headers': {'Accept': 'application/json'},
                }),
              )
              as Map<String, dynamic>;
      expect(result['ok'], isTrue);
      expect(result['text'], '[1,2]');
      expect(result.containsKey('done'), isFalse);
      // A path resolves against the open page; the login goes along.
      expect(started.single, contains('"https://example.com/api/items"'));
      expect(started.single, contains('"GET"'));
      expect(started.single, contains('"Accept":"application/json"'));

      final bad =
          jsonDecode(
                await BrowserAgentTool.execute({
                  'action': 'fetch',
                  'url': 'ftp://example.com/x',
                }),
              )
              as Map<String, dynamic>;
      expect(bad['error'], 'invalid_url');
    },
  );

  test('a click at a point is a real tap at its place on the visible page; '
      'without the Android WebView it falls back to a script click', () async {
    final fake = await attach();
    final scripts = <String>[];
    fake.jsHandler = (script) {
      scripts.add(script);
      if (script.contains('captcha_frames')) {
        return jsonEncode({'cloudflare': false, 'captcha_frames': 0});
      }
      return jsonEncode({
        'ok': true,
        'x': 100,
        'y': 200,
        'fx': 0.25,
        'fy': 0.5,
        'tag': 'a',
        'text': 'Search',
      });
    };
    final taps = <(double, double)>[];
    final originalTap = session.nativeTap;
    addTearDown(() => session.nativeTap = originalTap);
    session.nativeTap = (_, fx, fy) async {
      taps.add((fx, fy));
      return true;
    };

    final tapped =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'click',
                'x': 100,
                'y': 200,
              }),
            )
            as Map<String, dynamic>;
    expect(taps, [(0.25, 0.5)]);
    expect(tapped['trusted'], isTrue);
    expect(tapped['tag'], 'a');
    expect(tapped.containsKey('fx'), isFalse);
    // Only the probe ran in the page: no script click on top of the tap.
    expect(scripts.any((s) => s.contains('const mode = "click"')), isFalse);

    session.nativeTap = (_, _, _) async => false;
    scripts.clear();
    final scripted =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'click',
                'x': 100,
                'y': 200,
              }),
            )
            as Map<String, dynamic>;
    expect(scripted['ok'], isTrue);
    expect(scripted.containsKey('trusted'), isFalse);
    expect(scripts.any((s) => s.contains('const mode = "click"')), isTrue);
  });

  test('press_key is a real key press when the WebView takes it', () async {
    final fake = await attach();
    fake.jsHandler = (_) => jsonEncode({'ok': true, 'url': 'x'});
    final keys = <String>[];
    final originalKey = session.nativeKey;
    addTearDown(() => session.nativeKey = originalKey);
    session.nativeKey = (_, key) async {
      keys.add(key);
      return true;
    };
    final pressed =
        jsonDecode(
              await BrowserAgentTool.execute({
                'action': 'press_key',
                'key': 'Enter',
              }),
            )
            as Map<String, dynamic>;
    expect(keys, ['Enter']);
    expect(pressed['trusted'], isTrue);
  });

  test('opening a link that turns into a download ends the wait', () async {
    await attach();
    final fake = FakeWebViewPlatform.lastCreated!;
    // The download: no page starts or finishes.
    fake.autoFinish = false;
    final opening = session.load(Uri.parse('https://example.com/file.pdf'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    session.downloadStarted('https://example.com/file.pdf');
    await opening.timeout(const Duration(seconds: 2));
    fake.pending.clear();
    fake.autoFinish = true;
  });
}
