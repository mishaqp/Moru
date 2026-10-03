import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime_bootstrap.dart';

import '../../../support/fake_workspace_runtime.dart';

void main() {
  test('applyWorkspaceStack registers the runtime', () {
    final runtime = FakeWorkspaceRuntime();
    final provider = WorkspaceRuntimeProvider();
    applyWorkspaceStack(provider, WorkspaceStack(runtime: runtime));
    expect(provider.runtime, same(runtime));
  });
}
