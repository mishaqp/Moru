import 'dart:async';
import 'dart:convert';

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
      case 'sendToolResponses':
        return null;
      case 'cancel':
        return true;
      default:
        return null;
    }
  }

  void emit(Map<String, Object?> event) => sink?.success(event);

  Map<String, Object?> argsOf(String method) => Map<String, Object?>.from(
    calls.lastWhere((c) => c.method == method).arguments as Map,
  );

  Future<Map<String, Object?>> waitForArgs(
    String method, {
    int after = 0,
  }) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final matching = calls.where((call) => call.method == method).toList();
      if (matching.length > after) {
        return Map<String, Object?>.from(matching[after].arguments as Map);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for native $method call #${after + 1}');
  }
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
    String modelPath = '/models/a.litertlm',
  }) {
    final cancel = cancelCompleter ?? Completer<void>();
    return runtime.generate(
      conversationId: conversationId,
      modelPath: modelPath,
      backend: 'cpu',
      messages: messages,
      whenCancelled: cancel.future,
      isCancelled: () => cancel.isCompleted,
    );
  }

  /// A one-shot background/utility call (title-gen, summary-gen, ...) --
  /// tagged with a real conversation's id purely for logging, exactly like
  /// the real callers in home_view_model.dart do.
  Stream<StreamChunk> generateBackground({
    required String conversationId,
    required List<Map<String, dynamic>> messages,
    String modelPath = '/models/a.litertlm',
  }) {
    final cancel = Completer<void>();
    return runtime.generate(
      conversationId: conversationId,
      modelPath: modelPath,
      backend: 'cpu',
      messages: messages,
      whenCancelled: cancel.future,
      isCancelled: () => cancel.isCompleted,
      isConversationTurn: false,
    );
  }

  Stream<StreamChunk> generateWithFeatures({
    required List<Map<String, dynamic>> messages,
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
    Future<Object?> Function(
      String name,
      Map<String, dynamic> args, {
      String? toolCallId,
    })?
    onToolCall,
    bool keepLoaded = true,
  }) {
    final cancel = Completer<void>();
    return Function.apply(runtime.generate, const [], <Symbol, dynamic>{
          #conversationId: 'feature-conversation',
          #modelPath: '/models/features.litertlm',
          #backend: 'gpu',
          #messages: messages,
          #whenCancelled: cancel.future,
          #isCancelled: () => cancel.isCompleted,
          #maxNumTokens: maxNumTokens,
          #temperature: temperature,
          #topK: topK,
          #topP: topP,
          #maxOutputTokens: maxOutputTokens,
          #visionEnabled: visionEnabled,
          #audioEnabled: audioEnabled,
          #thinkingEnabled: thinkingEnabled,
          #thinkingBudget: thinkingBudget,
          #tools: tools,
          #onToolCall: onToolCall,
          #keepLoaded: keepLoaded,
        })
        as Stream<StreamChunk>;
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

  test(
    'a cancellation mid-stream calls native cancel and ends cleanly',
    () async {
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
      expect(
        chunks.last,
        isA<Finish>().having((c) => c.finishReason, 'reason', 'cancelled'),
      );
    },
  );

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

  test('consecutive turns in the same conversation reuse the native '
      'Conversation -- only one startConversation call', () async {
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
    expect(fake.argsOf('sendMessage')['contents'], [
      {'type': 'text', 'text': 'turn two'},
    ]);
    fake.emit({'type': 'done', 'requestId': rid2});
    await secondDone.future;

    // Still one -- turn two was a pure continuation, reused the
    // existing native Conversation instead of recreating it.
    expect(fake.startConversationCount, 1);
  });

  test('switching to a different conversation recreates the native '
      'Conversation', () async {
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
  });

  test('regenerating the same turn recreates the conversation instead of '
      'appending a duplicate user message', () async {
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
    expect(fake.argsOf('sendMessage')['contents'], [
      {'type': 'text', 'text': 'hi'},
    ]);
    fake.emit({'type': 'done', 'requestId': rid2});
    await regenDone.future;

    expect(fake.startConversationCount, 2);
  });

  test('a second generate() call is queued behind the first, never runs '
      'concurrently', () async {
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
  });

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

  test('a file the SDK rejects at load time (header-valid but corrupt or '
      'otherwise unloadable) surfaces as a clean stream error, not a hang '
      'or a silently-treated-as-ready engine', () async {
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
  });

  test('a background call tagged with the active conversation\'s own id is '
      'never mistaken for a continuation of it, and never corrupts what the '
      'real conversation recreates with afterwards', () async {
    // Real turn 1 of conversation c1.
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

    // A background call (title-gen) tagged with the SAME id, c1 -- but
    // it is not a continuation, so it must not be able to answer "yes"
    // to "is this a continuation of c1" no matter what native
    // conversationToken it lands under.
    final bg = generateBackground(
      conversationId: 'c1',
      messages: const [
        {'role': 'user', 'content': 'give this chat a short title'},
      ],
    );
    final bgDone = Completer<void>();
    bg.listen((_) {}, onDone: bgDone.complete);
    final rid2 = await requestIdOfLastSendMessage();
    // A background call is never treated as a continuation of anything
    // (it is always the first and only turn of its own throwaway
    // context), so it always starts a fresh native conversation -- its
    // own `initialMessages` must be empty, never c1's real history.
    expect(fake.startConversationCount, 2);
    expect(fake.argsOf('startConversation')['initialMessages'], isEmpty);
    fake.emit({'type': 'done', 'requestId': rid2});
    await bgDone.future;

    // Turn two of c1: LocalModelRuntime holds only one native
    // Conversation at a time (by design -- "one model, one generation
    // in memory"), so *any* intervening call, background or not, evicts
    // it and turn two must recreate -- that eviction is an accepted,
    // unavoidable cost of the single-slot design, not what this test is
    // about. What actually matters: the recreated conversation is seeded
    // from c1's own real prior history, not from the background call's
    // throwaway prompt or some corrupted mix of the two.
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
    final rid3 = await requestIdOfLastSendMessage();
    expect(fake.startConversationCount, 3);
    expect(fake.argsOf('startConversation')['initialMessages'], [
      {
        'role': 'user',
        'contents': [
          {'type': 'text', 'text': 'turn one'},
        ],
      },
      {
        'role': 'assistant',
        'contents': [
          {'type': 'text', 'text': 'reply one'},
        ],
      },
    ]);
    expect(fake.argsOf('sendMessage')['contents'], [
      {'type': 'text', 'text': 'turn two'},
    ]);
    fake.emit({'type': 'done', 'requestId': rid3});
    await secondDone.future;
  });

  test(
    'a background call is rejected, not allowed to evict, when a '
    'different model is already loaded for the active conversation',
    () async {
      final chat = generateOnce(
        conversationId: 'c1',
        modelPath: '/models/chat-model.litertlm',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      final chatDone = Completer<void>();
      chat.listen((_) {}, onDone: chatDone.complete);
      final rid = await requestIdOfLastSendMessage();
      fake.emit({'type': 'done', 'requestId': rid});
      await chatDone.future;
      expect(fake.loadModelCount, 1);
      expect(runtime.loadedModelPath, '/models/chat-model.litertlm');

      // A background call configured to use a DIFFERENT local model (the
      // user's title-generation model setting, say) must not unload the
      // conversation's own model to run itself.
      final bg = generateBackground(
        conversationId: 'c1',
        modelPath: '/models/title-model.litertlm',
        messages: const [
          {'role': 'user', 'content': 'give this chat a short title'},
        ],
      );
      final bgErrors = <Object>[];
      final bgDone = Completer<void>();
      bg.listen((_) {}, onError: bgErrors.add, onDone: bgDone.complete);
      await bgDone.future;

      expect(bgErrors, hasLength(1));
      expect(
        (bgErrors.single as LiteRtException).code,
        'background_model_conflict',
      );
      // No unload/reload was attempted at all.
      expect(fake.loadModelCount, 1);
      expect(runtime.loadedModelPath, '/models/chat-model.litertlm');
    },
  );

  test('a background call proceeds normally when it targets the same model '
      'already loaded, or when nothing is loaded yet', () async {
    // Nothing loaded yet -- a background call is free to load the
    // first model, same as any other first call would.
    final bg1 = generateBackground(
      conversationId: 'c1',
      messages: const [
        {'role': 'user', 'content': 'summarize this'},
      ],
    );
    final bg1Chunks = <StreamChunk>[];
    final bg1Done = Completer<void>();
    bg1.listen(bg1Chunks.add, onDone: bg1Done.complete);
    final rid1 = await requestIdOfLastSendMessage();
    fake.emit({'type': 'done', 'requestId': rid1});
    await bg1Done.future;
    expect(bg1Chunks, contains(isA<Finish>()));
    expect(fake.loadModelCount, 1);

    // Same model as what is already loaded -- no conflict, proceeds.
    final bg2 = generateBackground(
      conversationId: 'c1',
      messages: const [
        {'role': 'user', 'content': 'give this chat a short title'},
      ],
    );
    final bg2Chunks = <StreamChunk>[];
    final bg2Done = Completer<void>();
    bg2.listen(bg2Chunks.add, onDone: bg2Done.complete);
    final rid2 = await requestIdOfLastSendMessage();
    fake.emit({'type': 'done', 'requestId': rid2});
    await bg2Done.future;
    expect(bg2Chunks, contains(isA<Finish>()));
    // Still one -- the same model path never triggers an unload/reload.
    expect(fake.loadModelCount, 1);
  });

  test('engine and conversation settings reach the native bridge without '
      'mixing their lifetimes', () async {
    final chunks = generateWithFeatures(
      maxNumTokens: 8192,
      temperature: 0.25,
      topK: 32,
      topP: 0.8,
      maxOutputTokens: 512,
      visionEnabled: true,
      audioEnabled: true,
      thinkingEnabled: true,
      thinkingBudget: 256,
      messages: const [
        {'role': 'user', 'content': 'hello'},
      ],
    );
    final done = Completer<void>();
    chunks.listen((_) {}, onDone: done.complete);

    final send = await fake.waitForArgs('sendMessage');
    final requestId = send['requestId'] as String;
    fake.emit({'type': 'done', 'requestId': requestId});
    await done.future;

    expect(fake.argsOf('loadModel'), containsPair('maxNumTokens', 8192));
    expect(fake.argsOf('loadModel'), containsPair('visionEnabled', true));
    expect(fake.argsOf('loadModel'), containsPair('audioEnabled', true));
    expect(fake.argsOf('startConversation'), containsPair('temperature', 0.25));
    expect(fake.argsOf('startConversation'), containsPair('topK', 32));
    expect(fake.argsOf('startConversation'), containsPair('topP', 0.8));
    expect(
      fake.argsOf('startConversation'),
      containsPair('maxOutputTokens', 512),
    );
    expect(
      fake.argsOf('startConversation'),
      containsPair('thinkingEnabled', true),
    );
    expect(
      fake.argsOf('startConversation'),
      containsPair('thinkingBudget', 256),
    );
  });

  test(
    'multimodal contents are sent as structured image and audio paths',
    () async {
      final chunks = generateWithFeatures(
        visionEnabled: true,
        audioEnabled: true,
        messages: const [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Describe these files'},
              {'type': 'image', 'path': '/tmp/photo.png'},
              {'type': 'audio', 'path': '/tmp/voice.wav'},
            ],
          },
        ],
      );
      final done = Completer<void>();
      chunks.listen((_) {}, onDone: done.complete);

      final send = await fake.waitForArgs('sendMessage');
      expect(send['contents'], [
        {'type': 'text', 'text': 'Describe these files'},
        {'type': 'image', 'path': '/tmp/photo.png'},
        {'type': 'audio', 'path': '/tmp/voice.wav'},
      ]);
      fake.emit({'type': 'done', 'requestId': send['requestId']});
      await done.future;
    },
  );

  test(
    'reasoning channel becomes reasoning chunks before answer text',
    () async {
      final stream = generateWithFeatures(
        thinkingEnabled: true,
        messages: const [
          {'role': 'user', 'content': 'think first'},
        ],
      );
      final chunks = <StreamChunk>[];
      final done = Completer<void>();
      stream.listen(chunks.add, onDone: done.complete);

      final send = await fake.waitForArgs('sendMessage');
      final requestId = send['requestId'] as String;
      fake.emit({
        'type': 'reasoningDelta',
        'requestId': requestId,
        'text': 'plan',
      });
      fake.emit({
        'type': 'textDelta',
        'requestId': requestId,
        'text': 'answer',
      });
      fake.emit({'type': 'done', 'requestId': requestId});
      await done.future;

      expect(chunks, [
        isA<ReasoningStart>(),
        isA<ReasoningDelta>().having((chunk) => chunk.text, 'text', 'plan'),
        isA<ReasoningEnd>(),
        isA<TextStart>(),
        isA<TextDelta>().having((chunk) => chunk.text, 'text', 'answer'),
        isA<TextEnd>(),
        isA<Finish>(),
      ]);
    },
  );

  test('native tool calls execute through the existing handler and resume '
      'the same request with tool responses', () async {
    final invoked = <({String name, Map<String, dynamic> args, String? id})>[];
    final stream = generateWithFeatures(
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'search',
            'description': 'Search locally',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          },
        },
      ],
      onToolCall: (name, args, {toolCallId}) async {
        invoked.add((name: name, args: args, id: toolCallId));
        return const {'result': 'found'};
      },
      messages: const [
        {'role': 'user', 'content': 'find it'},
      ],
    );
    final chunks = <StreamChunk>[];
    final done = Completer<void>();
    stream.listen(chunks.add, onDone: done.complete);

    final send = await fake.waitForArgs('sendMessage');
    final requestId = send['requestId'] as String;
    fake.emit({
      'type': 'toolCalls',
      'requestId': requestId,
      'calls': [
        {
          'name': 'search',
          'arguments': {'query': 'LiteRT'},
        },
      ],
    });

    final response = await fake.waitForArgs('sendToolResponses');
    expect(invoked, hasLength(1));
    expect(invoked.single.name, 'search');
    expect(invoked.single.args, {'query': 'LiteRT'});
    expect(invoked.single.id, isNotEmpty);
    expect(response['requestId'], requestId);
    expect(response['responses'], [
      {
        'name': 'search',
        'response': jsonEncode({'result': 'found'}),
      },
    ]);

    fake.emit({'type': 'textDelta', 'requestId': requestId, 'text': 'done'});
    fake.emit({'type': 'done', 'requestId': requestId});
    await done.future;

    expect(chunks.whereType<ToolCallStart>(), hasLength(1));
    expect(chunks.whereType<ToolCallDelta>(), hasLength(1));
    expect(chunks.whereType<ToolCallEnd>(), hasLength(1));
    expect(chunks.whereType<ToolCallResult>(), hasLength(1));
    expect(chunks.last, isA<Finish>());
  });

  test('keepLoaded false unloads after the request completes', () async {
    final stream = generateWithFeatures(
      keepLoaded: false,
      messages: const [
        {'role': 'user', 'content': 'one shot'},
      ],
    );
    final done = Completer<void>();
    stream.listen((_) {}, onDone: done.complete);

    final send = await fake.waitForArgs('sendMessage');
    fake.emit({'type': 'done', 'requestId': send['requestId']});
    await done.future;

    await fake.waitForArgs('unloadModel');
    expect(runtime.loadedModelPath, isNull);
  });
}
