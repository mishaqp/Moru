import '../providers/settings_provider.dart';
import '../services/api/chat_api_helpers.dart';
import '../services/model_catalog/model_catalog.dart';
import '../services/model_override_payload_parser.dart';
import 'chat_message.dart';
import 'compress_context_options.dart';

/// Context window of well-known model families, used when the user has not
/// set one in the model settings. Unknown models return null.
int? inferContextWindowTokens(String modelId) {
  final id = modelId.toLowerCase().split('/').last;
  if (id.contains('claude')) return 200000;
  if (RegExp(r'gemini-(1\.5|2|3)').hasMatch(id)) return 1048576;
  if (id.startsWith('gpt-4.1')) return 1047576;
  if (id.startsWith('gpt-5')) return 400000;
  if (id.startsWith('gpt-4o') || id.startsWith('gpt-4-turbo')) return 128000;
  if (RegExp(r'^o[134](-|$)').hasMatch(id)) return 200000;
  if (id.startsWith('deepseek')) return 128000;
  if (id.startsWith('grok-4')) return 256000;
  return null;
}

/// The context window for [modelId] of [providerKey]: the model settings
/// value first, then [defaultContextWindowTokens] for the upstream id.
int? resolveContextWindowTokens(
  SettingsProvider settings,
  String providerKey,
  String modelId, {
  ModelCatalog? catalog,
}) {
  final cfg = settings.getProviderConfig(providerKey);
  final configured = readModelContextWindowTokens(
    ModelOverridePayloadParser.modelOverride(cfg.modelOverrides, modelId),
  );
  return configured ??
      defaultContextWindowTokens(apiModelId(cfg, modelId), catalog: catalog);
}

/// The window models.dev lists for [upstreamId], else the family default.
int? defaultContextWindowTokens(String upstreamId, {ModelCatalog? catalog}) =>
    (catalog ?? ModelCatalog.instance).lookup(upstreamId)?.contextTokens ??
    inferContextWindowTokens(upstreamId);

/// Tokens the next request starts from: the latest reply's prompt plus its
/// completion. Providers report the whole context each round, so the last
/// round's numbers already cover the history. Null when no reply in
/// [visible] (one message per slot, oldest first) has usage.
int? latestContextTokens(List<ChatMessage> visible) {
  for (var i = visible.length - 1; i >= 0; i--) {
    final m = visible[i];
    if (m.role != 'assistant') continue;
    final split = (m.promptTokens ?? 0) + (m.completionTokens ?? 0);
    final used = split > 0 ? split : (m.totalTokens ?? 0);
    if (used > 0) return used;
  }
  return null;
}
