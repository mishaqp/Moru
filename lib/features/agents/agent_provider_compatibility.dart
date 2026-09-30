import '../../core/providers/settings_provider.dart';
import '../../core/services/acp/acp_agent_catalog.dart';

/// Codex requires Responses API even when Moru uses another chat API.
bool agentNeedsResponsesApiWarning(String? agentId, ProviderConfig? provider) {
  if (agentId != AcpAgentSpec.codexId || provider == null) return false;
  final kind = ProviderConfig.classify(
    provider.id,
    explicitType: provider.providerType,
  );
  return kind != ProviderKind.openai || provider.useResponseApi != true;
}
