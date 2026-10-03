import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/providers/assistant_provider.dart';
import '../../core/providers/workspace_provider.dart';
import '../../core/services/acp/acp_agent_catalog.dart';
import '../../core/services/acp/acp_agent_manager.dart';
import '../../core/services/workspace/workspace_runtime.dart';
import '../../shared/pages/webview/browser_mini_window.dart';
import 'agent_chat_start.dart';

/// Reuses the agent assistant's workspace without creating an empty chat.
Future<void> openAgentWeb(
  BuildContext context,
  AcpAgentSpec spec,
  AcpProviderInput provider,
) async {
  final assistants = context.read<AssistantProvider>();
  final workspaces = context.read<WorkspaceProvider>();
  final manager = context.read<AcpAgentManager>();
  final runtime = context.read<WorkspaceRuntimeProvider>().runtime;
  final assistant = await assistantForAgent(assistants, spec);
  await workspaces.loaded;
  var workspace = workspaces.byId(assistant.defaultWorkspaceId ?? '');
  if (workspace == null) {
    workspace = await workspaces.create(name: spec.name);
    await assistants.updateAssistant(
      assistant.copyWith(defaultWorkspaceId: workspace.id),
    );
  }
  final root = await workspaces.hostRootFor(workspace);
  final sandboxed = (await runtime?.status())?.sandboxed ?? true;
  await manager.webServers.open(
    spec,
    provider,
    cwd: sandboxed ? '/workspace' : root,
    mounts: sandboxed ? [Mount(host: root, guest: '/workspace')] : const [],
    openBrowser: (target) => openSharedBrowser(
      startUrl: target.url,
      authentication: target.authentication,
      newTab: true,
    ),
  );
}
