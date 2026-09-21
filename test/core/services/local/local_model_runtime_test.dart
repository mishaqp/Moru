import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/local/litert_channel.dart';
import 'package:Kelivo/core/services/local/local_model_runtime.dart';

/// Drives the mocked `app.litert` method channel like a tiny fake native
/// side: records every call and lets the test script `textDelta`/`done`/
/// `error` events back through the mocked event channel on demand. Exists
/// so [LocalModelRuntime]'s own Dart-side logic (conversation reuse vs.
/// recreate, cancellation wiring, the single-flight queue) is verified
/// without a real device -- real native behavior is only provable on
/// hardware (see docs/litert-lm-progress.md).
class _FakeNative {
  _FakeNative(this.messenger, this.methodChannel, this.eventChannel) {
    messenger.setMockMethodCallHandler(methodChannel, _handle);
  }

  final TestDefaultBinaryMessenger messenger;
  final MethodChannel methodChannel;
  final EventChannel eventChannel;
  MockStreamHandlerEventSink? sink;

  final List<MethodCall> calls = [];
  int startConversationCount = 0;
  int loadModelCount = 0;

  /// Set to simulate the real SDK rejecting a header-valid but corrupt or
  /// otherwise unloadable `.litertlm` file at `Engine.initialize()` --
  /// LiteRtEngineManager.kt wraps that call in try/catch and reports it
  /// through the method channel's error result exactly like this.
  PlatformException? loadModelError;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'loadModel':
        loadModelCount++;
        if (loadModelError != null) throw loadModelError!;
        return <String, Object?>{'backend': 'cpu'};
      case 'unloadModel':
        return null;
      case 'startConversation':
        startConversationCount++;
        return null;
      case 'sendMessage':
        return null;
      case 'cancel':
        return true;
      default:
        return null;
    }
  }

  void emit(Map<String, Object?> event) => sink?.success(event);

  Map<String, Object?> argsOf(String method) =>
      Map<String, Object?>.from(
        calls.lastWhere((c) => c.method == method).arguments as Map,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late MethodChannel methodChannel;
  late EventChannel eventChannel;
  late _FakeNative fake;
  late LocalModelRuntime runtime;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    methodChannel = const MethodChannel(kLiteRtMethodChannel);
    eventChannel = const EventChannel(kLiteRtEventChannel);
    fake = _FakeNative(messenger, methodChannel, eventChannel);
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (args, sink) => fake.sink = sink),
    );
    runtime = LocalModelRuntime(
      channel: LiteRtChannel(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  Stream<StreamChunk> generateOnce({
    required String conversationId,
    required List<Map<String, dynamic>> messages,
    Completer<void>? cancelCompleter,
  }) {
    final cancel = cancelCompleter ?? Completer<void>();
    return runtime.generate(
      conversationId: conversationId,
      modelPath: '/models/a.litertlm',
      backend: 'cpu',
      messages: messages,
      whenCancelled: cancel.future,
      isCancelled: () => cancel.isCompleted,
    );
  }

  /// Lets the fake native side answer the just-issued `sendMessage` call
  /// with a scripted `textDelta*` + `done` (or `error`) sequence, after
  /// yielding a turn so the runtime has registered its request id.
  Future<String> requestIdOfLastSendMessage() async {
    await Future<void>.delayed(Duration.zero);
    return fake.argsOf('sendMessage')['requestId'] as String;
  }

  test(
    'emits TextStart before TextDelta before TextEnd/Finish, in order',
    () async {
      final stream = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      final chunks = <StreamChunk>[];
      final done = Completer<void>();
      stream.listen(chunks.add, onDone: done.complete);

      final rid = await requestIdOfLastSendMessage();
      fake.emit({'type': 'textDelta', 'requestId': rid, 'text': 'Hel'});
      fake.emit({'type': 'textDelta', 'requestId': rid, 'text': 'lo'});
      fake.emit({'type': 'done', 'requestId': rid});
      await done.future;

      expect(chunks, [
        isA<TextStart>(),
        isA<TextDelta>().having((c) => c.text, 'text', 'Hel'),
        isA<TextDelta>().having((c) => c.text, 'text', 'lo'),
        isA<TextEnd>(),
        isA<Finish>(),
      ]);
    },
  );

  test('a cancellation mid-stream calls native cancel and ends cleanly', () async {
    final cancelCompleter = Completer<void>();
    final stream = generateOnce(
      conversationId: 'c1',
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
      cancelCompleter: cancelCompleter,
    );
    final chunks = <StreamChunk>[];
    final errors = <Object>[];
    final done = Completer<void>();
    stream.listen(chunks.add, onError: errors.add, onDone: done.complete);

    final rid = await requestIdOfLastSendMessage();
    fake.emit({'type': 'textDelta', 'requestId': rid, 'text': 'Hel'});
    await Future<void>.delayed(Duration.zero);

    cancelCompleter.complete();
    await Future<void>.delayed(Duration.zero);
    expect(fake.argsOf('cancel')['requestId'], rid);

    fake.emit({
      'type': 'error',
      'requestId': rid,
      'message': 'cancelled',
      'cancelled': true,
    });
    await done.future;

    // Cancellation is a clean stop, not a stream error.
    expect(errors, isEmpty);
    expect(chunks.last, isA<Finish>().having((c) => c.finishReason, 'reason', 'cancelled'));
  });

  test('a genuine native error is delivered as a stream error', () async {
    final stream = generateOnce(
      conversationId: 'c1',
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );
    final errors = <Object>[];
    final done = Completer<void>();
    stream.listen((_) {}, onError: errors.add, onDone: done.complete);

    final rid = await requestIdOfLastSendMessage();
    fake.emit({
      'type': 'error',
      'requestId': rid,
      'message': 'native crash',
      'cancelled': false,
    });
    await done.future;

    expect(errors, hasLength(1));
    expect(errors.single, isA<LiteRtException>());
  });

  test(
    'consecutive turns in the same conversation reuse the native '
    'Conversation -- only one startConversation call',
    () async {
      final first = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'turn one'},
        ],
      );
      final firstDone = Completer<void>();
      first.listen((_) {}, onDone: firstDone.complete);
      final rid1 = await requestIdOfLastSendMessage();
      fake.emit({'type': 'textDelta', 'requestId': rid1, 'text': 'reply one'});
      fake.emit({'type': 'done', 'requestId': rid1});
      await firstDone.future;

      expect(fake.startConversationCount, 1);

      // Turn two: the full history Moru would actually resend, including
      // the model's own reply to turn one.
      final second = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'turn one'},
          {'role': 'assistant', 'content': 'reply one'},
          {'role': 'user', 'content': 'turn two'},
        ],
      );
      final secondDone = Completer<void>();
      second.listen((_) {}, onDone: secondDone.complete);
      final rid2 = await requestIdOfLastSendMessage();
      expect(fake.argsOf('sendMessage')['text'], 'turn two');
      fake.emit({'type': 'done', 'requestId': rid2});
      await secondDone.future;

      // Still one -- turn two was a pure continuation, reused the
      // existing native Conversation instead of recreating it.
      expect(fake.startConversationCount, 1);
    },
  );

  test(
    'switching to a different conversation recreates the native '
    'Conversation',
    () async {
      final first = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      final firstDone = Completer<void>();
      first.listen((_) {}, onDone: firstDone.complete);
      final rid1 = await requestIdOfLastSendMessage();
      fake.emit({'type': 'done', 'requestId': rid1});
      await firstDone.future;
      expect(fake.startConversationCount, 1);

      final second = generateOnce(
        conversationId: 'c2',
        messages: const [
          {'role': 'user', 'content': 'different chat'},
        ],
      );
      final secondDone = Completer<void>();
      second.listen((_) {}, onDone: secondDone.complete);
      final rid2 = await requestIdOfLastSendMessage();
      fake.emit({'type': 'done', 'requestId': rid2});
      await secondDone.future;

      expect(fake.startConversationCount, 2);
    },
  );

  test(
    'regenerating the same turn recreates the conversation instead of '
    'appending a duplicate user message',
    () async {
      final first = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      final firstDone = Completer<void>();
      first.listen((_) {}, onDone: firstDone.complete);
      final rid1 = await requestIdOfLastSendMessage();
      fake.emit({'type': 'textDelta', 'requestId': rid1, 'text': 'first reply'});
      fake.emit({'type': 'done', 'requestId': rid1});
      await firstDone.future;
      expect(fake.startConversationCount, 1);

      // Regenerate: the exact same history is resent (no assistant reply
      // appended yet) -- this must NOT be treated as "extends by one".
      final regen = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      final regenDone = Completer<void>();
      regen.listen((_) {}, onDone: regenDone.complete);
      final rid2 = await requestIdOfLastSendMessage();
      // A fresh conversation means initialMessages is empty and the turn
      // itself is sent as the message.
      expect(fake.argsOf('startConversation')['initialMessages'], isEmpty);
      expect(fake.argsOf('sendMessage')['text'], 'hi');
      fake.emit({'type': 'done', 'requestId': rid2});
      await regenDone.future;

      expect(fake.startConversationCount, 2);
    },
  );

  test(
    'a second generate() call is queued behind the first, never runs '
    'concurrently',
    () async {
      final order = <String>[];
      final first = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'first'},
        ],
      );
      final firstDone = Completer<void>();
      first.listen((c) {
        if (c is Finish) order.add('first-finish');
      }, onDone: firstDone.complete);

      final second = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'second (background task)'},
        ],
      );
      final secondDone = Completer<void>();
      second.listen((c) {
        if (c is Finish) order.add('second-finish');
      }, onDone: secondDone.complete);

      // Only the first call's sendMessage should have reached native yet.
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls.where((c) => c.method == 'sendMessage'), hasLength(1));

      final rid1 = fake.argsOf('sendMessage')['requestId'] as String;
      fake.emit({'type': 'done', 'requestId': rid1});
      await firstDone.future;

      final rid2 = await requestIdOfLastSendMessage();
      fake.emit({'type': 'done', 'requestId': rid2});
      await secondDone.future;

      expect(order, ['first-finish', 'second-finish']);
    },
  );

  test('the model is loaded once and not reloaded for the same path', () async {
    final first = generateOnce(
      conversationId: 'c1',
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );
    final firstDone = Completer<void>();
    first.listen((_) {}, onDone: firstDone.complete);
    final rid1 = await requestIdOfLastSendMessage();
    fake.emit({'type': 'done', 'requestId': rid1});
    await firstDone.future;
    expect(fake.loadModelCount, 1);

    final second = generateOnce(
      conversationId: 'c2',
      messages: const [
        {'role': 'user', 'content': 'again'},
      ],
    );
    final secondDone = Completer<void>();
    second.listen((_) {}, onDone: secondDone.complete);
    final rid2 = await requestIdOfLastSendMessage();
    fake.emit({'type': 'done', 'requestId': rid2});
    await secondDone.future;

    expect(fake.loadModelCount, 1);
  });

  test(
    'a file the SDK rejects at load time (header-valid but corrupt or '
    'otherwise unloadable) surfaces as a clean stream error, not a hang '
    'or a silently-treated-as-ready engine',
    () async {
      // The magic-byte check in local_model_import.dart only proves the
      // file *header* is well-formed -- it is not proof the file is a
      // loadable model (see docs/litert-lm-progress.md). This is what the
      // real SDK is expected to do next: Engine.initialize() throws,
      // LiteRtEngineManager.kt's try/catch turns that into a method-channel
      // error result, and it must reach the caller as a normal stream
      // error instead of hanging forever or leaving the runtime thinking a
      // model is loaded.
      fake.loadModelError = PlatformException(
        code: 'litert_native',
        message: 'failed to parse model: invalid or corrupt container',
      );

      final stream = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      final errors = <Object>[];
      final done = Completer<void>();
      stream.listen((_) {}, onError: errors.add, onDone: done.complete);

      await done.future;

      expect(errors, hasLength(1));
      expect(errors.single, isA<LiteRtException>());
      expect(fake.loadModelCount, 1);
      // The failed load must not be mistaken for a successfully loaded
      // model on the next attempt.
      expect(runtime.loadedModelPath, isNull);

      // Recovery: once the underlying file/model is fixed (simulated here
      // by clearing the injected failure), a later generate() call must
      // still work -- a failed load must not permanently wedge the queue
      // or the runtime's own state.
      fake.loadModelError = null;
      final retry = generateOnce(
        conversationId: 'c1',
        messages: const [
          {'role': 'user', 'content': 'hi again'},
        ],
      );
      final retryChunks = <StreamChunk>[];
      final retryDone = Completer<void>();
      retry.listen(retryChunks.add, onDone: retryDone.complete);
      final rid = await requestIdOfLastSendMessage();
      fake.emit({'type': 'done', 'requestId': rid});
      await retryDone.future;

      expect(retryChunks, contains(isA<Finish>()));
      expect(runtime.loadedModelPath, isNotNull);
    },
  );
}
