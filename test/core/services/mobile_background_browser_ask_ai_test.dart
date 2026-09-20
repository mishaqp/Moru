import 'package:Kelivo/core/models/mobile_background_settings.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `visibleBrowserAskAiTask` is the hook `finish()` asks so a browser
/// Ask-AI run's own completion notification can be suppressed only when
/// the browser's own UI is already showing (or about to show) that exact
/// run's result -- never from "the browser is open" alone, which would
/// also suppress a notification for a different run or a browser covered
/// by another screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.mobile_background.browser_ask_ai');
  final notifications = <Map<String, String?>>[];
  late MobileBackgroundCoordinator coordinator;
  late AppLocalizations l10n;

  setUp(() async {
    notifications.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'sync' || call.method == 'getStatus'
              ? <String, dynamic>{'notificationsAuthorized': false}
              : null;
        });
    coordinator = MobileBackgroundCoordinator(
      channel: channel,
      platform: TargetPlatform.android,
      notificationSender: ({required conversationId, title, body}) async {
        notifications.add({'id': conversationId, 'title': title, 'body': body});
      },
    );
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await coordinator.configure(
      const MobileBackgroundSettings(notificationsEnabled: true),
      l10n,
    );
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
  });

  tearDown(() async {
    await coordinator.flush();
    coordinator.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> start(String id, {required String conversationId}) =>
      coordinator.start(
        id: id,
        conversationId: conversationId,
        title: 'Chat $id',
        cancel: () async {},
      );

  test('foreground + the browser\'s own visible Ask-AI surface + the matching '
      'run suppresses the notification', () async {
    coordinator.visibleBrowserAskAiTask = (taskId, conversationId) =>
        taskId == 'run-1' && conversationId == 'conv-1';
    await start('run-1', conversationId: 'conv-1');

    await coordinator.finish('run-1', BackgroundTaskOutcome.completed);

    expect(notifications, isEmpty);
  });

  test('background (not foreground) still notifies even if visible-check '
      'would say yes', () async {
    coordinator.visibleBrowserAskAiTask = (_, _) => true;
    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    await start('run-1', conversationId: 'conv-1');

    await coordinator.finish('run-1', BackgroundTaskOutcome.completed);

    expect(notifications, isNotEmpty);
  });

  test('a different run (task id) than the one the browser is showing still '
      'notifies', () async {
    coordinator.visibleBrowserAskAiTask = (taskId, conversationId) =>
        taskId == 'run-shown' && conversationId == 'conv-1';
    await start('run-other', conversationId: 'conv-1');

    await coordinator.finish('run-other', BackgroundTaskOutcome.completed);

    expect(notifications, isNotEmpty);
  });

  test(
    'a matching run id but a different conversation still notifies',
    () async {
      coordinator.visibleBrowserAskAiTask = (taskId, conversationId) =>
          taskId == 'run-1' && conversationId == 'conv-1';
      await start('run-1', conversationId: 'conv-2');

      await coordinator.finish('run-1', BackgroundTaskOutcome.completed);

      expect(notifications, isNotEmpty);
    },
  );

  test('the browser covered by another screen (visible-check itself says no) '
      'still notifies', () async {
    // Models BrowserAgentSession.consumeVisibleAskAiTask returning false
    // because isRouteCurrent is false, even though the run/conversation
    // ids would otherwise match.
    coordinator.visibleBrowserAskAiTask = (_, _) => false;
    await start('run-1', conversationId: 'conv-1');

    await coordinator.finish('run-1', BackgroundTaskOutcome.completed);

    expect(notifications, isNotEmpty);
  });

  test('no visible-browser hook registered at all behaves exactly as before '
      '(falls through to the normal visibleConversation check)', () async {
    coordinator.visibleConversation = () => 'conv-1';
    await start('run-1', conversationId: 'conv-1');

    await coordinator.finish('run-1', BackgroundTaskOutcome.completed);

    expect(notifications, isEmpty);
  });

  test(
    'the visible-browser check is asked with this exact run\'s task id even '
    'when the browser is no longer tracking any "active" request UI-side -- '
    'finish() never substitutes its own notion of "current" request',
    () async {
      final askedWith = <String>[];
      coordinator.visibleBrowserAskAiTask = (taskId, conversationId) {
        askedWith.add(taskId);
        // Simulates AskAiPanelController having already reset its own
        // activeRequestId to null by the time finish() runs -- the
        // decision must still be reachable through the task id alone.
        return taskId == 'run-1' && conversationId == 'conv-1';
      };
      await start('run-1', conversationId: 'conv-1');

      await coordinator.finish('run-1', BackgroundTaskOutcome.completed);

      expect(askedWith, ['run-1']);
      expect(notifications, isEmpty);
    },
  );
}
