import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/controllers/active_streaming_message_store.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolApprovalOwner owner(
    String chat,
    String run, {
    bool Function()? isActive,
  }) => ToolApprovalOwner(
    conversationId: chat,
    generationRunId: run,
    assistantMessageId: 'message-$run',
    isActive: isActive ?? () => true,
  );

  ToolApprovalActionStatus resolve(
    ToolApprovalService service,
    ToolApprovalRequest request, {
    bool approved = true,
    String? chat,
    String? run,
  }) => service.resolveNotificationApproval(
    approvalId: request.approvalId,
    conversationId: chat ?? request.conversationId!,
    generationRunId: run ?? request.generationRunId!,
    assistantMessageId: request.assistantMessageId!,
    approved: approved,
  );

  test(
    'native identities resolve only the matching live chat and run',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final a = service.requestApproval(
        toolCallId: 'round-0:tool-1',
        toolName: 'shell',
        arguments: const {},
        conversationId: 'a',
        owner: owner('a', 'run-a'),
      );
      final b = service.requestApproval(
        toolCallId: 'round-0:tool-1',
        toolName: 'shell',
        arguments: const {},
        conversationId: 'b',
        owner: owner('b', 'run-b'),
      );
      final requests = service.pendingRequests;
      expect(requests[0].approvalId, isNot(requests[1].approvalId));
      expect(
        resolve(service, requests[0], chat: 'b'),
        ToolApprovalActionStatus.stale,
      );
      expect(
        resolve(service, requests[0], run: 'run-b'),
        ToolApprovalActionStatus.stale,
      );
      expect(service.pendingRequests, hasLength(2));
      expect(resolve(service, requests[0]), ToolApprovalActionStatus.resolved);
      expect((await a).approved, isTrue);
      expect(service.pendingRequests.single, same(requests[1]));
      expect(
        resolve(service, requests[1], approved: false),
        ToolApprovalActionStatus.resolved,
      );
      expect((await b).approved, isFalse);
      expect(resolve(service, requests[0]), ToolApprovalActionStatus.stale);
    },
  );

  test(
    'a notification cannot approve a report without the in-chat disclosure',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final pending = service.requestApproval(
        toolCallId: 'report',
        toolName: 'report_problem',
        arguments: {},
        conversationId: 'chat',
        owner: owner('chat', 'run'),
      );
      expect(
        resolve(service, service.pendingRequests.single),
        ToolApprovalActionStatus.stale,
      );
      expect(service.pendingRequests, hasLength(1));
      service.approve('report', conversationId: 'chat');
      expect((await pending).approved, isTrue);
    },
  );

  test(
    'old action cannot approve a successor with the same tool call id',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final first = service.requestApproval(
        toolCallId: 'same',
        toolName: 'tool',
        arguments: const {},
        conversationId: 'a',
        owner: owner('a', 'old'),
      );
      final previous = service.pendingRequests.single;
      service.cancelForConversation('a');
      expect((await first).approved, isFalse);
      final next = service.requestApproval(
        toolCallId: 'same',
        toolName: 'tool',
        arguments: const {},
        conversationId: 'a',
        owner: owner('a', 'new'),
      );
      final current = service.pendingRequests.single;
      expect(resolve(service, previous), ToolApprovalActionStatus.stale);
      expect(service.pendingRequests.single, same(current));
      service.deny('same', conversationId: 'a');
      expect((await next).approved, isFalse);
      expect(resolve(service, current), ToolApprovalActionStatus.stale);
    },
  );

  test(
    'cancelled owner cannot create an approval or use trusted mode',
    () async {
      final service = ToolApprovalService()..setAutoApproveAll(true);
      addTearDown(service.dispose);
      final result = await owner('a', 'run', isActive: () => false).run(
        () => service.requestApproval(
          toolCallId: 'late',
          toolName: 'tool',
          arguments: const {},
          conversationId: 'a',
        ),
      );
      expect(result.approved, isFalse);
      expect(result.denyReason, 'cancelled');
      expect(service.pendingRequests, isEmpty);
    },
  );

  test(
    'an old continuation cannot adopt the next execution of its message',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final store = ActiveStreamingMessageStore();
      final message = ChatMessage(
        id: 'same-assistant',
        role: 'assistant',
        conversationId: 'a',
        content: 'partial',
        isStreaming: true,
      );
      ToolApprovalOwner execution(String token) => ToolApprovalOwner(
        conversationId: 'a',
        generationRunId: token,
        assistantMessageId: message.id,
        isActive: () => store.isExecutionActive(message, token),
      );
      store.put(message, executionId: 'first');
      final firstOwner = execution('first');
      final first = service.requestApproval(
        toolCallId: 'same',
        toolName: 'tool',
        arguments: const {},
        owner: firstOwner,
      );
      final previous = service.pendingRequests.single;
      store.invalidateExecution('a', executionId: 'first');
      service.cancelForRun('a', 'first');
      expect((await first).approved, isFalse);

      store.put(message, executionId: 'second');
      final next = service.requestApproval(
        toolCallId: 'same',
        toolName: 'tool',
        arguments: const {},
        owner: execution('second'),
      );
      final current = service.pendingRequests.single;
      final late = await firstOwner.run(
        () => service.requestApproval(
          toolCallId: 'late',
          toolName: 'tool',
          arguments: const {},
        ),
      );
      expect(late.approved, isFalse);
      expect(resolve(service, previous), ToolApprovalActionStatus.stale);
      expect(service.pendingRequests.single, same(current));
      expect(resolve(service, current), ToolApprovalActionStatus.resolved);
      expect((await next).approved, isTrue);
    },
  );

  test(
    'inactive pending owner rejects action and releases the old gate',
    () async {
      var active = true;
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final future = service.requestApproval(
        toolCallId: 'call',
        toolName: 'tool',
        arguments: const {},
        conversationId: 'a',
        owner: owner('a', 'run', isActive: () => active),
      );
      final request = service.pendingRequests.single;
      active = false;
      expect(resolve(service, request), ToolApprovalActionStatus.stale);
      expect((await future).approved, isFalse);
      expect(service.pendingRequests, isEmpty);
    },
  );

  test(
    'trust and service disposal invalidate notification authority',
    () async {
      final service = ToolApprovalService();
      final future = service.requestApproval(
        toolCallId: 'call',
        toolName: 'tool',
        arguments: const {},
        conversationId: 'a',
        owner: owner('a', 'run'),
      );
      final request = service.pendingRequests.single;
      service.setAutoApproveAll(true);
      expect((await future).approved, isTrue);
      expect(resolve(service, request), ToolApprovalActionStatus.stale);
      service.setAutoApproveAll(false);
      final pending = service.requestApproval(
        toolCallId: 'other',
        toolName: 'tool',
        arguments: const {},
        conversationId: 'a',
        owner: owner('a', 'next'),
      );
      service.dispose();
      expect((await pending).approved, isFalse);
    },
  );

  for (final throughTrust in [false, true]) {
    test(
      '${throughTrust ? 'trusted mode' : 'in-chat Allow'} cannot release an inactive execution',
      () async {
        var active = true;
        final service = ToolApprovalService();
        addTearDown(service.dispose);
        final future = service.requestApproval(
          toolCallId: 'old',
          toolName: 'tool',
          arguments: const {},
          conversationId: 'a',
          owner: owner('a', 'run', isActive: () => active),
        );
        active = false;
        if (throughTrust) {
          service.setAutoApproveAll(true);
        } else {
          service.approve('old', conversationId: 'a');
        }
        expect((await future).approved, isFalse);
        expect(service.pendingRequests, isEmpty);
      },
    );
  }
}
