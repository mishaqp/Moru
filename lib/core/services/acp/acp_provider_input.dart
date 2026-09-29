import '../../providers/model_provider.dart' show Modality;
import '../../providers/settings_provider.dart';
import '../api/chat_api_helpers.dart';
import '../../utils/openai_model_compat.dart';
import 'acp_agent_catalog.dart';

/// The address, key and upstream model of a Moru provider's model, for an
/// agent to use. Null when the provider has no key to share (an OAuth login
/// or an empty key) or no address.
AcpProviderInput? acpProviderInputFor(
  SettingsProvider settings,
  String providerKey,
  String modelId,
) {
  final config = settings.getProviderConfig(providerKey);
  if (config.baseUrl.trim().isEmpty || config.isOAuth) return null;
  final apiKey = apiKeyForRequest(config, modelId).trim();
  if (apiKey.isEmpty) return null;
  final kind = ProviderConfig.classify(
    config.id,
    explicitType: config.providerType,
  );
  final override = config.modelOverrides[modelId];
  return AcpProviderInput(
    baseUrl: config.baseUrl,
    apiKey: apiKey,
    model: resolveApiModelIdOverride(
      override is Map ? override.cast<String, dynamic>() : null,
      modelId,
    ),
    anthropicProvider: kind == ProviderKind.claude,
    responsesApi: kind == ProviderKind.openai && config.useResponseApi == true,
    imageInput: effectiveModelInfo(
      config,
      modelId,
    ).input.contains(Modality.image),
    headers: {
      for (final header in config.customHeaders)
        if ((header['name'] ?? '').trim().isNotEmpty)
          header['name']!.trim(): header['value'] ?? '',
    },
  );
}
