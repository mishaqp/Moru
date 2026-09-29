import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/external_mounts_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/acp/acp_agent.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../core/services/acp/acp_error_messages.dart';
import '../../../core/services/acp/acp_chat_prompt.dart';
import '../../../core/services/acp/acp_chat_sessions.dart';
import '../../../core/services/acp/acp_provider_input.dart';
import '../../../core/services/api/stream/stream_chunk.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/workspace/task_plan.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import '../../../l10n/app_localizations.dart';
import 'tool_approval_service.dart';

/// Extras key of a chat's agent session: `{agent, id}`.
const String acpSessionKey = 'acp.session';
const String acpModeKey = 'acp.mode';

/// Sends a chat turn to the assistant's agent instead of the model.
///
/// The chat keeps doing everything else the same way: the message is stored,
/// streamed, stopped and finished by the usual pipeline; only the source of
/// the chunks changes.
class AcpChatBridge {
  AcpChatBridge(this.context);

  final BuildContext context;

  /// Translate both setup failures and errors arriving after streaming starts.
  Future<Stream<StreamChunk>?> streamFor({
    required Object? assistant,
    required String conversationId,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
    required List<Map<String, dynamic>> apiMessages,
    List<String> userImagePaths = const [],
  }) async {
    if (assistant is! Assistant || assistant.agentId?.isNotEmpty != true) {
      return null;
    }
    final l10n = AppLocalizations.of(context)!;
    try {
      final stream = await _streamFor(
        assistant: assistant,
        conversationId: conversationId,
        settings: settings,
        providerKey: providerKey,
        modelId: modelId,
        apiMessages: apiMessages,
        userImagePaths: userImagePaths,
      );
      return stream == null ? null : localizeStreamErrors(stream, l10n);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(localizeAcpError(error, l10n), stackTrace);
    }
  }

  static Stream<StreamChunk> localizeStreamErrors(
    Stream<StreamChunk> source,
    AppLocalizations l10n,
  ) => source.handleError((Object error, StackTrace stackTrace) {
    Error.throwWithStackTrace(localizeAcpError(error, l10n), stackTrace);
  });

  /// The agent's answer, or null when [assistant] has no agent.
  Future<Stream<StreamChunk>?> _streamFor({
    required Object? assistant,
    required String conversationId,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
    required List<Map<String, dynamic>> apiMessages,
    List<String> userImagePaths = const [],
  }) async {
    if (assistant is! Assistant) return null;
    final agentId = assistant.agentId;
    if (agentId == null || agentId.isEmpty) return null;
    // Everything from the widget tree is read before the first await.
    final l10n = AppLocalizations.of(context)!;
    final manager = context.read<AcpAgentManager>();
    final sessions = context.read<AcpChatSessions>();
    final chats = context.read<ChatService>();
    final workspaces = context.read<WorkspaceProvider>();
    final runtime = context.read<WorkspaceRuntimeProvider>();
    final externalMounts = context.read<ExternalMountsProvider?>();
    final approvals = context.read<ToolApprovalService?>();
    final assistants = context.read<AssistantProvider>();
    TaskPlanRegistry? plans;
    try {
      plans = context.read<TaskPlanRegistry>();
    } on ProviderNotFoundException {
      plans = null;
    }

    await manager.loaded;
    final spec = manager.agent(agentId);
    if (spec == null) {
      throw AcpError(AcpError.internalError, l10n.agentsChatMissing);
    }
    if (manager.state(spec.id) == AcpInstallState.missing) {
      throw AcpError(
        AcpError.internalError,
        l10n.agentsChatNotInstalled(spec.name),
      );
    }
    final provider = acpProviderInputFor(settings, providerKey, modelId);
    if (provider == null) {
      throw AcpError(AcpError.internalError, l10n.agentsChatNoKey);
    }

    await ensureWorkspace(
      chats: chats,
      workspaces: workspaces,
      assistants: assistants,
      assistant: assistant,
      conversationId: conversationId,
      name: spec.name,
    );
    final workspace = await WorkspaceToolsService.resolve(
      conversationId: conversationId,
      workspaceProvider: workspaces,
      runtimeProvider: runtime,
      chatService: chats,
      externalMounts: externalMounts,
    );
    final message = acpPromptFromMessages(apiMessages);
    final saved = chats.getConversation(conversationId)?.extras[acpSessionKey];

    return sessions.send(
      AcpChatTurn(
        conversationId: conversationId,
        spec: spec,
        provider: provider,
        cwd: workspace?.cwd ?? '/root',
        mounts: workspace?.paths.mounts ?? const [],
        prompt: message.prompt,
        userImagePaths: userImagePaths,
        imageNotSentMessage: l10n.agentsImageNotSent,
        savedModeId:
            chats.getConversation(conversationId)?.extras[acpModeKey]
                as String?,
        history: message.history,
        savedSessionId: saved is Map && saved['agent'] == spec.id
            ? saved['id'] as String?
            : null,
        onSession: (id) => unawaited(
          chats.updateConversationExtras(
            conversationId,
            (extras) => extras
              ..[acpSessionKey] = <String, dynamic>{'agent': spec.id, 'id': id},
          ),
        ),
        onPermission: approvals == null
            ? null
            : (request) => answerPermission(
                approvals,
                request,
                conversationId: conversationId,
              ),
        onPlan: plans == null
            ? null
            : (plan) => plans!.set(conversationId, plan),
      ),
    );
  }

