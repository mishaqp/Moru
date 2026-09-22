import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../utils/mcp_structured_image.dart';
import '../../utils/multimodal_input_utils.dart';
import '../api/chat_api_helpers.dart';
import '../api/stream/stream_chunk.dart';
import '../api/stream/stream_chunk_ids.dart';
import 'litert_channel.dart';

final class _EngineKey {
  const _EngineKey({
    required this.modelPath,
    required this.backend,
    required this.maxNumTokens,
    required this.visionEnabled,
    required this.audioEnabled,
  });

  final String modelPath;
  final String backend;
  final int? maxNumTokens;
  final bool visionEnabled;
  final bool audioEnabled;

  @override
  bool operator ==(Object other) =>
      other is _EngineKey &&
      other.modelPath == modelPath &&
      other.backend == backend &&
      other.maxNumTokens == maxNumTokens &&
      other.visionEnabled == visionEnabled &&
      other.audioEnabled == audioEnabled;

  @override
  int get hashCode => Object.hash(
    modelPath,
    backend,
    maxNumTokens,
    visionEnabled,
    audioEnabled,
  );
}

/// Owns the single in-memory LiteRT-LM engine for the whole app. Calls are
/// serialized through [_enqueue], matching the native manager's one-engine,
/// one-generation contract.
class LocalModelRuntime {
  LocalModelRuntime({LiteRtChannel? channel})
    : _channel = channel ?? LiteRtChannel();

  static final LocalModelRuntime instance = LocalModelRuntime();

  static const String _utilityConversationKey = '__moru_litert_utility__';
  static const int _maxToolCallsPerTurn = 25;

  final LiteRtChannel _channel;
  final Map<String, StreamController<LiteRtEvent>> _byRequestId = {};
  StreamSubscription<LiteRtEvent>? _eventSub;
  Future<void> _queue = Future<void>.value();

  _EngineKey? _loadedEngineKey;
  String? _activeConversationKey;
  String? _activeConversationSignature;
  List<Map<String, dynamic>>? _lastFullHistory;

  String? get loadedModelPath => _loadedEngineKey?.modelPath;

