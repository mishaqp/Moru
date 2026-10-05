import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/memory_provider_v2.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/tool_call_cancellation.dart';
import '../../../core/services/api/tool_call_argument_privacy.dart';
import '../../../core/services/mcp/mcp_tool_privacy.dart';
import '../../../core/services/api/tool_schema_normalizer.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/memory/memory_pipeline.dart';
import '../../../core/services/memory/memory_tools.dart';
import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/logging/problem_report_service.dart';
import '../../../core/services/scheduled_tasks_service.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/services/tools/tool_schema_overrides.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import '../../../core/services/workspace/task_plan.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/browser/browser_agent_session.dart';
import '../../../core/services/browser/browser_cookie_export.dart';
import '../../mini_apps/mini_app_checker.dart';
import '../../mini_apps/mini_app_launcher.dart';
import 'ask_user_interaction_service.dart';
import 'assistant_manager_tool.dart';
import 'browser_agent_tool.dart';
import 'built_in_tool_names.dart';
import 'local_tools_service.dart';
import 'mcp_manager_tool.dart';
import 'mini_app_data_tool.dart';
import 'mini_app_tool_routes.dart';

export 'mini_app_tool_routes.dart' show MiniAppToolRouteSnapshot;
import 'root_phone_control.dart';
import 'root_shell_tool.dart';
import 'scheduled_task_tool.dart';
import 'spend_control_service.dart';
import 'spend_control_tool.dart';
import 'tool_approval_service.dart';
import '../../../core/services/acp/acp_agent_manager.dart';

/// 工具调用处理服务
///
/// 处理各类工具调用：
/// - MCP 工具
/// - Memory 工具 (§10)
/// - Search 工具
class ToolHandlerService {
  ToolHandlerService({
    required this.contextProvider,
    this.compactContext,
    this.miniAppRuntime,
  });

  SpendCompactHandler? compactContext;
  final MiniAppRuntime? miniAppRuntime;
  MiniAppRuntime get _miniApps => miniAppRuntime ?? MiniAppLauncher.runtime;

  Set<String> get miniAppActionNames => {
    for (final definition in _miniApps.toolDefinitions())
      definition['function']['name'] as String,
  };

  Set<String> get _reservedToolNames => {
    ...BuiltInToolNames.all,
    ...miniAppActionNames,
  };

  MiniAppToolRouteSnapshot captureMiniAppToolRoutes() =>
      MiniAppToolRouteSnapshot.capture(_miniApps);

  /// Build context (used for accessing providers)
  final BuildContext contextProvider;

  T? _optional<T>() {
    try {
      return contextProvider.read<T>();
    } catch (_) {
      return null;
    }
  }

  WorkspaceToolsService _workspaceTools() {
    try {
      final chat = contextProvider.read<ChatService>();
      final workspaces = contextProvider.read<WorkspaceProvider>();
      Future<void> Function(String skillId)? onSkillRead;
      Future<void> Function()? onShellCompleted;
      try {
        final skills = contextProvider.read<SkillsService>();
        onSkillRead = skills.incrementUseCount;
        onShellCompleted = skills.rescan;
      } catch (_) {}
      return WorkspaceToolsService(
        registry: contextProvider.read<ToolRunRegistry>(),
        runtimeProvider: contextProvider.read<WorkspaceRuntimeProvider>(),
        updateConversationExtras: chat.updateConversationExtras,
        touchLastUsed: workspaces.touchLastUsed,
        onSkillRead: onSkillRead,
        onShellCompleted: onShellCompleted,
        loadEnvironment: contextProvider
            .read<EnvironmentProvider?>()
            ?.loadExecutionConfig,
        isToolEnabled: (id, name) =>
            workspaces.byId(id)?.isToolEnabled(name) ?? false,
        plans: _optional<TaskPlanRegistry>(),
        checkMiniApp: defaultTargetPlatform == TargetPlatform.android
            ? (app) {
                final environment = contextProvider
                    .read<EnvironmentProvider?>();
                return MiniAppChecker.run(
                  app,
                  jobs: MiniAppLauncher.jobs,
                  serverEnvironment: environment == null
                      ? null
                      : MiniAppLauncher.serverEnvironment(
                          contextProvider.read<WorkspaceRuntimeProvider>(),
                          environment,
                        ),
                );
              }
            : null,
      );
    } catch (_) {
      return WorkspaceToolsService();
    }
  }

  // ============================================================================
  // Tool Schema Sanitization
  // ============================================================================

