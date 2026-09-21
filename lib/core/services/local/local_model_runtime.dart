import 'dart:async';

import 'package:uuid/uuid.dart';

import '../api/stream/stream_chunk.dart';
import '../api/stream/stream_chunk_ids.dart';
import 'litert_channel.dart';

/// Owns the single in-memory LiteRT-LM engine for the whole app (Dart-side
/// counterpart of `LiteRtEngineManager` on the Kotlin side). Every
/// load/unload/generate call -- whether the user's own chat turn or a
/// background call (title/summary/suggestions/memory-organize) -- is
/// funneled through [_enqueue], a strict FIFO queue: only one local-model
/// operation ever runs at a time, matching "one model, one generation in
/// memory" from the task brief. There is no priority lane -- a background
/// call simply waits its turn behind whatever is already running, and the
/// next call waits behind it.
class LocalModelRuntime {
  LocalModelRuntime({LiteRtChannel? channel})
    : _channel = channel ?? LiteRtChannel();

  static final LocalModelRuntime instance = LocalModelRuntime();

  final LiteRtChannel _channel;
  final Map<String, StreamController<LiteRtEvent>> _byRequestId = {};
  StreamSubscription<LiteRtEvent>? _eventSub;
  Future<void> _queue = Future<void>.value();

  String? _loadedModelPath;
  String? _loadedBackend;
  String? _activeConversationKey;
  List<Map<String, dynamic>>? _lastFullHistory;

  /// The file path of the model currently loaded in the native engine, or
  /// `null` if none is. Read by the model-management UI to guard against
  /// deleting a model file that is in active use.
  String? get loadedModelPath => _loadedModelPath;

  void _ensureListening() {
    _eventSub ??= _channel.events.listen((event) {
      final rid = switch (event) {
        LiteRtTextDelta(:final requestId) => requestId,
        LiteRtDone(:final requestId) => requestId,
        LiteRtError(:final requestId) => requestId,
        _ => null,
      };
      if (rid != null) _byRequestId[rid]?.add(event);
    });
  }

