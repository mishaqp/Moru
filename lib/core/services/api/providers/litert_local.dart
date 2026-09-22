import 'dart:async';

import 'package:dio/dio.dart';

import '../../../providers/settings_provider.dart';
import '../../local/local_model_runtime.dart';
import '../chat_api_helpers.dart';
import '../stream/stream_chunk.dart';

final class LiteRtRuntimeOptions {
  const LiteRtRuntimeOptions({
    required this.backend,
    required this.maxNumTokens,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.maxOutputTokens,
    required this.thinkingEnabled,
    required this.thinkingBudget,
    required this.visionEnabled,
    required this.audioEnabled,
    required this.toolsEnabled,
    required this.keepLoaded,
  });

  final String backend;
  final int? maxNumTokens;
  final double temperature;
  final int topK;
  final double topP;
  final int? maxOutputTokens;
  final bool thinkingEnabled;
  final int? thinkingBudget;
  final bool visionEnabled;
  final bool audioEnabled;
  final bool toolsEnabled;
  final bool keepLoaded;
}

/// Local (on-device) generation via the `LiteRT-LM` engine, dispatched from
/// `ChatApiService._sendOnce` for `ProviderKind.local`. Deliberately not
/// HTTP-shaped: no `http.Client`, no OAuth, no proxy, no vendor headers, no
/// network retry -- [ChatApiService] already skips all of that for this
/// kind before calling here (see the `kind == ProviderKind.local` branch).
///
/// [modelId] must have a matching entry in [ProviderConfig.modelOverrides]
/// carrying the installed model's absolute file path under
/// `localModelPath` (populated by the model-management UI, not yet built in
/// this slice) and, optionally, `localBackend` ("cpu"/"gpu", default "cpu"
/// -- GPU is opt-in, never auto-enabled just because it was detected, per
/// the task brief).
///
/// [isConversationTurn] disambiguates two very different callers that both
/// happen to pass the real conversation's id as [conversationId]:
///  - the actual next turn of an ongoing conversation (`true`) -- reusing
///    [LocalModelRuntime]'s native `Conversation` across turns is exactly
///    the point.
///  - a one-shot utility prompt -- title/summary/translation/OCR/memory-
///    organize/chat-suggestions/etc. (`false`, the default) -- these are
///    unrelated single-message prompts that are tagged with the real
///    conversation's id purely for logging/grouping, not because they
///    continue it. See [LocalModelRuntime.generate]'s own doc comment for
///    what [LocalModelRuntime] does with this: it never lets a background
///    call reuse or overwrite a real conversation's native context, and
///    never lets one evict the model the user's own conversation already
///    has loaded.
Stream<StreamChunk> sendLiteRtStream({
  required ProviderConfig config,
  required String modelId,
  required List<Map<String, dynamic>> messages,
  required String conversationId,
  required CancelToken sessionToken,
  List<String>? userImagePaths,
  int? thinkingBudget,
  double? temperature,
  double? topP,
  int? maxTokens,
  List<Map<String, dynamic>>? tools,
  ToolCallHandler? onToolCall,
  bool isConversationTurn = false,
}) {
  final overrides = resolveLiteRtModelOverride(config, modelId);
  final modelPath = overrides?['localModelPath']?.toString();
  if (modelPath == null || modelPath.isEmpty) {
    return Stream<StreamChunk>.error(
      StateError(
        'No local model file is configured for "$modelId". Install or '
        'import a model first.',
      ),
    );
  }
  final options = resolveLiteRtRuntimeOptions(
    overrides,
    thinkingBudget: thinkingBudget,
    temperature: temperature,
    topP: topP,
    maxTokens: maxTokens,
  );
  final activeTools = options.toolsEnabled && onToolCall != null
      ? (tools ?? const <Map<String, dynamic>>[])
      : const <Map<String, dynamic>>[];
  return LocalModelRuntime.instance.generate(
    conversationId: conversationId,
    modelPath: modelPath,
    backend: options.backend,
    messages: messages,
    whenCancelled: sessionToken.whenCancel.then((_) {}),
    isCancelled: () => sessionToken.isCancelled,
    isConversationTurn: isConversationTurn,
    maxNumTokens: options.maxNumTokens,
    temperature: options.temperature,
    topK: options.topK,
    topP: options.topP,
    maxOutputTokens: options.maxOutputTokens,
    thinkingEnabled: options.thinkingEnabled,
    thinkingBudget: options.thinkingBudget,
    visionEnabled: options.visionEnabled,
    audioEnabled: options.audioEnabled,
    tools: activeTools,
    onToolCall: activeTools.isEmpty ? null : onToolCall,
    keepLoaded: options.keepLoaded,
    additionalMediaPaths: userImagePaths ?? const [],
  );
}

LiteRtRuntimeOptions resolveLiteRtRuntimeOptions(
  Map? overrides, {
  int? thinkingBudget,
  double? temperature,
  double? topP,
  int? maxTokens,
}) {
  final backend = overrides?['localBackend']?.toString() == 'gpu'
      ? 'gpu'
      : 'cpu';
  final context = _positiveInt(overrides?['localMaxNumTokens']);
  final configuredTemperature = _nonNegativeDouble(
    overrides?['localTemperature'],
  );
  final configuredTopK = _positiveInt(overrides?['localTopK']);
  final configuredTopP = _probability(overrides?['localTopP']);
  final configuredThinkingBudget = _thinkingBudget(
    overrides?['localThinkingBudget'],
  );
  final requestThinkingBudget = _thinkingBudget(thinkingBudget);
  final resolvedThinkingBudget =
      configuredThinkingBudget ?? requestThinkingBudget;
  final canThink = overrides?['localThinking'] == true;

  return LiteRtRuntimeOptions(
    backend: backend,
    maxNumTokens: context,
    temperature:
        configuredTemperature ?? _nonNegativeDouble(temperature) ?? 1.0,
    topK: configuredTopK ?? 64,
    topP: configuredTopP ?? _probability(topP) ?? 0.95,
    maxOutputTokens: _positiveInt(maxTokens),
    thinkingEnabled: canThink && resolvedThinkingBudget != 0,
    thinkingBudget: canThink ? (resolvedThinkingBudget ?? -1) : null,
    visionEnabled: overrides?['localVision'] == true,
    audioEnabled: overrides?['localAudio'] == true,
    toolsEnabled: overrides?['localTools'] == true,
    keepLoaded: overrides?['localKeepLoaded'] != false,
  );
}

int? _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _thinkingBudget(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= -1 ? parsed : null;
}

double? _nonNegativeDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}

double? _probability(Object? value) {
  final parsed = _nonNegativeDouble(value);
  return parsed != null && parsed <= 1 ? parsed : null;
}

/// Resolves a local model's metadata while keeping chats created by older
/// test builds usable. Those builds assigned a fresh UUID after each import;
/// if only one local model remains, its selection is unambiguous.
Map? resolveLiteRtModelOverride(ProviderConfig config, String modelId) {
  final exact = config.modelOverrides[modelId] as Map?;
  if (exact != null) return exact;

  // Older builds assigned a random UUID on every import. A chat could keep
  // that stale UUID after the same model was reimported. When exactly one
  // local model is installed there is no ambiguity, so keep the chat usable
  // and resolve it to that sole installed model.
  if (config.models.length != 1) return null;
  return config.modelOverrides[config.models.single] as Map?;
}