  /// Compatibility entry point; all provider conversion lives in the normalizer.
  static Map<String, dynamic> sanitizeToolParametersForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) => normalizeToolSchema(schema, switch (kind) {
    ProviderKind.google => ToolSchemaTarget.gemini,
    ProviderKind.claude => ToolSchemaTarget.claude,
    _ => ToolSchemaTarget.openai,
  }).parameters;

  static String _toolError({
    required String error,
    required String message,
    required String tool,
    String? instruction,
  }) {
    return jsonEncode({
      'type': 'tool_error',
      'error': error,
      'message': message,
      'tool': tool,
      if (instruction != null) 'instruction': instruction,
    });
  }

  // ============================================================================
  // Tool Definitions Builder
  // ============================================================================

  McpToolRouteSnapshot captureMcpToolRoutes(Assistant? assistant) {
    return contextProvider.read<McpToolService>().captureRoutesForAssistant(
      contextProvider.read<McpProvider>(),
      contextProvider.read<AssistantProvider>(),
      assistantId: assistant?.id,
      reservedNames: _reservedToolNames,
    );
  }

  /// Build tool definitions for API call.
  ///
  /// Returns a list of tool definitions including:
  /// - Search tool (if enabled and model supports tools)
  /// - Memory tools (if assistant has memory / past-recall enabled)
  /// - MCP tools (from selected servers for the assistant)
  /// Whether the chat being generated is a throwaway one.
  ///
  /// Scheduled sends can target a different conversation from the visible one.
  bool _isTemporaryConversation(String? conversationId) {
    try {
      final chatService = contextProvider.read<ChatService>();
      return chatService.isTemporaryConversation(
        conversationId ?? chatService.currentConversationId,
      );
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch, {
    required bool Function(String providerKey, String modelId) isToolModel,
    McpToolRouteSnapshot? mcpRouteSnapshot,
    MiniAppToolRouteSnapshot? miniAppRouteSnapshot,
    WorkspaceToolContext? workspaceContext,
    String? conversationId,
  }) {
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    final supportsTools = isToolModel(providerKey, modelId);

    // Search tool (skip when Gemini built-in search is active)
    if (assistant?.searchEnabled == true &&
        !hasBuiltInSearch &&
        supportsTools) {
      toolDefs.add(SearchToolService.getToolDefinition());
    }

    // Memory tools (§10.1)
    if (settings.legacyMemoryMode) {
      if (assistant?.enableMemory == true && supportsTools) {
        toolDefs.addAll(
          MemoryTools.legacyDefinitions(settings.resolvedMemoryPromptLang),
        );
      }
    } else if (supportsTools && assistant != null) {
      toolDefs.addAll(
        MemoryTools.buildDefinitions(
          lang: settings.resolvedMemoryPromptLang,
          writeScope: assistant.memoryWriteScope,
          enableMemory: assistant.enableMemory,
          allowPastConversationRecall: assistant.allowPastConversationRecall,
          allowMemoryWrites: !_isTemporaryConversation(conversationId),
        ),
      );
    }

    // Local tools
    toolDefs.addAll(
      LocalToolsService.buildToolDefinitions(
        assistant: assistant,
        supportsTools: supportsTools,
      ),
    );
    if (supportsTools &&
        assistant != null &&
        LocalToolsService.isAvailableOnThisPlatform(LocalToolNames.miniApps) &&
        LocalToolsService.isEnabledForAssistant(
          LocalToolNames.miniApps,
          assistant,
        )) {
      toolDefs.addAll(
        (miniAppRouteSnapshot ?? captureMiniAppToolRoutes()).currentDefinitions(
          _miniApps.store,
        ),
      );
    }

    // MCP tools
    final mcpTools = _buildMcpToolDefinitions(
      settings: settings,
      assistant: assistant,
      providerKey: providerKey,
      supportsTools: supportsTools,
      mcpRouteSnapshot: mcpRouteSnapshot,
    );
    toolDefs.addAll(mcpTools);

    if (supportsTools && workspaceContext != null) {
      toolDefs.addAll(_workspaceTools().buildToolDefinitions(workspaceContext));
    }

    final overrides = settings.toolSchemaOverrides;
    if (overrides.isEmpty) return toolDefs;
    return ToolSchemaOverrides.apply(toolDefs, overrides);
  }

  /// Build MCP tool definitions from connected servers.
  List<Map<String, dynamic>> _buildMcpToolDefinitions({
    required SettingsProvider settings,
    required Assistant? assistant,
    required String providerKey,
    required bool supportsTools,
    McpToolRouteSnapshot? mcpRouteSnapshot,
  }) {
    if (!supportsTools) return [];

    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    final tools = toolSvc.listAvailableToolsForAssistant(
      mcp,
      contextProvider.read<AssistantProvider>(),
      assistant?.id,
      routeSnapshot: mcpRouteSnapshot,
      reservedNames: _reservedToolNames,
    );

    if (tools.isEmpty) return [];

    return tools.map((t) {
      final baseSchema = McpToolService.sourceParameters(t);
      return {
        'type': 'function',
        'function': {
          'name': t.name,
          if ((t.description ?? '').isNotEmpty) 'description': t.description,
          'parameters': baseSchema,
        },
      };
    }).toList();
  }

  // ============================================================================
  // Tool Call Handler
  // ============================================================================

  /// Build tool call handler function.
  ///
  /// Returns a function that handles tool calls by name and arguments.
  /// Supports:
  /// - Search tool calls
  /// - Memory tool calls (§10)
  /// - MCP tool calls
  ToolCallHandler? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant, {
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
    String? conversationId,
    McpToolRouteSnapshot? mcpRouteSnapshot,
    MiniAppToolRouteSnapshot? miniAppRouteSnapshot,
    WorkspaceToolContext? workspaceContext,
    MiniAppInvocationSource miniAppSource = MiniAppInvocationSource.chat,
  }) {
    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    // Capture AssistantProvider reference before async gap to avoid
    // use_build_context_synchronously warning
    final assistantProvider = contextProvider.read<AssistantProvider>();
    final routes =
        mcpRouteSnapshot ??
        toolSvc.captureRoutesForAssistant(
          mcp,
          assistantProvider,
          assistantId: assistant?.id,
          reservedNames: _reservedToolNames,
        );

    String approvalIdFor(String name, String? toolCallId) {
      final trimmed = toolCallId?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
      return '${name}_${DateTime.now().microsecondsSinceEpoch}';
    }

    void ensureLiveToolCall() {
      ToolCallCancellation.current?.throwIfCancelled();
      final owner = ToolApprovalOwner.current;
      if (owner != null && !owner.isActive()) {
        throw StateError('tool_call_cancelled');
      }
    }

    final miniAppBindings =
        (miniAppRouteSnapshot ?? captureMiniAppToolRoutes()).bindings;

    MiniAppInvocation appInvocation(
      String name,
      String? toolCallId, {
      Future<void>? cancelled,
    }) => MiniAppInvocation(
      source: miniAppSource,
      cancelled: cancelled,
      fullTrust: () => settings.toolAutoApproveAll,
      isAllowed: () {
        try {
          ensureLiveToolCall();
          if (!contextProvider.mounted) return false;
          final current = assistant == null
              ? null
              : assistantProvider.getById(assistant.id);
          return current != null &&
              LocalToolsService.isAvailableOnThisPlatform(
                LocalToolNames.miniApps,
              ) &&
              LocalToolsService.isEnabledForAssistant(
                LocalToolNames.miniApps,
                current,
              );
        } catch (_) {
          return false;
        }
      },
      approve: approvalService == null
          ? null
          : (app, action, arguments) async {
              approvalService.setAutoApproveAll(settings.toolAutoApproveAll);
              final approval = await approvalService.requestApproval(
                toolCallId: approvalIdFor(name, toolCallId),
                toolName: MiniAppRuntime.toolNameFor(app.id, action.name),
                conversationId: conversationId,
                arguments: {
                  'app_id': app.id,
                  'app': app.name,
                  'action': action.name,
                  'description': action.description,
                  'version': app.updatedAt.millisecondsSinceEpoch,
                  'source': miniAppSource.name,
                  'arguments': arguments,
                },
              );
              return approval.approved;
            },
    );

    Future<T> invokeMiniApp<T>(
      String name,
      String? toolCallId,
      Future<T> Function(MiniAppInvocation) execute,
    ) async {
      final cancellation = Completer<void>();
      final invocation = appInvocation(
        name,
        toolCallId,
        cancelled: cancellation.future,
      );
      void changed() {
        if (invocation.isAllowed?.call() == false &&
            !cancellation.isCompleted) {
          cancellation.complete();
        }
      }

      // A live predicate prevents the next step, while this signal also stops
      // native work already waiting for Android or a root-manager response.
      assistantProvider.addListener(changed);
      try {
        changed();
        return await execute(invocation);
      } finally {
        assistantProvider.removeListener(changed);
        if (!cancellation.isCompleted) cancellation.complete();
      }
    }

    final privacy = McpToolPrivacy(mcp);
    final assistantCredentials = <String>{};
    Map<String, dynamic> publicAssistantArguments(Map<String, dynamic> args) =>
        AssistantManagerTool.argumentsForModel(
          args,
          assistants: assistantProvider.assistants,
          catalog: _assistantManagerCatalog(settings, mcp),
          retainedCredentials: assistantCredentials,
        );

    Future<Object?> approveAndExecuteMcp(
      String name,
      Map<String, dynamic> args, {
      String? toolCallId,
    }) async {
      privacy.capture(mcp);
      if (privacy.containsCredential(args)) {
        return _toolError(
          error: 'credential_arguments',
          message:
              'MCP credential literals are not accepted in tool arguments. Configure credentials privately in MCP settings.',
          tool: privacy.text(name),
        );
      }
      final needsApproval =
          !settings.toolAutoApproveAll &&
          toolSvc.toolNeedsApprovalForAssistant(
            mcp,
            assistantProvider,
            assistantId: assistant?.id,
            toolName: name,
            routeSnapshot: routes,
            reservedNames: _reservedToolNames,
          );
      if (needsApproval) {
        if (approvalService == null) {
          return _toolError(
            error: 'approval_unavailable',
            message: 'This MCP tool requires the user\'s confirmation.',
            tool: privacy.text(name),
          );
        }
        approvalService.setAutoApproveAll(false);
        final result = await approvalService.requestApproval(
          toolCallId: approvalIdFor(name, toolCallId),
          toolName: name,
          arguments: args,
          conversationId: conversationId,
        );
        privacy.capture(mcp);
        if (!result.approved) {
          return _toolError(
            error: 'approval_denied',
            message: privacy.text(
              result.denyReason ?? 'User denied the tool call',
            ),
            tool: privacy.text(name),
          );
        }
      }

      ensureLiveToolCall();
      return toolSvc.callToolForAssistant(
        mcp,
        assistantProvider,
        assistantId: assistant?.id,
        toolName: name,
        arguments: args,
        routeSnapshot: routes,
        reservedNames: _reservedToolNames,
      );
    }

    final workspaceTools = workspaceContext == null ? null : _workspaceTools();

    Future<Object?> handler(
      String name,
      Map<String, dynamic> args, {
      String? toolCallId,
    }) async {
      try {
        ensureLiveToolCall();
        final binding = miniAppBindings[name];
        if (binding != null) {
          if (!identical(_miniApps.store.byId(binding.app.id), binding.app)) {
            return jsonEncode({
              'ok': false,
              'status': 'denied',
              'message':
                  'The app changed after this tool was offered. Request its current actions again.',
            });
          }
          return jsonEncode(
            MiniAppDataTool.stateForModel(
              await invokeMiniApp(
                name,
                toolCallId,
                (invocation) => _miniApps.execute(
                  binding.app.id,
                  binding.actionName,
                  args,
                  invocation: invocation,
                ),
              ),
            ),
          );
        }
        if (workspaceContext != null &&
            workspaceTools != null &&
            WorkspaceToolsService.toolNames.contains(name)) {
          return await workspaceTools.handle(
            workspaceContext,
            name,
            args,
            toolCallId: toolCallId ?? '',
            approvalService: approvalService,
            conversationId: conversationId,
          );
        }

        if (routes.containsExposedName(name)) {
          return await approveAndExecuteMcp(name, args, toolCallId: toolCallId);
        }

        final liveAssistant = assistant == null
            ? null
            : assistantProvider.getById(assistant.id);
        bool localPermissionIsLive() =>
            liveAssistant != null &&
            LocalToolsService.isAvailableOnThisPlatform(name) &&
            LocalToolsService.isEnabledForAssistant(name, liveAssistant);
        if (LocalToolNames.all.contains(name) && !localPermissionIsLive()) {
          return _toolError(
            error: 'permission_denied',
            message: 'This tool is disabled for the current assistant.',
            tool: name,
          );
        }

        // Search tool
        if (name == SearchToolService.toolName &&
            liveAssistant?.searchEnabled == true) {
          final query = args['query'];
          if (query is! String || query.trim().isEmpty) {
            return _toolError(
              error: 'invalid_arguments',
              message: 'query must be a non-empty string.',
              tool: name,
            );
          }
          final q = query.trim();
          return await SearchToolService.executeSearch(q, settings);
        }

        // Memory tools
        final memoryResult = await _handleMemoryToolCall(
          name,
          args,
          liveAssistant,
          conversationId: conversationId,
        );
        ensureLiveToolCall();
        if (memoryResult != null) {
          return memoryResult;
        }

        // A browser action turned off in Settings > Browser is rejected
        // before it ever reaches an approval prompt.
        if (name == LocalToolNames.browserUse &&
            settings.disabledBrowserActions.contains(
              (args['action'] ?? '').toString().trim().toLowerCase(),
            )) {
          return jsonEncode({
            'ok': false,
            'error': 'action_disabled',
            'message':
                'The browser_use action "${args['action']}" is turned off in Settings > Browser.',
          });
        }

        // Mutations require consent unless the saved global full access is on.
        if (name != LocalToolNames.reportProblem &&
            name != LocalToolNames.mcpManager &&
            name != LocalToolNames.spendControl &&
            LocalToolNames.requiresApprovalFor(name, args) &&
            localPermissionIsLive() &&
            !settings.toolAutoApproveAll) {
          if (approvalService == null) {
            return _toolError(
              error: 'approval_unavailable',
              message: 'This action requires the user\'s confirmation.',
              tool: name,
            );
          }
          approvalService.setAutoApproveAll(false);
          if (name == LocalToolNames.browserUse) {
            BrowserAgentSession.instance.setOwnerConversationId(conversationId);
          }
          final approval = await approvalService.requestApproval(
            toolCallId: approvalIdFor(name, toolCallId),
            toolName: name,
            arguments: name == LocalToolNames.assistantManager
                ? publicAssistantArguments(args)
                : args,
            conversationId: conversationId,
          );
          ensureLiveToolCall();
          if (!approval.approved) {
            return _toolError(
              error: 'approval_denied',
              message: approval.denyReason ?? 'User denied the tool call',
              tool: name,
            );
          }
        }
        if (LocalToolNames.all.contains(name)) {
          final current = assistant == null
              ? null
              : assistantProvider.getById(assistant.id);
          if (current == null ||
              !LocalToolsService.isEnabledForAssistant(name, current)) {
            return _toolError(
              error: 'permission_denied',
              message: 'This tool was disabled while awaiting confirmation.',
              tool: name,
            );
          }
        }
        if (name == LocalToolNames.browserUse &&
            settings.disabledBrowserActions.contains(
              (args['action'] ?? '').toString().trim().toLowerCase(),
            )) {
          return jsonEncode({
            'ok': false,
            'error': 'action_disabled',
            'message':
                'This browser action is turned off in Settings > Browser.',
          });
        }

        // Re-read phone-control permission on every call so disabling it also
        // stops a tool loop that was built with an older assistant snapshot.
        if (name == LocalToolNames.phoneControl) {
          final current = assistant == null
              ? null
              : assistantProvider.getById(assistant.id);
          if (current == null || !current.localToolIds.contains(name)) {
            return _toolError(
              error: 'permission_denied',
              message: 'Phone control is disabled for this assistant.',
              tool: name,
            );
          }
        }

        if (name == LocalToolNames.reportProblem) {
          bool isEnabled() {
            final current = assistant == null
                ? null
                : assistantProvider.getById(assistant.id);
            return current != null &&
                LocalToolsService.isEnabledForAssistant(name, current) &&
                LocalToolsService.isAvailableOnThisPlatform(name);
          }

          if (!isEnabled()) {
            return _toolError(
              error: 'permission_denied',
              message: 'Problem reports are disabled for this assistant.',
              tool: name,
            );
          }
          if (!settings.toolAutoApproveAll) {
            if (approvalService == null) {
              return _toolError(
                error: 'approval_unavailable',
                message: 'A problem report requires the user\'s confirmation.',
                tool: name,
              );
            }
            // The settings value changes before the provider's next rebuild.
            approvalService.setAutoApproveAll(false);
            final approval = await approvalService.requestApproval(
              toolCallId: approvalIdFor(name, toolCallId),
              toolName: name,
              arguments: const {},
              conversationId: conversationId,
            );
            ensureLiveToolCall();
            if (!approval.approved) {
              return _toolError(
                error: 'approval_denied',
                message: approval.denyReason ?? 'User denied the tool call',
                tool: name,
              );
            }
          }
          ensureLiveToolCall();
          if (!isEnabled()) {
            return _toolError(
              error: 'permission_denied',
              message: 'Problem reports are disabled for this assistant.',
              tool: name,
            );
          }
          return jsonEncode(
            await ProblemReportService().create(
              settings: settings,
              mcp: mcp,
              environment: _optional<EnvironmentProvider>(),
              checkCancelled: ensureLiveToolCall,
            ),
          );
        }

        if (name == LocalToolNames.mcpManager) {
          void checkAllowed() {
            ensureLiveToolCall();
            final current = assistant == null
                ? null
                : assistantProvider.getById(assistant.id);
            if (current == null ||
                !LocalToolsService.isEnabledForAssistant(name, current)) {
              throw StateError('permission_denied');
            }
          }

          try {
            checkAllowed();
          } catch (_) {
            return _toolError(
              error: 'permission_denied',
              message: 'MCP management is disabled for this assistant.',
              tool: name,
            );
          }
          approvalService?.setAutoApproveAll(settings.toolAutoApproveAll);
          final conversation = conversationId == null
              ? null
              : _optional<ChatService>()?.getConversation(conversationId);
          final binding = conversation != null
              ? WorkspaceBinding.fromExtras(conversation.extras)
              : (workspaceContext?.skillsOnly == false
                    ? workspaceContext!.binding
                    : null);
          return McpManagerTool(
            provider: mcp,
            assistants: assistantProvider,
            chat: _optional<ChatService>(),
            currentAssistantId: conversation?.assistantId ?? assistant?.id,
            defaultWorkspaceId: binding?.isBound == true
                ? binding!.workspaceId
                : null,
            approvals: approvalService,
            autoApproveAll: settings.toolAutoApproveAll,
            checkAllowed: checkAllowed,
          ).execute(
            args,
            toolCallId: approvalIdFor(name, toolCallId),
            conversationId: conversationId,
          );
        }

        if (name == LocalToolNames.spendControl) {
          final chats = _optional<ChatService>();
          if (chats == null ||
              conversationId == null ||
              chats.getConversation(conversationId) == null) {
            return _toolError(
              error: 'no_conversation',
              message: 'Spend control needs an existing chat.',
              tool: name,
            );
          }
          void checkAllowed() {
            ensureLiveToolCall();
            final current = assistant == null
                ? null
                : assistantProvider.getById(assistant.id);
            if (current == null ||
                !LocalToolsService.isEnabledForAssistant(name, current) ||
                chats.getConversation(conversationId) == null) {
              throw StateError('permission_denied');
            }
          }

          final compress = compactContext;
          return SpendControlTool(
            settings: settings,
            approvals: approvalService,
            checkAllowed: checkAllowed,
            readStatus: () =>
                SpendControlService(chats: chats, settings: settings).status(
                  conversationId,
                  assistant: assistant == null
                      ? null
                      : assistantProvider.getById(assistant.id),
                ),
            compact: compress == null
                ? null
                : () => compress(conversationId, checkAllowed: checkAllowed),
          ).execute(
            args,
            toolCallId: approvalIdFor(name, toolCallId),
            conversationId: conversationId,
          );
        }

        if (name == LocalToolNames.assistantManager &&
            assistant != null &&
            LocalToolsService.isEnabledForAssistant(name, assistant)) {
          // Changes are only made after the approval prompt above; a caller
          // without one (e.g. a background run) may only read.
          if (!settings.toolAutoApproveAll &&
              approvalService == null &&
              AssistantManagerTool.requiresApproval(args)) {
            return _toolError(
              error: 'approval_unavailable',
              message:
                  'Changing assistants needs the user\'s confirmation, '
                  'which is not available here.',
              tool: name,
            );
          }
          return AssistantManagerTool(
            assistants: assistantProvider,
            catalog: _assistantManagerCatalog(settings, mcp),
            callerAssistantId: assistant.id,
          ).execute(args);
        }

        if (name == LocalToolNames.scheduledTasks &&
            assistant != null &&
            LocalToolsService.isEnabledForAssistant(name, assistant)) {
          // Changes are only made after the approval prompt above; a caller
          // without one (e.g. a background run) may only read.
          if (!settings.toolAutoApproveAll &&
              approvalService == null &&
              ScheduledTaskTool.requiresApproval(args)) {
            return _toolError(
              error: 'approval_unavailable',
              message:
                  'Changing scheduled tasks needs the user\'s confirmation, '
                  'which is not available here.',
              tool: name,
            );
          }
          final service = ScheduledTasksService.instance;
          return ScheduledTaskTool(
            tasks: () async {
              if (!service.loaded) await service.refresh();
              return service.tasks;
            },
            save: service.save,
            delete: service.delete,
            assistantNames: {
              for (final a in assistantProvider.assistants) a.id: a.name,
            },
            callerAssistantId: assistant.id,
            conversationId: conversationId,
          ).execute(args);
        }

        if (name == LocalToolNames.rootShell &&
            assistant != null &&
            LocalToolsService.isEnabledForAssistant(name, assistant)) {
          // Commands that change anything are approved first; a caller
          // without the prompt (e.g. a background run) may only read. The
          // permission is read again so turning it off stops a tool loop.
          final current = assistantProvider.getById(assistant.id);
          if (current == null || !current.localToolIds.contains(name)) {
            return _toolError(
              error: 'permission_denied',
              message: 'Root commands are disabled for this assistant.',
              tool: name,
            );
          }
          if (!settings.toolAutoApproveAll &&
              approvalService == null &&
              LocalToolNames.requiresApprovalFor(name, args)) {
            return _toolError(
              error: 'approval_unavailable',
              message:
                  'Root commands that change something need the user\'s '
                  'confirmation, which is not available here.',
              tool: name,
            );
          }
          return const RootShellTool().execute(args);
        }

        if (name == LocalToolNames.miniApps &&
            assistant != null &&
            LocalToolsService.isEnabledForAssistant(name, assistant)) {
          // Deleting is only done after the approval prompt above; a caller
          // without one (e.g. a background run) may not delete.
          if (!settings.toolAutoApproveAll &&
              approvalService == null &&
              MiniAppDataTool.requiresApproval(args)) {
            return _toolError(
              error: 'approval_unavailable',
              message:
                  'Deleting mini apps or jobs needs the user\'s confirmation, '
                  'which is not available here.',
              tool: name,
            );
          }
          return invokeMiniApp(
            name,
            toolCallId,
            (invocation) => MiniAppDataTool(
              store: _miniApps.store,
              jobs: MiniAppLauncher.jobs,
              serverStatus: MiniAppLauncher.servers.status,
              runtime: _miniApps,
              invocation: invocation,
            ).execute(args),
          );
        }

        if (name == LocalToolNames.browserUse &&
            '${args['action']}'.trim().toLowerCase() == 'export_cookies') {
          return _exportBrowserCookies(
            conversationId,
            approvalService,
            fullAccess: settings.toolAutoApproveAll,
          );
        }

        // Local tools
        final localResult = await LocalToolsService.tryHandleToolCall(
          name,
          args,
          assistant,
          disabledBrowserActions: settings.disabledBrowserActions,
          conversationId: conversationId,
          onSpeakText: (text) async {
            final tts = contextProvider.read<TtsProvider>();
            if (!tts.isAvailable) {
              throw StateError('Text-to-speech is unavailable.');
            }
            unawaited(
              tts.speak(text).catchError((Object error, StackTrace stack) {
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    stack: stack,
                    library: 'Kelivo local tools',
                    context: ErrorDescription('while playing text-to-speech'),
                  ),
                );
              }),
            );
          },
        );
        if (localResult != null) {
          if (name == LocalToolNames.phoneControl &&
              assistant != null &&
              RootPhoneControl.accessibilityUnavailable(localResult) &&
              (assistantProvider
                      .getById(assistant.id)
                      ?.localToolIds
                      .contains(LocalToolNames.rootShell) ??
                  false)) {
            // Accessibility is off; root can still read and drive the screen.
            return RootPhoneControl(
              setClipboard: (text) =>
                  Clipboard.setData(ClipboardData(text: text)),
            ).execute(args);
          }
          if (name == LocalToolNames.browserUse) {
            return BrowserAgentTool.forModel(localResult);
          }
          return localResult;
        }

        if (name == LocalToolNames.askUser &&
            assistant != null &&
            assistant.localToolIds.contains(LocalToolNames.askUser)) {
          if (askUserService == null) {
            return _toolError(
              error: 'ask_user_unavailable',
              message: 'Ask user interaction service is unavailable.',
              tool: name,
            );
          }
          try {
            final result = await askUserService.requestAnswer(
              toolCallId: (toolCallId?.trim().isNotEmpty == true)
                  ? toolCallId!.trim()
                  : '${name}_${DateTime.now().microsecondsSinceEpoch}',
              arguments: args,
              conversationId: conversationId,
            );
            ensureLiveToolCall();
            final current = assistantProvider.getById(assistant.id);
            if (current == null || !current.localToolIds.contains(name)) {
              return _toolError(
                error: 'permission_denied',
                message: 'Ask user was disabled while awaiting an answer.',
                tool: name,
              );
            }
            return result.toJsonString();
          } on AskUserInvalidRequestException catch (e) {
            return _toolError(
              error: 'invalid_ask_user_request',
              message: e.message,
              tool: name,
            );
          }
        }

        return await approveAndExecuteMcp(name, args, toolCallId: toolCallId);
      } catch (e) {
        // Catch unexpected exceptions and return error JSON to LLM
        // This prevents tool failures from terminating the chat flow
        privacy.capture(mcp);
        return _toolError(
          error: 'execution_error',
          message: privacy.text(e.toString()),
          tool: privacy.text(name),
          instruction:
              'The tool execution failed unexpectedly. You may try again with different parameters or inform the user about the issue.',
        );
      }
    }

    return ToolCallArgumentPrivacy.register(handler, (name, args) {
      final publicName = args['value'];
      if (name == '__mcp_private_name__' &&
          publicName is String &&
          (BuiltInToolNames.all.contains(publicName) ||
              routes.containsExposedName(publicName))) {
        return args;
      }
      if (name == LocalToolNames.mcpManager) {
        privacy.capture(mcp);
        return privacy.managerArgumentsForModel(
          args,
          publicIds: [
            ...assistantProvider.assistants.map((assistant) => assistant.id),
            ...?_optional<WorkspaceProvider>()?.workspaces.map(
              (workspace) => workspace.id,
            ),
          ],
        );
      }
      if (name == LocalToolNames.assistantManager) {
        return publicAssistantArguments(args);
      }
      if (routes.containsExposedName(name) ||
          !BuiltInToolNames.all.contains(name)) {
        privacy.capture(mcp);
        return privacy.argumentsForModel(args);
      }
      return args;
    });
  }

  AcpAgentManager? _agentManager() {
    try {
      return contextProvider.read<AcpAgentManager>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  AssistantManagerCatalog _assistantManagerCatalog(
    SettingsProvider settings,
    McpProvider mcp,
  ) {
    final configs = settings.providerConfigs;
    final privacy = McpToolPrivacy(mcp);
    final keys = [
      ...settings.providersOrder.where(configs.containsKey),
      ...configs.keys.where((k) => !settings.providersOrder.contains(k)),
    ];
    return AssistantManagerCatalog(
      providers: [
        for (final key in keys)
          AssistantManagerProvider(
            key: key,
            name: configs[key]!.name,
            enabled: configs[key]!.enabled,
            models: configs[key]!.models,
          ),
      ],
      mcpServers: [
        for (final server in mcp.configuredServers)
          AssistantManagerOption(
            id: server.id,
            name: privacy.text(server.name),
            enabled: server.enabled,
          ),
      ],
      skills: [
        for (final skill in contextProvider.read<SkillsService>().skills)
          AssistantManagerOption(
            id: skill.record.id,
            name: skill.name,
            description: skill.description,
            enabled: skill.record.enabled,
          ),
      ],
      workspaces: [
        for (final workspace
            in contextProvider.read<WorkspaceProvider>().workspaces)
          AssistantManagerOption(id: workspace.id, name: workspace.name),
      ],
      agents: [
        if (_agentManager() case final agents?)
          for (final spec in agents.agents)
            AssistantManagerOption(
              id: spec.id,
              name: spec.name,
              enabled: agents.state(spec.id) == AcpInstallState.installed,
            ),
      ],
      localToolIds: [
        for (final id in LocalToolNames.all)
          if (LocalToolsService.isAvailableOnThisPlatform(id) &&
              id != LocalToolNames.browserUse)
            id,
      ],
    );
  }

  /// browser_use export_cookies: the open site's cookies as a file in the
  /// chat folder of the conversation's workspace, for the terminal. Only
  /// after the user's approval, which [handleToolCall] asked for already.
  Future<String> _exportBrowserCookies(
    String? conversationId,
    ToolApprovalService? approvalService, {
    required bool fullAccess,
  }) async {
    if (approvalService == null && !fullAccess) {
      return _toolError(
        error: 'approval_unavailable',
        message:
            'Exporting cookies needs the user\'s confirmation, which is not '
            'available here.',
        tool: LocalToolNames.browserUse,
      );
    }
    final session = BrowserAgentSession.instance;
    if (!session.isAttached) {
      return _toolError(
        error: 'browser_not_open',
        message: 'Open the site in the browser first.',
        tool: LocalToolNames.browserUse,
      );
    }
    final ctx = await WorkspaceToolsService.resolve(
      conversationId: conversationId,
      workspaceProvider: contextProvider.read<WorkspaceProvider>(),
      runtimeProvider: contextProvider.read<WorkspaceRuntimeProvider>(),
      chatService: contextProvider.read<ChatService>(),
    );
    if (ctx == null) {
      return _toolError(
        error: 'workspace_required',
        message:
            'Cookies go to the terminal of a workspace; this chat has none.',
        tool: LocalToolNames.browserUse,
      );
    }
    return jsonEncode(
      await BrowserCookieExport.export(
        pageUrl: await session.controller?.currentUrl(),
        hostDir: ctx.sessionDir,
        modelDir: ctx.paths.modelSessionDir,
      ),
    );
  }

  /// Handle memory tool calls (§10).
  ///
  /// Returns null if the tool is not a memory tool or the relevant gate is off.
  Future<String?> _handleMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant, {
    String? conversationId,
  }) async {
    final settings = contextProvider.read<SettingsProvider>();
    if (settings.legacyMemoryMode) {
      if (MemoryTools.allToolNames.contains(name)) return null;
      return _handleLegacyMemoryToolCall(
        name,
        args,
        assistant,
        conversationId: conversationId,
      );
    }

    if (assistant == null) return null;
    if (!MemoryTools.allToolNames.contains(name)) return null;

    final memoryV2 = contextProvider.read<MemoryProviderV2>();
    ChatService? chatService;
    try {
      chatService = contextProvider.read<ChatService>();
    } catch (_) {
      chatService = null;
    }

    MemoryPipelineService? pipeline;
    try {
      pipeline = contextProvider.read<MemoryPipelineService>();
    } catch (_) {
      pipeline = null;
    }

    Future<String> Function(String prompt)? memoryLlmCall;
    final provKey = settings.memoryModelProvider;
    final mdlId = settings.memoryModelId;
    if (provKey != null && mdlId != null) {
      final cfg = settings.getProviderConfig(provKey);
      final budget = settings.memoryModelThinkingEnabled
          ? (assistant.thinkingBudget ?? settings.thinkingBudget)
          : 0;
      memoryLlmCall = (prompt) => ChatApiService.generateText(
        conversationId: conversationId,
        config: cfg,
        modelId: mdlId,
        prompt: prompt,
        thinkingBudget: budget,
      );
    }

    final temporary =
        chatService?.isTemporaryConversation(conversationId) ?? false;
    return MemoryTools.handle(
      name: name,
      args: args,
      assistant: assistant,
      repository: memoryV2.repository,
      chatRepository: memoryV2.chatRepository,
      chatService: chatService,
      conversationId: conversationId,
      // Reload without changing which assistants the open memory UI is showing.
      onMutated: memoryV2.reloadCurrentScope,
      smartAdd: pipeline?.smartAdd,
      promptLang: settings.resolvedMemoryPromptLang,
      memoryLlmCall: memoryLlmCall,
      smartAddPromptZh: settings.memorySmartAddPromptZh,
      smartAddPromptEn: settings.memorySmartAddPromptEn,
      // Temporary chats are discarded on exit; their tool traces must not linger.
      traceRecorder: temporary ? null : pipeline?.traceRecorder,
      conversationTitle: conversationId == null
          ? null
          : chatService?.getConversation(conversationId)?.title,
    );
  }

  /// Handle legacy create/edit/delete_memory calls via [MemoryProvider].
  ///
  /// Returns null if memory is disabled or [name] is not a legacy memory tool.
  Future<String?> _handleLegacyMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant, {
    String? conversationId,
  }) async {
    if (assistant?.enableMemory != true) return null;
    if (name != 'create_memory' &&
        name != 'edit_memory' &&
        name != 'delete_memory') {
      return null;
    }

    try {
      if (_optional<ChatService>()?.isTemporaryConversation(conversationId) ??
          false) {
        return _toolError(
          error: 'temporary_conversation',
          message: 'Memory cannot be written from a temporary conversation.',
          tool: name,
        );
      }
      final mp = contextProvider.read<MemoryProvider>();

      if (name == 'create_memory') {
        final content = args['content'];
        if (content is! String || content.isEmpty) {
          return _toolError(
            error: 'invalid_memory_content',
            message: 'Memory content must be a non-empty string.',
            tool: name,
          );
        }
        final m = await mp.add(assistantId: assistant!.id, content: content);
        return m.content;
      } else if (name == 'edit_memory') {
        final id = args['id'];
        final content = args['content'];
        if (id is! num || !id.isFinite || id <= 0 || id != id.toInt()) {
          return _toolError(
            error: 'invalid_memory_id',
            message: 'Memory id must be a positive integer.',
            tool: name,
          );
        }
        if (content is! String || content.isEmpty) {
          return _toolError(
            error: 'invalid_memory_content',
            message: 'Memory content must be a non-empty string.',
            tool: name,
          );
        }
        final m = await mp.update(
          id: id.toInt(),
          content: content,
          assistantId: assistant!.id,
        );
        if (m == null) {
          return _toolError(
            error: 'memory_not_found',
            message: 'No memory record was found for id $id.',
            tool: name,
            instruction:
                'Use the available memory records shown in context, or create a new memory instead of editing a missing one.',
          );
        }
        return m.content;
      } else if (name == 'delete_memory') {
        final id = args['id'];
        if (id is! num || !id.isFinite || id <= 0 || id != id.toInt()) {
          return _toolError(
            error: 'invalid_memory_id',
            message: 'Memory id must be a positive integer.',
            tool: name,
          );
        }
        final ok = await mp.delete(id: id.toInt(), assistantId: assistant!.id);
        if (!ok) {
          return _toolError(
            error: 'memory_not_found',
            message: 'No memory record was found for id $id.',
            tool: name,
            instruction:
                'Use the available memory records shown in context, or skip deleting a missing memory.',
          );
        }
        return 'deleted';
      }
    } catch (e) {
      return _toolError(
        error: 'memory_execution_error',
        message: e.toString(),
        tool: name,
        instruction:
            'The memory tool failed. Retry only after correcting the parameters, or inform the user about the issue.',
      );
    }

    return null;
  }
}
