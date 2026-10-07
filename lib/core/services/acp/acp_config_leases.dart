import 'dart:async';

import '../workspace/workspace_runtime.dart';
import 'acp_agent_catalog.dart';

/// Shared settings survive until every process using that runtime/path exits.
/// A new writer also waits for an earlier last-owner deletion to finish.
class AcpConfigLeases {
  final Map<WorkspaceRuntime, Map<String, _ConfigOwners>> _runtimes =
      Map.identity();

  Future<Future<void> Function()> acquire(
    WorkspaceRuntime runtime,
    Iterable<AcpConfigFile> files,
    Future<void> Function(List<String> paths) remove,
  ) async {
    final states = _runtimes.putIfAbsent(runtime, () => {});
    final owned = <String, _ConfigOwners>{};
    for (final path
        in files
            .where((file) => file.temporary)
            .map((file) => file.path)
            .toSet()) {
      final state = states.putIfAbsent(path, _ConfigOwners.new);
      while (state.deleting != null) {
        await state.deleting;
      }
      state.count++;
      owned[path] = state;
    }
    Future<void>? released;
    Future<void> release() => released ??= () async {
      final deleting = <String, _ConfigOwners>{};
      final completed = Completer<void>();
      for (final entry in owned.entries) {
        if (--entry.value.count == 0) {
          entry.value.deleting = completed.future;
          deleting[entry.key] = entry.value;
        }
      }
      try {
        if (deleting.isNotEmpty) await remove(deleting.keys.toList());
      } catch (_) {
        // Cleanup output/errors may contain credentials. Never publish them or
        // let an asynchronous close report an unhandled exception.
      } finally {
        for (final state in deleting.values) {
          state.deleting = null;
        }
        completed.complete();
      }
    }();
    return release;
  }
}

class _ConfigOwners {
  int count = 0;
  Future<void>? deleting;
}
