import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

import 'business_test_harness.dart';

/// An agent manager with no Linux environment, for screens that show agents.
AcpAgentManager createTestAcpAgentManager() => AcpAgentManager(
  preferences: createBusinessTestPreferences(),
  runtimeProvider: WorkspaceRuntimeProvider(),
  environment: EnvironmentProvider(
    preferences: createBusinessTestPreferences(),
  ),
);
