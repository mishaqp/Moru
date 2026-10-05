import 'dart:convert';

import 'package:Kelivo/core/services/api/tool_display_redaction.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> expectStillPending(Future<dynamic> future) async {
  var completed = false;
  future.whenComplete(() {
    completed = true;
  });
  await Future<void>.delayed(Duration.zero);
  expect(completed, isFalse);
}

void main() {
  test(
    'concurrent mini-app calls sharing an id need separate consent',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      Future<ToolApprovalResult> request() => service.requestApproval(
        toolCallId: 'same',
        toolName: 'ma_phone_control_power_save',
        conversationId: 'chat',
        arguments: const {
          'app_id': 'phone-control',
          'version': 1,
          'enabled': true,
        },
      );
      final first = request();
      final second = request();
      expect(identical(first, second), false);
      expect((await first).approved, false);
      service.approve('same', conversationId: 'chat');
      expect((await second).approved, true);
    },
  );

  test(
    'mini-app actions require explicit consent for the prepared version',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final first = service.requestApproval(
        toolCallId: 'same',
        toolName: 'ma_phone_control_power_save',
        conversationId: 'chat',
        arguments: const {
          'app_id': 'phone-control',
          'version': 1,
          'enabled': true,
        },
      );
      expect(service.pendingRequests.single.requiresExplicitConsent, true);
      final second = service.requestApproval(
        toolCallId: 'same',
        toolName: 'ma_phone_control_power_save',
        conversationId: 'chat',
        arguments: const {
          'app_id': 'phone-control',
          'version': 2,
          'enabled': true,
        },
      );
      expect((await first).approved, false);
      service.approve('same', conversationId: 'chat');
      expect((await second).approved, true);
    },
  );

  for (final toolName in ['browser_use', 'phone_control']) {
    test(
      '$toolName cannot reuse pending consent for different nested arguments',
      () async {
        final service = ToolApprovalService();
        addTearDown(service.dispose);
        final owner = ToolApprovalOwner(
          conversationId: 'chat',
          generationRunId: 'run',
          assistantMessageId: 'reply',
          isActive: _liveOwner,
        );
        final first = service.requestApproval(
          toolCallId: 'same',
          toolName: toolName,
          owner: owner,
          arguments: const {
            'action': 'eval_js',
            'steps': [
              {'code': 'read-only'},
            ],
          },
        );
        final second = service.requestApproval(
          toolCallId: 'same',
          toolName: toolName,
          owner: owner,
          arguments: const {
            'action': 'eval_js',
            'steps': [
              {'code': 'change-state'},
            ],
          },
        );
        expect(
          service.pendingRequests.single.arguments['steps'][0]['code'],
          'change-state',
        );
        expect((await first).approved, isFalse);
        await expectStillPending(second);
        service.approve('same', conversationId: 'chat');
        expect((await second).approved, isTrue);
      },
    );
  }

  test(
    'identical deep arguments reuse consent despite display redaction',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final display = ToolDisplayRedaction(
        text: (text) => text.replaceAll('PRIVATE', '[REDACTED]'),
        value: (value) =>
            jsonDecode(jsonEncode(value).replaceAll('PRIVATE', '[REDACTED]')),
      );
      late Future<ToolApprovalResult> first;
      late Future<ToolApprovalResult> second;
      await display.run(() async {
        first = service.requestApproval(
          toolCallId: 'same',
          toolName: 'browser_use',
          conversationId: 'chat',
          arguments: {
            'action': 'eval_js',
            'steps': [
              {'code': 'PRIVATE'},
            ],
          },
        );
        second = service.requestApproval(
          toolCallId: 'same',
          toolName: 'browser_use',
          conversationId: 'chat',
          arguments: {
            'steps': [
              {'code': 'PRIVATE'},
            ],
            'action': 'eval_js',
          },
        );
      });
      expect(identical(first, second), isTrue);
      expect(service.pendingRequests, hasLength(1));
      expect(
        jsonEncode(service.pendingRequests.single.arguments),
        isNot(contains('PRIVATE')),
      );
      service.approve('same', conversationId: 'chat');
      expect((await first).approved, isTrue);
      expect((await second).approved, isTrue);
    },
  );

  test('full trust still waits for missing private MCP inputs', () async {
    final service = ToolApprovalService()..setAutoApproveAll(true);
    addTearDown(service.dispose);
    final pending = service.requestApproval(
      toolCallId: 'private',
      toolName: 'manage_mcp',
      arguments: const {'action': 'add'},
      conversationId: 'chat',
      secretFields: const ['env:API_KEY'],
      secretInputOnly: true,
    );
    expect(service.pendingRequests, hasLength(1));
    expect(service.pendingRequests.single.secretInputOnly, isTrue);
    await expectStillPending(pending);
    service.approve('private', conversationId: 'chat');
    await expectStillPending(pending);
    service.approve(
      'private',
      conversationId: 'chat',
      secretValues: const {'env:API_KEY': 'PRIVATE_INPUT'},
    );
    final result = await pending;
    expect(result.approved, isTrue);
    expect(result.takeSecretValues(), {'env:API_KEY': 'PRIVATE_INPUT'});
    expect(result.takeSecretValues(), isEmpty);
    expect(service.pendingRequests, isEmpty);
  });

  test(
    'enabling full trust preserves missing private input requests',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final pending = service.requestApproval(
        toolCallId: 'private',
        toolName: 'manage_mcp',
        arguments: const {'action': 'update'},
        conversationId: 'chat',
        secretFields: const ['header:Authorization'],
      );
      final approvalId = service.pendingRequests.single.approvalId;
      expect(service.pendingRequests.single.secretInputOnly, isFalse);
      service.setAutoApproveAll(true);
      expect(service.pendingRequests.single.approvalId, approvalId);
      expect(service.pendingRequests.single.secretInputOnly, isTrue);
      await expectStillPending(pending);
      service.setAutoApproveAll(false);
      expect(service.pendingRequests.single.secretInputOnly, isFalse);
      expect(service.pendingRequests.single.approvalId, approvalId);
      await expectStillPending(pending);
      service.cancelForConversation('chat');
      final result = await pending;
      expect(result.approved, isFalse);
      expect(result.denyReason, 'cancelled');
      expect(result.takeSecretValues(), isEmpty);
    },
  );

  for (final throughTrust in [false, true]) {
    test(
      'inactive private input owner is cancelled (trust: $throughTrust)',
      () async {
        var active = true;
        final service = ToolApprovalService();
        addTearDown(service.dispose);
        final pending = service.requestApproval(
          toolCallId: 'private',
          toolName: 'manage_mcp',
          arguments: const {'action': 'add'},
          secretFields: const ['env:API_KEY'],
          owner: ToolApprovalOwner(
            conversationId: 'chat',
            generationRunId: 'run',
            assistantMessageId: 'message',
            isActive: () => active,
          ),
        );
        active = false;
        if (throughTrust) {
          service.setAutoApproveAll(true);
        } else {
          service.approve('private', conversationId: 'chat');
        }
        final result = await pending;
        expect(result.approved, isFalse);
        expect(result.denyReason, 'cancelled');
        expect(result.takeSecretValues(), isEmpty);
        expect(service.pendingRequests, isEmpty);
      },
    );
  }

  test(
    'private input requests cannot be completed by notification approval',
    () async {
      final service = ToolApprovalService()..setAutoApproveAll(true);
      addTearDown(service.dispose);
      final pending = service.requestApproval(
        toolCallId: 'private',
        toolName: 'manage_mcp',
        arguments: const {},
        secretFields: const ['env:API_KEY'],
        secretInputOnly: true,
        owner: const ToolApprovalOwner(
          conversationId: 'chat',
          generationRunId: 'run',
          assistantMessageId: 'message',
          isActive: _liveOwner,
        ),
      );
      expect(
        service.resolveNotificationApproval(
          approvalId: service.pendingRequests.single.approvalId,
          conversationId: 'chat',
          generationRunId: 'run',
          assistantMessageId: 'message',
          approved: true,
        ),
        ToolApprovalActionStatus.stale,
      );
      await expectStillPending(pending);
      service.cancelForRun('chat', 'run');
      expect((await pending).approved, isFalse);
    },
  );

  test(
    'reused MCP call ids cannot apply consent to a different change',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final first = service.requestApproval(
        toolCallId: 'same',
        toolName: 'manage_mcp',
        arguments: {
          'action': 'remove',
          'server': {'id': 'one'},
        },
        conversationId: 'chat',
      );
      final second = service.requestApproval(
        toolCallId: 'same',
        toolName: 'manage_mcp',
        arguments: {
          'action': 'remove',
          'server': {'id': 'two'},
        },
        conversationId: 'chat',
      );
      expect(service.pendingRequests.single.arguments['server']['id'], 'two');
      expect((await first).approved, isFalse);
      await expectStillPending(second);
      service.approve('same', conversationId: 'chat');
      expect((await second).approved, isTrue);
    },
  );

  test(
    'reused assistant manager ids need consent for the new change',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final first = service.requestApproval(
        toolCallId: 'same',
        toolName: 'manage_assistants',
        conversationId: 'chat',
        arguments: const {'action': 'delete', 'assistant_id': 'one'},
      );
      final second = service.requestApproval(
        toolCallId: 'same',
        toolName: 'manage_assistants',
        conversationId: 'chat',
        arguments: const {'action': 'delete', 'assistant_id': 'two'},
      );
      expect(service.pendingRequests.single.arguments['assistant_id'], 'two');
      expect((await first).approved, isFalse);
      await expectStillPending(second);
      service.approve('same', conversationId: 'chat');
      expect((await second).approved, isTrue);
    },
  );

  test('a report cannot reuse another tool\'s pending consent', () async {
    final service = ToolApprovalService();
    addTearDown(service.dispose);
    final other = service.requestApproval(
      toolCallId: 'same',
      toolName: 'shell',
      arguments: {'command': 'touch file'},
      conversationId: 'chat',
    );
    final report = service.requestApproval(
      toolCallId: 'same',
      toolName: 'report_problem',
      arguments: {},
      conversationId: 'chat',
    );
    expect(service.pendingRequests, hasLength(1));
    await expectStillPending(report);
    expect((await other).approved, isFalse);
    service.approve('same', conversationId: 'chat');
    expect((await report).approved, isTrue);
  });
  test('problem reports bypass consent with full trust', () async {
    final service = ToolApprovalService()..setAutoApproveAll(true);
    addTearDown(service.dispose);
    final pending = service.requestApproval(
      toolCallId: 'report',
      toolName: 'report_problem',
      arguments: const {},
      conversationId: 'chat',
    );
    expect(service.pendingRequests, isEmpty);
    expect((await pending).approved, isTrue);
  });

  test('enabling full trust approves a waiting problem report', () async {
    final service = ToolApprovalService();
    addTearDown(service.dispose);
    final pending = service.requestApproval(
      toolCallId: 'report',
      toolName: 'report_problem',
      arguments: const {},
      conversationId: 'chat',
    );
    service.setAutoApproveAll(true);
    expect(service.pendingRequests, isEmpty);
    expect((await pending).approved, isTrue);
  });

  test('problem reports require fresh consent without full trust', () async {
    final service = ToolApprovalService();
    addTearDown(service.dispose);
    for (var i = 0; i < 2; i++) {
      final pending = service.requestApproval(
        toolCallId: 'report',
        toolName: 'report_problem',
        arguments: const {},
        conversationId: 'chat',
      );
      expect(service.pendingRequests.single.requiresExplicitConsent, isTrue);
      await expectStillPending(pending);
      service.approve('report', conversationId: 'chat');
      expect((await pending).approved, isTrue);
    }
  });

  test(
    'two conversations sharing a placeholder id keep both Completers',
    () async {
      final service = ToolApprovalService();
      final futureA = service.requestApproval(
        toolCallId: 'round-0:tool-1',
        toolName: 'lookup',
        arguments: const {'q': 'a'},
        conversationId: 'conversation-a',
      );
      final futureB = service.requestApproval(
        toolCallId: 'round-0:tool-1',
        toolName: 'lookup',
        arguments: const {'q': 'b'},
        conversationId: 'conversation-b',
      );

      expect(service.pendingRequests, hasLength(2));
      expect(
        service.pendingFor(
          toolCallId: 'round-0:tool-1',
          conversationId: 'conversation-a',
        ),
        isNotNull,
      );
      expect(
        service.pendingFor(
          toolCallId: 'round-0:tool-1',
          conversationId: 'conversation-b',
        ),
        isNotNull,
      );

      service.approve('round-0:tool-1', conversationId: 'conversation-a');
      final resultA = await futureA;
      expect(resultA.approved, isTrue);
      await expectStillPending(futureB);
      expect(
        service.isPending('round-0:tool-1', conversationId: 'conversation-b'),
        isTrue,
      );
      expect(
        service.isPending('round-0:tool-1', conversationId: 'conversation-a'),
        isFalse,
      );

      service.approve('round-0:tool-1', conversationId: 'conversation-b');
      final resultB = await futureB;
      expect(resultB.approved, isTrue);
      expect(service.hasPending, isFalse);
    },
  );

  test(
    'requestApproval reuses the same Completer for identical arguments and key',
    () async {
      final service = ToolApprovalService();
      final first = service.requestApproval(
        toolCallId: 'round-0:tool-1',
        toolName: 'lookup',
        arguments: const {'q': 'first'},
        conversationId: 'conversation-a',
      );
      final second = service.requestApproval(
        toolCallId: 'round-0:tool-1',
        toolName: 'lookup',
        arguments: const {'q': 'first'},
        conversationId: 'conversation-a',
      );

      expect(service.pendingRequests, hasLength(1));
      service.approve('round-0:tool-1', conversationId: 'conversation-a');
      expect((await first).approved, isTrue);
      expect((await second).approved, isTrue);
    },
  );

  test('unscoped requests with the same toolCallId do not overwrite', () async {
    final service = ToolApprovalService();
    final first = service.requestApproval(
      toolCallId: 'round-0:tool-1',
      toolName: 'lookup',
      arguments: const {'q': 'first'},
    );
    final second = service.requestApproval(
      toolCallId: 'round-0:tool-1',
      toolName: 'lookup',
      arguments: const {'q': 'second'},
    );

    expect(service.pendingRequests, hasLength(2));
    await expectStillPending(first);
    await expectStillPending(second);

    service.cancelAll();
    expect((await first).approved, isFalse);
    expect((await second).approved, isFalse);
  });

  test('cancelForConversation leaves the other chat waiting', () async {
    final service = ToolApprovalService();
    final futureA = service.requestApproval(
      toolCallId: 'round-0:tool-1',
      toolName: 'lookup',
      arguments: const {},
      conversationId: 'conversation-a',
    );
    final futureB = service.requestApproval(
      toolCallId: 'round-0:tool-1',
      toolName: 'lookup',
      arguments: const {},
      conversationId: 'conversation-b',
    );

    service.cancelForConversation('conversation-a');
    expect((await futureA).approved, isFalse);
    await expectStillPending(futureB);
    expect(
      service.pendingFor(
        toolCallId: 'round-0:tool-1',
        conversationId: 'conversation-b',
      ),
      isNotNull,
    );
  });
  test('full trust approves immediately without creating pending UI', () async {
    final service = ToolApprovalService();
    service.setAutoApproveAll(true);

    final result = await service.requestApproval(
      toolCallId: 'browser-1',
      toolName: 'browser_use',
      arguments: const {'action': 'click', 'element_id': 1},
      conversationId: 'conversation-a',
    );

    expect(result.approved, isTrue);
    expect(service.pendingRequests, isEmpty);
  });

  test(
    'enabling full trust releases requests that are already waiting',
    () async {
      final service = ToolApprovalService();
      final pending = service.requestApproval(
        toolCallId: 'browser-1',
        toolName: 'browser_use',
        arguments: const {'action': 'type', 'element_id': 2},
        conversationId: 'conversation-a',
      );

      await expectStillPending(pending);
      expect(service.hasPending, isTrue);

      service.setAutoApproveAll(true);

      expect((await pending).approved, isTrue);
      expect(service.hasPending, isFalse);
    },
  );

  test('full trust also covers eval_js, with no exception', () async {
    final service = ToolApprovalService();
    service.setAutoApproveAll(true);

    final result = await service.requestApproval(
      toolCallId: 'browser-1',
      toolName: 'browser_use',
      arguments: const {'action': 'eval_js', 'code': 'document.title'},
      conversationId: 'conversation-a',
    );

    expect(result.approved, isTrue);
    expect(service.pendingRequests, isEmpty);
  });
}

bool _liveOwner() => true;
