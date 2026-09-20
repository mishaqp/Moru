import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

/// `consumeVisibleAskAiTask` is what `MobileBackgroundCoordinator.finish()`
/// asks to decide whether a browser Ask-AI run's own completion should
/// suppress the usual "generation finished" system notification. It must
/// say yes only when all three hold at once: the task was actually started
/// by this session, the conversation matches, and the browser's own route
/// is the current, visible one right now -- never from "the browser is
/// merely attached" alone, since a session stays attached while covered by
/// another screen.
void main() {
  final session = BrowserAgentSession.instance;

  setUp(() {
    installFakeWebViewPlatform();
    session.isRouteCurrent = false;
  });

  test(
    'a tracked task for the matching conversation, with the route current, '
    'is visible',
    () {
      session.trackAskAiTask('run-1', 'conv-1');
      session.isRouteCurrent = true;

      expect(session.consumeVisibleAskAiTask('run-1', 'conv-1'), isTrue);
    },
  );

  test('consuming removes the entry: a second check for the same id fails', () {
    session.trackAskAiTask('run-1', 'conv-1');
    session.isRouteCurrent = true;

    expect(session.consumeVisibleAskAiTask('run-1', 'conv-1'), isTrue);
    expect(session.consumeVisibleAskAiTask('run-1', 'conv-1'), isFalse);
  });

  test('an untracked task id is never visible, route or not', () {
    session.isRouteCurrent = true;
    expect(session.consumeVisibleAskAiTask('unknown-run', 'conv-1'), isFalse);
  });

  test(
    'a tracked task is not visible while the browser route is covered by '
    'another screen',
    () {
      session.trackAskAiTask('run-2', 'conv-1');
      session.isRouteCurrent = false;

      expect(session.consumeVisibleAskAiTask('run-2', 'conv-1'), isFalse);
    },
  );

  test(
    'a tracked task is not visible for a different conversation than it '
    'was started from',
    () {
      session.trackAskAiTask('run-3', 'conv-1');
      session.isRouteCurrent = true;

      expect(session.consumeVisibleAskAiTask('run-3', 'conv-2'), isFalse);
    },
  );

  test('unregister() clears tracked tasks and route visibility', () {
    final controller = WebViewController();
    session.register(controller);
    session.trackAskAiTask('run-4', 'conv-1');
    session.isRouteCurrent = true;

    session.unregister(controller);

    expect(session.isRouteCurrent, isFalse);
    expect(session.consumeVisibleAskAiTask('run-4', 'conv-1'), isFalse);
  });
}
