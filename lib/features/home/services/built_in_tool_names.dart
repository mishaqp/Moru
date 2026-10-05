import '../../../core/services/memory/memory_tools.dart';
import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import 'local_tools_service.dart';

/// Client-side built-in function names that MCP tools must not expose.
///
/// Static tools and installed app actions are reserved regardless of the
/// assistant's switches, so an external MCP server cannot impersonate them.
abstract final class BuiltInToolNames {
  static Set<String> get all => {
    SearchToolService.toolName,
    'builtin_search',
    ...MemoryTools.allToolNames,
    ...MemoryTools.legacyToolNames,
    ...LocalToolNames.all,
    ...WorkspaceToolsService.toolNames,
    for (final app in MiniAppStore.instance.apps)
      for (final action in app.actions)
        MiniAppRuntime.toolNameFor(app.id, action.name),
  };
}
