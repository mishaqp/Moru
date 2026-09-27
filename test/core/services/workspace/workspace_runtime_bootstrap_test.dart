import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime_bootstrap.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_workspace_runtime.dart';

void main() {
  late EnvironmentProvider env;

  setUp(() {
    env = EnvironmentProvider(preferences: createBusinessTestPreferences());
  });

  test('createWorkspaceStack is empty outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final stack = await createWorkspaceStack(env: env);
    expect(stack.runtime, isNull);
    expect(stack.environmentManager, isNull);
    expect(stack.mirrors, isNull);
    expect(stack.dependencies, isNull);
  });

  test('applyWorkspaceStack registers the runtime', () {
    final runtime = FakeWorkspaceRuntime();
    final provider = WorkspaceRuntimeProvider();
    applyWorkspaceStack(provider, WorkspaceStack(runtime: runtime));
    expect(provider.runtime, same(runtime));
  });
}
