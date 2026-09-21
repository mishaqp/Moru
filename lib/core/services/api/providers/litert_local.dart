import 'dart:async';

import 'package:dio/dio.dart';

import '../../../providers/settings_provider.dart';
import '../../local/local_model_runtime.dart';
import '../stream/stream_chunk.dart';

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
Stream<StreamChunk> sendLiteRtStream({
  required ProviderConfig config,
  required String modelId,
  required List<Map<String, dynamic>> messages,
  required String conversationId,
  required CancelToken sessionToken,
}) {
  final overrides = config.modelOverrides[modelId] as Map?;
  final modelPath = overrides?['localModelPath']?.toString();
  if (modelPath == null || modelPath.isEmpty) {
    return Stream<StreamChunk>.error(
      StateError(
        'No local model file is configured for "$modelId". Install or '
        'import a model first.',
      ),
    );
  }
  final backend = (overrides?['localBackend']?.toString() ?? 'cpu');
  return LocalModelRuntime.instance.generate(
    conversationId: conversationId,
    modelPath: modelPath,
    backend: backend,
    messages: messages,
    whenCancelled: sessionToken.whenCancel.then((_) {}),
    isCancelled: () => sessionToken.isCancelled,
  );
}