  void _ensureListening() {
    _eventSub ??= _channel.events.listen((event) {
      final requestId = switch (event) {
        LiteRtTextDelta(:final requestId) => requestId,
        LiteRtReasoningDelta(:final requestId) => requestId,
        LiteRtToolCalls(:final requestId) => requestId,
        LiteRtDone(:final requestId) => requestId,
        LiteRtError(:final requestId) => requestId,
        _ => null,
      };
      if (requestId != null) _byRequestId[requestId]?.add(event);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final started = _queue.then((_) => action());
    _queue = started.then((_) {}, onError: (_) {});
    return started;
  }

  Future<void> unload() => _enqueue(_unloadNow);

  Future<void> _unloadNow() async {
    if (_loadedEngineKey == null) return;
    await _channel.unloadModel();
    _clearLoadedState();
  }

  void _clearLoadedState() {
    _loadedEngineKey = null;
    _activeConversationKey = null;
    _activeConversationSignature = null;
    _lastFullHistory = null;
  }

  Stream<StreamChunk> generate({
    required String conversationId,
    required String modelPath,
    required String backend,
    required List<Map<String, dynamic>> messages,
    required Future<void> whenCancelled,
    required bool Function() isCancelled,
    bool isConversationTurn = true,
    int? maxNumTokens,
    double? temperature,
    int? topK,
    double? topP,
    int? maxOutputTokens,
    bool visionEnabled = false,
    bool audioEnabled = false,
    bool thinkingEnabled = false,
    int? thinkingBudget,
    List<Map<String, dynamic>> tools = const [],
    ToolCallHandler? onToolCall,
    bool keepLoaded = true,
    List<String> additionalMediaPaths = const [],
  }) {
    final controller = StreamController<StreamChunk>();
    final engineKey = _EngineKey(
      modelPath: modelPath,
      backend: backend,
      maxNumTokens: maxNumTokens,
      visionEnabled: visionEnabled,
      audioEnabled: audioEnabled,
    );
    unawaited(
      _enqueue(
        () => _runGenerate(
          controller: controller,
          conversationId: isConversationTurn
              ? conversationId
              : _utilityConversationKey,
          engineKey: engineKey,
          messages: messages,
          whenCancelled: whenCancelled,
          isCancelled: isCancelled,
          isConversationTurn: isConversationTurn,
          temperature: temperature,
          topK: topK,
          topP: topP,
          maxOutputTokens: maxOutputTokens,
          thinkingEnabled: thinkingEnabled,
          thinkingBudget: thinkingBudget,
          tools: tools,
          onToolCall: onToolCall,
          keepLoaded: keepLoaded,
          additionalMediaPaths: additionalMediaPaths,
        ),
      ).catchError((Object error, StackTrace stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          controller.close();
        }
      }),
    );
    return controller.stream;
  }

  Future<void> _ensureModelLoaded(_EngineKey requested) async {
    if (_loadedEngineKey == requested) return;
    if (_loadedEngineKey != null) {
      await _channel.unloadModel();
      _clearLoadedState();
    }
    await _channel.loadModel(
      modelPath: requested.modelPath,
      backend: requested.backend,
      maxNumTokens: requested.maxNumTokens,
      visionEnabled: requested.visionEnabled,
      audioEnabled: requested.audioEnabled,
    );
    _loadedEngineKey = requested;
  }

  ({String? systemInstruction, List<Map<String, dynamic>> history})
  _splitSystem(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    final history = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = (message['role'] ?? 'user').toString();
      if (role == 'system') {
        final text = _textFromContent(message['content']);
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.write(text);
        }
      } else {
        history.add(message);
      }
    }
    return (
      systemInstruction: buffer.isEmpty ? null : buffer.toString(),
      history: history,
    );
  }

  bool _sameHistory(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return a.toString() == b.toString();
    }
  }

  String _conversationSignature({
    required double? temperature,
    required int? topK,
    required double? topP,
    required int? maxOutputTokens,
    required bool thinkingEnabled,
    required int? thinkingBudget,
    required List<Map<String, dynamic>> tools,
  }) => jsonEncode({
    'temperature': temperature,
    'topK': topK,
    'topP': topP,
    'maxOutputTokens': maxOutputTokens,
    'thinkingEnabled': thinkingEnabled,
    'thinkingBudget': thinkingBudget,
    'tools': tools,
  });

  Future<void> _runGenerate({
    required StreamController<StreamChunk> controller,
    required String conversationId,
    required _EngineKey engineKey,
    required List<Map<String, dynamic>> messages,
    required Future<void> whenCancelled,
    required bool Function() isCancelled,
    required bool isConversationTurn,
    required double? temperature,
    required int? topK,
    required double? topP,
    required int? maxOutputTokens,
    required bool thinkingEnabled,
    required int? thinkingBudget,
    required List<Map<String, dynamic>> tools,
    required ToolCallHandler? onToolCall,
    required bool keepLoaded,
    required List<String> additionalMediaPaths,
  }) async {
    var loadedForThisCall = false;
    try {
      if (isCancelled()) {
        await controller.close();
        return;
      }
      _ensureListening();

      if (!isConversationTurn &&
          _loadedEngineKey != null &&
          _loadedEngineKey != engineKey) {
        controller.addError(
          const LiteRtException(
            'background_model_conflict',
            'A different local model is already loaded for the active '
                'conversation; skipping this background request instead of '
                'evicting it.',
          ),
        );
        await controller.close();
        return;
      }

      await _ensureModelLoaded(engineKey);
      loadedForThisCall = true;

      final split = _splitSystem(messages);
      final history = split.history;
      if (history.isEmpty) {
        await controller.close();
        return;
      }
      final newTurn = history.last;
      final priorHistory = history.sublist(0, history.length - 1);
      final signature = _conversationSignature(
        temperature: temperature,
        topK: topK,
        topP: topP,
        maxOutputTokens: maxOutputTokens,
        thinkingEnabled: thinkingEnabled,
        thinkingBudget: thinkingBudget,
        tools: tools,
      );

      final canReuse =
          _activeConversationKey == conversationId &&
          _activeConversationSignature == signature &&
          _lastFullHistory != null &&
          _sameHistory(priorHistory, _lastFullHistory!);

      if (!canReuse) {
        await _channel.startConversation(
          conversationToken: conversationId,
          systemInstruction: split.systemInstruction,
          initialMessages: [
            for (final message in priorHistory)
              _nativeMessage(
                message,
                visionEnabled: engineKey.visionEnabled,
                audioEnabled: engineKey.audioEnabled,
              ),
          ],
          temperature: temperature,
          topK: topK,
          topP: topP,
          maxOutputTokens: maxOutputTokens,
          thinkingEnabled: thinkingEnabled,
          thinkingBudget: thinkingBudget,
          tools: tools,
        );
        _activeConversationKey = conversationId;
        _activeConversationSignature = signature;
      }

      final requestId = const Uuid().v4();
      final events = StreamController<LiteRtEvent>();
      _byRequestId[requestId] = events;
      final cancelSub = whenCancelled.asStream().listen((_) {
        if (!isCancelled()) return;
        unawaited(_channel.cancel(requestId));
      });

      final newContents = _contentsFor(
        newTurn,
        visionEnabled: engineKey.visionEnabled,
        audioEnabled: engineKey.audioEnabled,
        additionalMediaPaths: additionalMediaPaths,
      );
      try {
        await _channel.sendMessage(
          requestId: requestId,
          conversationToken: conversationId,
          contents: newContents,
        );
      } catch (_) {
        await cancelSub.cancel();
        _byRequestId.remove(requestId);
        await events.close();
        rethrow;
      }

      final ids = StreamChunkIds('litert-$requestId');
      final replyBuffer = StringBuffer();
      var startedText = false;
      var settled = false;
      var toolCallCount = 0;

      try {
        await for (final event in events.stream) {
          switch (event) {
            // Reasoning events are deliberately discarded: they are internal
            // model thoughts, not assistant content to persist in the chat.
            case LiteRtReasoningDelta():
              continue;
            case LiteRtTextDelta(:final text):
              if (text.isEmpty) continue;
              if (!startedText) {
                startedText = true;
                controller.add(TextStart(ids.text()));
              }
              replyBuffer.write(text);
              controller.add(TextDelta(id: ids.text(), text: text));
            case LiteRtToolCalls(:final calls):
              if (calls.isEmpty) continue;
              if (onToolCall == null) {
                throw const LiteRtException(
                  'tool_handler_missing',
                  'The local model requested a tool but no handler is active.',
                );
              }
              if (toolCallCount + calls.length > _maxToolCallsPerTurn) {
                throw const LiteRtException(
                  'tool_call_limit',
                  'The local model exceeded the per-turn tool-call limit.',
                );
              }
              final responses = <Map<String, dynamic>>[];
              for (final call in calls) {
                final id = ids.next('tool-${++toolCallCount}');
                controller.add(ToolCallStart(id: id, toolName: call.name));
                if (call.arguments.isNotEmpty) {
                  controller.add(
                    ToolCallDelta(
                      id: id,
                      inputDelta: jsonEncode(call.arguments),
                    ),
                  );
                }
                controller.add(ToolCallEnd(id));
                Object? raw;
                try {
                  raw = await onToolCall(
                    call.name,
                    call.arguments,
                    toolCallId: id,
                  );
                } catch (_) {
                  if (isCancelled()) {
                    settled = true;
                    _activeConversationKey = null;
                    _activeConversationSignature = null;
                    _lastFullHistory = null;
                    controller.add(const Finish(finishReason: 'cancelled'));
                    unawaited(events.close());
                    break;
                  }
                  rethrow;
                }
                if (isCancelled()) {
                  settled = true;
                  _activeConversationKey = null;
                  _activeConversationSignature = null;
                  _lastFullHistory = null;
                  controller.add(const Finish(finishReason: 'cancelled'));
                  unawaited(events.close());
                  break;
                }
                final result = _normalizeToolResult(raw);
                controller.add(
                  ToolCallResult(
                    id: id,
                    output: result.content,
                    metadata: result.metadata,
                  ),
                );
                responses.add({'name': call.name, 'response': result.content});
              }
              if (!settled && responses.isNotEmpty) {
                await _channel.sendToolResponses(
                  requestId: requestId,
                  conversationToken: conversationId,
                  responses: responses,
                );
              }
            case LiteRtDone():
              settled = true;
              if (startedText) controller.add(TextEnd(ids.text()));
              controller.add(const Finish());
              _lastFullHistory = [
                ...priorHistory,
                newTurn,
                {'role': 'assistant', 'content': replyBuffer.toString()},
              ];
              unawaited(events.close());
            case LiteRtError(:final cancelled, :final message):
              settled = true;
              _activeConversationKey = null;
              _activeConversationSignature = null;
              _lastFullHistory = null;
              if (startedText) controller.add(TextEnd(ids.text()));
              if (cancelled) {
                controller.add(const Finish(finishReason: 'cancelled'));
              } else {
                controller.addError(
                  LiteRtException('generation_failed', message),
                );
              }
              unawaited(events.close());
            case LiteRtEngineStateChanged():
            case LiteRtUnknownEvent():
              continue;
          }
        }
      } catch (_) {
        _activeConversationKey = null;
        _activeConversationSignature = null;
        _lastFullHistory = null;
        unawaited(_channel.cancel(requestId));
        rethrow;
      } finally {
        await cancelSub.cancel();
        _byRequestId.remove(requestId);
        if (!events.isClosed) await events.close();
      }
      if (!settled) {
        _activeConversationKey = null;
        _activeConversationSignature = null;
        _lastFullHistory = null;
        controller.addError(
          const LiteRtException('generation_interrupted', null),
        );
      }
      await controller.close();
    } finally {
      if (!keepLoaded && loadedForThisCall) {
        await _unloadNow();
      }
    }
  }

  ClientToolResult _normalizeToolResult(Object? raw) {
    if (raw == null || raw is num || raw is bool || raw is Map || raw is List) {
      try {
        return ClientToolResult(jsonEncode(raw));
      } catch (_) {}
    }
    return ClientToolResult.fromHandler(raw);
  }

  Map<String, dynamic> _nativeMessage(
    Map<String, dynamic> message, {
    required bool visionEnabled,
    required bool audioEnabled,
  }) {
    final role = (message['role'] ?? 'user').toString();
    return {
      'role': role,
      'contents': _contentsFor(
        message,
        visionEnabled: visionEnabled,
        audioEnabled: audioEnabled,
      ),
      if (message['tool_calls'] is List)
        'toolCalls': _toolCallsForHistory(message['tool_calls'] as List),
    };
  }

  List<Map<String, dynamic>> _toolCallsForHistory(List rawCalls) {
    final out = <Map<String, dynamic>>[];
    for (final raw in rawCalls.whereType<Map>()) {
      final function = raw['function'];
      if (function is! Map) continue;
      final name = (function['name'] ?? '').toString();
      if (name.isEmpty) continue;
      out.add({
        'name': name,
        'arguments': _argumentsMap(function['arguments']),
      });
    }
    return out;
  }

  Map<String, dynamic> _argumentsMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _contentsFor(
    Map<String, dynamic> message, {
    required bool visionEnabled,
    required bool audioEnabled,
    List<String> additionalMediaPaths = const [],
  }) {
    final role = (message['role'] ?? 'user').toString();
    if (role == 'tool') {
      return [
        {
          'type': 'tool_response',
          'name': (message['name'] ?? 'tool').toString(),
          'response': message['content'] ?? '',
        },
      ];
    }

    final out = <Map<String, dynamic>>[];
    void addContent(Object? raw) {
      if (raw is String) {
        if (raw.isNotEmpty) out.add({'type': 'text', 'text': raw});
        return;
      }
      if (raw is List) {
        for (final item in raw) {
          addContent(item);
        }
        return;
      }
      if (raw is! Map) return;
      final type = (raw['type'] ?? '').toString();
      if (type == 'text' || type == 'input_text' || type == 'output_text') {
        final text = (raw['text'] ?? '').toString();
        if (text.isNotEmpty) out.add({'type': 'text', 'text': text});
        return;
      }
      if (type == 'image' || type == 'image_url' || type == 'input_image') {
        final path = _pathFromContent(raw, image: true);
        if (visionEnabled && path != null) {
          out.add({'type': 'image', 'path': path});
        }
        return;
      }
      if (type == 'audio' || type == 'input_audio') {
        final path = _pathFromContent(raw, image: false);
        if (audioEnabled && path != null) {
          out.add({'type': 'audio', 'path': path});
        }
      }
    }

    addContent(message['content']);
    final rawPaths = message[multimodalInternalMediaPathsKey];
    final paths = <String>[
      if (rawPaths is List)
        for (final path in rawPaths)
          if (path is String) path,
      ...additionalMediaPaths,
    ];
    final existing = {
      for (final content in out)
        if (content['path'] is String) content['path'] as String,
    };
    for (final path in paths) {
      if (path.isEmpty || !existing.add(path)) continue;
      if (_isAudioPath(path)) {
        if (audioEnabled) out.add({'type': 'audio', 'path': path});
      } else if (visionEnabled) {
        out.add({'type': 'image', 'path': path});
      }
    }
    return out;
  }

  String? _pathFromContent(Map raw, {required bool image}) {
    Object? value = raw['path'];
    if (value == null && image) {
      value = raw['image_url'];
      if (value is Map) value = value['url'];
    }
    if (value == null && !image) value = raw['audio_url'];
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.startsWith('data:') || text.startsWith('http')) {
      return null;
    }
    if (text.startsWith('file:')) {
      try {
        return Uri.parse(text).toFilePath();
      } catch (_) {
        return null;
      }
    }
    return text;
  }

  String _textFromContent(Object? content) {
    if (content is String) return content;
    if (content is Map) return _textFromContent([content]);
    if (content is! List) return content?.toString() ?? '';
    final parts = <String>[];
    for (final item in content.whereType<Map>()) {
      final type = (item['type'] ?? '').toString();
      if (type == 'text' || type == 'input_text' || type == 'output_text') {
        final text = (item['text'] ?? '').toString();
        if (text.isNotEmpty) parts.add(text);
      }
    }
    return parts.join('\n');
  }

  bool _isAudioPath(String path) {
    final withoutQuery = path.split('?').first.toLowerCase();
    return const [
      '.aac',
      '.amr',
      '.flac',
      '.m4a',
      '.mp3',
      '.ogg',
      '.opus',
      '.wav',
    ].any(withoutQuery.endsWith);
  }
}