  /// An agent works on files, so its chat always has a workspace: the
  /// assistant's default one, made on first use and named after the agent.
  /// Its files then show in the chat's Files panel and terminal.
  @visibleForTesting
  static Future<void> ensureWorkspace({
    required ChatService chats,
    required WorkspaceProvider workspaces,
    required AssistantProvider assistants,
    required Assistant assistant,
    required String conversationId,
    required String name,
  }) async {
    final conversation = chats.getConversation(conversationId);
    if (conversation == null ||
        chats.isTemporaryConversation(conversationId) ||
        WorkspaceBinding.fromExtras(conversation.extras).isBound) {
      return;
    }
    await workspaces.loaded;
    final defaultId = assistants.getById(assistant.id)?.defaultWorkspaceId;
    var workspace = defaultId == null ? null : workspaces.byId(defaultId);
    if (workspace == null) {
      workspace = await workspaces.create(name: name);
      final current = assistants.getById(assistant.id);
      if (current != null) {
        await assistants.updateAssistant(
          current.copyWith(defaultWorkspaceId: workspace.id),
        );
      }
    }
    await chats.updateConversationExtras(
      conversationId,
      WorkspaceBinding(
        workspaceId: workspace.id,
        cwd: workspace.defaultCwd,
      ).applyTo,
    );
  }

  /// Asks on the tool's card in the chat; "Allow" picks the agent's
  /// allow-once option, "Deny" its reject-once one. Trusted mode allows.
  static Future<String?> answerPermission(
    ToolApprovalService approvals,
    AcpPermissionRequest request, {
    required String conversationId,
  }) async {
    final result = await approvals.requestApproval(
      toolCallId: request.toolCallId.isEmpty
          ? 'acp-permission-${request.title.hashCode}'
          : request.toolCallId,
      toolName: request.title.isEmpty ? request.kind : request.title,
      arguments: {
        if (request.input is Map)
          ...Map<String, dynamic>.from(request.input as Map),
      },
      conversationId: conversationId,
    );
    String? pick(bool allow, String preferred) {
      for (final option in request.options) {
        if (option.kind == preferred) return option.id;
      }
      for (final option in request.options) {
        if (option.allows == allow) return option.id;
      }
      return null;
    }

    return result.approved
        ? pick(true, 'allow_once')
        : pick(false, 'reject_once');
  }
}
