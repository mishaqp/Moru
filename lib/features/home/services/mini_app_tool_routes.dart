import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';

/// Binds offered schemas to the installed app version for one model reply.
/// A replacement cannot silently change the meaning of an already offered tool.
class MiniAppToolRouteSnapshot {
  MiniAppToolRouteSnapshot._(this.definitions, this.bindings);

  final List<Map<String, dynamic>> definitions;
  final Map<String, ({MiniApp app, String actionName})> bindings;

  factory MiniAppToolRouteSnapshot.capture(MiniAppRuntime runtime) {
    final definitions = runtime.toolDefinitions();
    return MiniAppToolRouteSnapshot._(
      List.unmodifiable(definitions),
      Map.unmodifiable({
        for (final definition in definitions)
          if (definition['function']['name'] case final String name)
            if (runtime.resolveTool(name) case final binding?)
              name: (app: binding.app, actionName: binding.actionName),
      }),
    );
  }

  Set<String> get names => bindings.keys.toSet();

  List<Map<String, dynamic>> currentDefinitions(MiniAppStore store) => [
    for (final definition in definitions)
      if (bindings[definition['function']['name']] case final binding?)
        if (identical(store.byId(binding.app.id), binding.app)) definition,
  ];
}
