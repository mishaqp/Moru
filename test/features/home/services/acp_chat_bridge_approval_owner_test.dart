import 'package:Kelivo/core/services/acp/acp_agent.dart';
import 'package:Kelivo/features/home/services/acp_chat_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = AcpPermissionRequest(
    sessionId: 'private-session',
    toolCallId: 'acp:same-card',
    title: 'Run tool',
    kind: 'execute',
    input: {},
    options: [
      AcpPermissionOption(
        id: 'always',
        name: 'Allow always',
        kind: 'allow_always',
      ),
      AcpPermissionOption(id: 'once', name: 'Allow once', kind: 'allow_once'),
      AcpPermissionOption(id: 'reject', name: 'Deny', kind: 'reject_once'),
    ],
  );
  test(
    'ACP callback keeps captured ownership and native Allow picks allow once',
    () async {
      final service = ToolApprovalService();
      addTearDown(service.dispose);
      final owner = ToolApprovalOwner(
        conversationId: 'a',
        generationRunId: 'run-a',
        assistantMessageId: 'message-a',
        isActive: () => true,
      );
      final answer =
          await ToolApprovalOwner(
            conversationId: 'b',
            generationRunId: 'run-b',
            assistantMessageId: 'message-b',
            isActive: () => true,
          ).run(() async {
            final pending = AcpChatBridge.answerPermission(
              service,
              request,
              conversationId: 'a',
              approvalOwner: owner,
            );
            final item = service.pendingRequests.single;
            expect(item.generationRunId, 'run-a');
            expect(
              service.resolveNotificationApproval(
                approvalId: item.approvalId,
                conversationId: 'a',
                generationRunId: 'run-a',
                assistantMessageId: 'message-a',
                approved: true,
              ),
              ToolApprovalActionStatus.resolved,
            );
            return pending;
          });
      expect(answer, 'once');
    },
  );
}
