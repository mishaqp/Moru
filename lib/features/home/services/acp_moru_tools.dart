import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/acp/acp_mcp_binding.dart';
import '../../../core/services/acp/acp_mcp_server.dart';
import '../../../core/services/api/generation/tool_result_images.dart';
import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import '../../../utils/mcp_structured_image.dart';
import 'tool_approval_service.dart';
import 'tool_handler_service.dart';
import 'spend_control_tool.dart';

/// Reuses the model's definitions, policy and handlers with the agent's chat.
class AcpMoruTools {
  static AcpMcpTools create({
    required BuildContext context,
    required Assistant assistant,
    required ChatService chats,
    required AssistantProvider assistants,
    required SettingsProvider settings,
    required String conversationId,
    required String providerKey,
    required String modelId,
    required WorkspaceToolContext? workspace,
    required ToolApprovalService? approvals,
    ToolApprovalOwner? approvalOwner,
    SpendCompactHandler? compactContext,
    MiniAppRuntime? miniAppRuntime,
  }) {
    final service = ToolHandlerService(
      contextProvider: context,
      compactContext: compactContext,
      miniAppRuntime: miniAppRuntime,
    );
    final miniAppRoutes = service.captureMiniAppToolRoutes();
    Assistant? current() {
      if (!context.mounted || chats.getConversation(conversationId) == null) {
        return null;
      }
      final chatAssistant = chats.getConversation(conversationId)?.assistantId;
      if (chatAssistant != null && chatAssistant != assistant.id) return null;
      return assistants.getById(assistant.id);
    }

    List<Map<String, dynamic>> definitions() {
      final live = current();
      if (live == null) return [];
      return AcpMcpServer.moruTools(
        service.buildToolDefinitions(
          settings,
          live,
          providerKey,
          modelId,
          false,
          isToolModel: (_, _) => true,
          workspaceContext: workspace,
          miniAppRouteSnapshot: miniAppRoutes,
          conversationId: conversationId,
        ),
        miniAppActionNames: miniAppRoutes.names,
      );
    }

    return AcpMcpTools(
      key: assistant.id,
      definitions: definitions,
      miniAppActionNames: () => {
        for (final tool in definitions())
          if (tool['name'] case final String name)
            if (miniAppRoutes.names.contains(name)) name,
      },
      cancelApproval: (id) => approvals?.deny(
        id,
        conversationId: conversationId,
        reason: 'cancelled',
      ),
      execute: (name, args, {required toolCallId}) async {
        if (approvalOwner != null && !approvalOwner.isActive()) {
          return error('The agent turn was cancelled.');
        }
        final live = current();
        if (live == null ||
            !definitions().any((tool) => tool['name'] == name)) {
          return error(
            'This Moru tool is disabled for the assistant in this chat.',
          );
        }
        if (name == 'browser_use' &&
            !browserUiAvailable(context, chats, conversationId)) {
          return error(
            'The Moru browser needs a visible chat. Open this agent chat in Moru and try again.',
          );
        }
        final handler = service.buildToolCallHandler(
          settings,
          live,
          approvalService: approvals,
          conversationId: conversationId,
          workspaceContext: workspace,
          miniAppRouteSnapshot: miniAppRoutes,
          miniAppSource: MiniAppInvocationSource.acp,
        );
        if (handler == null) {
          return error('The Moru tool handler is unavailable.');
        }
        Future<Object?> execute() =>
            handler(name, args, toolCallId: toolCallId);
        return result(
          await (approvalOwner == null
              ? execute()
              : approvalOwner.run(execute)),
        );
      },
    );
  }

  static bool browserUiAvailable(
    BuildContext context,
    ChatService chats,
    String id,
  ) {
    if (!context.mounted || chats.currentConversationId != id) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final browser = BrowserAgentSession.instance;
    return ModalRoute.of(context)?.isCurrent == true ||
        (browser.ownerConversationId == id && browser.isRouteCurrent);
  }

  static Map<String, Object?> error(String message) => {
    'isError': true,
    'content': [
      {'type': 'text', 'text': message},
    ],
  };

  static Future<Map<String, Object?>> result(Object? raw) async {
    final value = ClientToolResult.fromHandler(raw);
    Object? decoded;
    try {
      decoded = jsonDecode(value.content);
    } on FormatException {
      /* Plain text. */
    }
    final isError =
        decoded is Map &&
        (decoded['type'] == 'tool_error' ||
            decoded['error'] != null ||
            decoded['ok'] == false ||
            const {
              'permission_required',
              'unsupported',
              'denied',
              'failed',
              'unknown_after_timeout',
            }.contains(decoded['status']));
    final images = await loadToolResultImages(value.metadata);
    return {
      'isError': isError,
      'content': [
        {'type': 'text', 'text': value.content},
        for (final image in images)
          {'type': 'image', 'data': image.base64, 'mimeType': image.mime},
      ],
    };
  }
}