  /// Runs [action] after every previously queued local-model operation has
  /// finished (successfully or not). A failure in one queued operation never
  /// wedges the queue for the next caller.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final started = _queue.then((_) => action());
    _queue = started.then((_) {}, onError: (_) {});
    return started;
  }

  /// Unloads the currently loaded model, if any. Safe to call when nothing
  /// is loaded. Queued like every other operation.
  Future<void> unload() => _enqueue(() async {
    if (_loadedModelPath == null) return;
    await _channel.unloadModel();
    _loadedModelPath = null;
    _loadedBackend = null;
    _activeConversationKey = null;
    _lastFullHistory = null;
  });

  /// Streams one local generation turn. [messages] is the full message
  /// history Moru already assembled for this turn (system/user/assistant),
  /// exactly like every cloud provider receives -- the last entry is the
  /// new user turn to answer.
  Stream<StreamChunk> generate({
    required String conversationId,
    required String modelPath,
    required String backend,
    required List<Map<String, dynamic>> messages,
    required Future<void> whenCancelled,
    required bool Function() isCancelled,
  }) {
    final controller = StreamController<StreamChunk>();
    unawaited(
      _enqueue(
        () => _runGenerate(
          controller: controller,
          conversationId: conversationId,
          modelPath: modelPath,
          backend: backend,
          messages: messages,
          whenCancelled: whenCancelled,
          isCancelled: isCancelled,
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

  Future<void> _ensureModelLoaded(String modelPath, String backend) async {
    if (_loadedModelPath == modelPath && _loadedBackend != null) return;
    if (_loadedModelPath != null && _loadedModelPath != modelPath) {
      await _channel.unloadModel();
      _loadedModelPath = null;
      _loadedBackend = null;
      _activeConversationKey = null;
      _lastFullHistory = null;
    }
    final actualBackend = await _channel.loadModel(
      modelPath: modelPath,
      backend: backend,
    );
    _loadedModelPath = modelPath;
    _loadedBackend = actualBackend;
  }

  ({String? systemInstruction, List<Map<String, dynamic>> history})
  _splitSystem(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    final history = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = (message['role'] ?? 'user').toString();
      if (role == 'system') {
        final text = (message['content'] ?? '').toString();
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
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i]['role'] ?? '').toString() != (b[i]['role'] ?? '').toString()) {
        return false;
      }
      if ((a[i]['content'] ?? '').toString() !=
          (b[i]['content'] ?? '').toString()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _runGenerate({
    required StreamController<StreamChunk> controller,
    required String conversationId,
    required String modelPath,
    required String backend,
    required List<Map<String, dynamic>> messages,
    required Future<void> whenCancelled,
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) {
      await controller.close();
      return;
    }
    _ensureListening();
    await _ensureModelLoaded(modelPath, backend);

    final split = _splitSystem(messages);
    final history = split.history;
    if (history.isEmpty) {
      await controller.close();
      return;
    }
    final newTurn = history.last;
    final priorHistory = history.sublist(0, history.length - 1);

    final canReuse =
        _activeConversationKey == conversationId &&
        _lastFullHistory != null &&
        _sameHistory(priorHistory, _lastFullHistory!);

    if (!canReuse) {
      await _channel.startConversation(
        conversationToken: conversationId,
        systemInstruction: split.systemInstruction,
        initialMessages: [
          for (final m in priorHistory)
            (
              (m['role'] ?? 'user').toString(),
              (m['content'] ?? '').toString(),
            ),
        ],
      );
      _activeConversationKey = conversationId;
    }

    final requestId = const Uuid().v4();
    final events = StreamController<LiteRtEvent>();
    _byRequestId[requestId] = events;

    final cancelSub = whenCancelled.asStream().listen((_) {
      if (!isCancelled()) return;
      unawaited(_channel.cancel(requestId));
    });

    try {
      await _channel.sendMessage(
        requestId: requestId,
        conversationToken: conversationId,
        text: (newTurn['content'] ?? '').toString(),
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

    await for (final event in events.stream) {
      switch (event) {
        case LiteRtTextDelta(:final text):
          if (text.isEmpty) continue;
          if (!startedText) {
            startedText = true;
            controller.add(TextStart(ids.text()));
          }
          replyBuffer.write(text);
          controller.add(TextDelta(id: ids.text(), text: text));
        case LiteRtDone():
          settled = true;
          if (startedText) controller.add(TextEnd(ids.text()));
          controller.add(const Finish());
          // The native conversation's own KV-cache now reflects [newTurn]
          // plus its own reply -- record that so the next call's history
          // can be recognized as a pure continuation and reuse it.
          _lastFullHistory = [
            ...priorHistory,
            newTurn,
            {'role': 'assistant', 'content': replyBuffer.toString()},
          ];
          // Not awaited: close()'s returned future only completes once the
          // stream has notified its listener of "done" -- but this *is*
          // that listener, still running this very callback, so awaiting
          // it here would deadlock against itself. The bare call still
          // marks the controller closed, which ends this `await for` on
          // its next iteration once this event finishes processing.
          unawaited(events.close());
        case LiteRtError(:final cancelled, :final message):
          settled = true;
          // The SDK does not roll back partial state on cancel (see
          // docs/litert-lm-progress.md) -- never reuse this conversation
          // again; the next turn always recreates it fresh.
          _activeConversationKey = null;
          _lastFullHistory = null;
          if (startedText) controller.add(TextEnd(ids.text()));
          if (!cancelled) {
            controller.addError(LiteRtException('generation_failed', message));
          } else {
            controller.add(const Finish(finishReason: 'cancelled'));
          }
          // See the LiteRtDone case above: must not be awaited here.
          unawaited(events.close());
        case LiteRtEngineStateChanged():
        case LiteRtUnknownEvent():
          continue;
      }
    }

    await cancelSub.cancel();
    _byRequestId.remove(requestId);
    if (!settled) {
      // The event stream closed without a done/error -- e.g. the engine
      // was torn down from under us. Never leave the caller hanging.
      _activeConversationKey = null;
      _lastFullHistory = null;
      controller.addError(
        const LiteRtException('generation_interrupted', null),
      );
    }
    await controller.close();
  }
}
