import 'dart:async';
import 'dart:convert';

import 'package:Kelivo/core/models/mobile_background_settings.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.approval_background');
  final calls = <MethodCall>[];
  late MobileBackgroundCoordinator coordinator;
  late ToolApprovalService approvals;
  late AppLocalizations l10n;
  Future<Object?> Function(MethodCall)? intercept;

  setUp(() async {
    calls.clear();
    intercept = null;
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return intercept?.call(call);
        });
    coordinator = MobileBackgroundCoordinator(
      platform: TargetPlatform.android,
      channel: channel,
    );
    approvals = ToolApprovalService();
    coordinator.bindApprovals(approvals);
    await coordinator.configure(
      const MobileBackgroundSettings(notificationsEnabled: true),
      l10n,
    );
  });

  tearDown(() async {
    approvals.dispose();
    await coordinator.flush();
    coordinator.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<ToolApprovalResult> ask(String chat, String run) =>
      approvals.requestApproval(
        toolCallId: 'raw-api-key-sentinel',
        toolName: 'secret-command',
        arguments: const {'command': 'private-env-sentinel'},
        conversationId: chat,
        owner: ToolApprovalOwner(
          conversationId: chat,
          generationRunId: run,
          assistantMessageId: 'message-$run',
          isActive: () => true,
        ),
      );

  Map lastApprovals() =>
      calls.lastWhere((call) => call.method == 'syncApprovals').arguments
          as Map;

  Future<Map> action(ToolApprovalRequest request, String choice) async {
    final response = Completer<Map>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('approvalAction', {
              'approvalId': request.approvalId,
              'conversationId': request.conversationId,
              'generationRunId': request.generationRunId,
              'assistantMessageId': request.assistantMessageId,
              'action': choice,
            }),
          ),
          (data) => response.complete(
            const StandardMethodCodec().decodeEnvelope(data!) as Map,
          ),
        );
    return response.future;
  }

  test(
    'native DTO contains only generated targets and safe localized text',
    () async {
      final pending = ask('chat-a', 'run-a');
      await coordinator.flush();
      final snapshot = lastApprovals();
      expect(snapshot['version'], 1);
      final item = (snapshot['pending'] as List).single as Map;
      expect(item['conversationId'], 'chat-a');
      expect(item['generationRunId'], 'run-a');
      expect(item['assistantMessageId'], 'message-run-a');
      expect(
        item.keys,
        unorderedEquals([
          'approvalId',
          'conversationId',
          'generationRunId',
          'assistantMessageId',
          'title',
          'body',
        ]),
      );
      final text = jsonEncode(snapshot);
      expect(text, isNot(contains('raw-api-key-sentinel')));
      expect(text, isNot(contains('private-env-sentinel')));
      expect(text, isNot(contains('secret-command')));
      expect(
        calls.map((call) => call.method),
        isNot(contains('requestPermission')),
      );
      approvals.deny('raw-api-key-sentinel', conversationId: 'chat-a');
      expect((await pending).approved, isFalse);
    },
  );

  test(
    'report consent stays in the chat instead of generic notification buttons',
    () async {
      final pending = approvals.requestApproval(
        toolCallId: 'report',
        toolName: 'report_problem',
        arguments: {},
        conversationId: 'chat',
        owner: ToolApprovalOwner(
          conversationId: 'chat',
          generationRunId: 'run',
          assistantMessageId: 'message',
          isActive: () => true,
        ),
      );
      await coordinator.flush();
      expect(lastApprovals()['pending'], isEmpty);
      expect(approvals.pendingRequests, hasLength(1));
      final request = approvals.pendingRequests.single;
      expect(await action(request, 'allow'), {'status': 'stale'});
      expect(approvals.pendingRequests, hasLength(1));
      approvals.approve('report', conversationId: 'chat');
      expect((await pending).approved, isTrue);
    },
  );

  test(
    'native action reaches the existing gate and duplicates are stale',
    () async {
      final a = ask('a', 'run-a');
      final b = ask('b', 'run-b');
      await coordinator.flush();
      final requests = approvals.pendingRequests;
      expect(await action(requests[0], 'allow'), {'status': 'resolved'});
      expect((await a).approved, isTrue);
      expect(approvals.pendingRequests.single, same(requests[1]));
      expect(await action(requests[0], 'deny'), {'status': 'stale'});
      expect(await action(requests[1], 'deny'), {'status': 'resolved'});
      expect((await b).approved, isFalse);
      await coordinator.flush();
      expect(lastApprovals()['pending'], isEmpty);
    },
  );

  test(
    'pending approval appears on leaving its visible chat and clears on return',
    () async {
      var visible = 'a';
      coordinator.visibleConversation = () => visible;
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final pending = ask('a', 'run-a');
      await coordinator.flush();
      expect(lastApprovals()['pending'], isEmpty);
      visible = 'b';
      coordinator.reconcileApprovals();
      await coordinator.flush();
      expect(lastApprovals()['pending'] as List, hasLength(1));
      visible = 'a';
      coordinator.reconcileApprovals();
      await coordinator.flush();
      expect(lastApprovals()['pending'], isEmpty);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      await coordinator.flush();
      expect(lastApprovals()['pending'] as List, hasLength(1));
      approvals.cancelAll();
      expect((await pending).approved, isFalse);
    },
  );

  test(
    'action acknowledgement does not wait behind an in-flight mirror',
    () async {
      final blocked = Completer<void>();
      var block = true;
      intercept = (call) async {
        if (call.method == 'syncApprovals' && block) await blocked.future;
        return null;
      };
      final pending = ask('a', 'run-a');
      final request = approvals.pendingRequests.single;
      await Future<void>.delayed(Duration.zero);
      expect(await action(request, 'allow'), {'status': 'resolved'});
      expect((await pending).approved, isTrue);
      block = false;
      blocked.complete();
      await coordinator.flush();
      expect(lastApprovals()['pending'], isEmpty);
    },
  );

  test(
    'privacy changes queued snapshots before crossing native boundary',
    () async {
      final blocked = Completer<void>();
      var once = true;
      intercept = (call) async {
        if (call.method == 'syncApprovals' && once) {
          once = false;
          await blocked.future;
        }
        return null;
      };
      final pending = ask('a', 'run-a');
      await Future<void>.delayed(Duration.zero);
      final configured = coordinator.configure(
        const MobileBackgroundSettings(
          notificationsEnabled: true,
          privacyMode: true,
        ),
        l10n,
      );
      approvals.cancelAll();
      blocked.complete();
      await configured;
      await coordinator.flush();
      expect((lastApprovals()['settings'] as Map)['privacyMode'], isTrue);
      expect(lastApprovals()['pending'], isEmpty);
      expect((await pending).approved, isFalse);
    },
  );

  test(
    'durable result uses captured run and message before final release',
    () async {
      await coordinator.start(
        id: 'run-a',
        conversationId: 'a',
        assistantMessageId: 'message-a',
        title: 'A',
        cancel: () async {},
      );
      await coordinator.finish(
        'run-a',
        BackgroundTaskOutcome.completed,
        replyPreview: 'Result preview',
      );
      final resultIndex = calls.indexWhere(
        (call) => call.method == 'showResult',
      );
      expect(resultIndex, greaterThanOrEqualTo(0));
      final result = calls[resultIndex].arguments as Map;
      expect(result['generationRunId'], 'run-a');
      expect(result['assistantMessageId'], 'message-a');
      expect(result['body'], 'Result preview');
      expect(
        (calls.skip(resultIndex + 1).last.arguments as Map)['tasks'],
        isEmpty,
      );
      await coordinator.start(
        id: 'run-b',
        conversationId: 'b',
        title: 'B',
        cancel: () async {},
      );
      await coordinator.finish(
        'run-b',
        BackgroundTaskOutcome.failed,
        resultPersisted: false,
      );
      expect(calls.where((call) => call.method == 'showResult'), hasLength(1));
    },
  );

  test(
    'disabling alerts invalidates old notification actions without denying the chat gate',
    () async {
      final pending = ask('a', 'run-a');
      final request = approvals.pendingRequests.single;
      await coordinator.flush();
      await coordinator.configure(const MobileBackgroundSettings(), l10n);
      expect(await action(request, 'allow'), {'status': 'stale'});
      expect(approvals.pendingRequests.single, same(request));
      approvals.deny(request.toolCallId, conversationId: 'a');
      expect((await pending).approved, isFalse);
    },
  );

  test(
    'replacement provider does not revive decisions from the previous process gate',
    () async {
      final oldFuture = ask('a', 'old');
      final previous = approvals.pendingRequests.single;
      approvals.cancelAll();
      expect((await oldFuture).approved, isFalse);
      final fresh = ToolApprovalService();
      coordinator.bindApprovals(fresh);
      final pending = fresh.requestApproval(
        toolCallId: previous.toolCallId,
        toolName: 'tool',
        arguments: const {},
        conversationId: 'a',
        owner: ToolApprovalOwner(
          conversationId: 'a',
          generationRunId: 'new',
          assistantMessageId: 'new-message',
          isActive: () => true,
        ),
      );
      expect(await action(previous, 'allow'), {'status': 'stale'});
      expect(fresh.pendingRequests, hasLength(1));
      fresh.dispose();
      expect((await pending).approved, isFalse);
      coordinator.bindApprovals(approvals);
    },
  );

  test(
    'permission grant refresh mirrors live requests without a prompt or old decisions',
    () async {
      final pending = ask('a', 'run-a');
      await coordinator.flush();
      final revision = lastApprovals()['revision'] as int;
      intercept = (call) async => call.method == 'getStatus'
          ? {'notificationsAuthorized': true, 'approvalChannelEnabled': true}
          : null;
      await coordinator.refreshStatus();
      await coordinator.flush();
      expect(lastApprovals()['revision'] as int, greaterThan(revision));
      expect(lastApprovals()['pending'] as List, hasLength(1));
      expect(
        calls.map((call) => call.method),
        isNot(contains('requestPermission')),
      );
      approvals.cancelAll();
      expect((await pending).approved, isFalse);
    },
  );

  test(
    'background shell outcome is generic and uses the actual job identity once',
    () async {
      await coordinator.reportBackgroundShellResult(
        id: 'job-a',
        conversationId: 'a',
        succeeded: false,
      );
      await coordinator.reportBackgroundShellResult(
        id: 'job-a',
        conversationId: 'a',
        succeeded: false,
      );
      final results = calls
          .where((call) => call.method == 'showResult')
          .toList();
      expect(results, hasLength(1));
      final result = results.single.arguments as Map;
      expect(result['generationRunId'], 'job-a');
      expect(result['assistantMessageId'], '');
      expect(result['body'], 'Background command failed');
      expect(result['privateBody'], 'Background command failed');
      expect(result['outcome'], 'failed');
    },
  );
}
