import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local/litert_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel methodChannel;
  late EventChannel eventChannel;
  late LiteRtChannel channel;
  late TestDefaultBinaryMessenger messenger;
  MockStreamHandlerEventSink? eventSink;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    methodChannel = const MethodChannel(kLiteRtMethodChannel);
    eventChannel = const EventChannel(kLiteRtEventChannel);
    channel = LiteRtChannel(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    eventSink = null;
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (args, sink) => eventSink = sink,
        onCancel: (args) => eventSink = null,
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test(
    'loadModel sends the exact args and returns the actual backend',
    () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'loadModel');
        final args = Map<String, Object?>.from(call.arguments as Map);
        expect(args['modelPath'], '/data/models/a.litertlm');
        expect(args['backend'], 'gpu');
        return <String, Object?>{'backend': 'cpu'}; // honest fallback report
      });

      final backend = await channel.loadModel(
        modelPath: '/data/models/a.litertlm',
        backend: 'gpu',
      );
      expect(backend, 'cpu');
    },
  );

  test('a PlatformException is normalized to LiteRtException', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      throw PlatformException(code: 'busy', message: 'generation in flight');
    });

    await expectLater(
      channel.sendMessage(requestId: 'r1', conversationToken: 'c1', text: 'hi'),
      throwsA(
        isA<LiteRtException>()
            .having((e) => e.code, 'code', 'busy')
            .having((e) => e.message, 'message', 'generation in flight'),
      ),
    );
  });

  test(
    'events decode to the right typed variant, keyed by requestId',
    () async {
      final received = <LiteRtEvent>[];
      final sub = channel.events.listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero); // let onListen attach

      eventSink?.success(<String, Object?>{
        'type': 'textDelta',
        'requestId': 'r1',
        'text': 'Hel',
      });
      eventSink?.success(<String, Object?>{'type': 'done', 'requestId': 'r1'});
      eventSink?.success(<String, Object?>{
        'type': 'error',
        'requestId': 'r2',
        'message': 'native failure',
        'cancelled': false,
      });
      eventSink?.success(<String, Object?>{
        'type': 'engineState',
        'state': 'generating',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(4));
      expect(
        received[0],
        isA<LiteRtTextDelta>()
            .having((e) => e.requestId, 'requestId', 'r1')
            .having((e) => e.text, 'text', 'Hel'),
      );
      expect(
        received[1],
        isA<LiteRtDone>().having((e) => e.requestId, 'requestId', 'r1'),
      );
      expect(
        received[2],
        isA<LiteRtError>()
            .having((e) => e.requestId, 'requestId', 'r2')
            .having((e) => e.cancelled, 'cancelled', isFalse),
      );
      expect(
        received[3],
        isA<LiteRtEngineStateChanged>().having(
          (e) => e.state,
          'state',
          'generating',
        ),
      );
    },
  );

  test('cancel returns whether the request id was actually active', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      return args['requestId'] == 'active';
    });
    expect(await channel.cancel('active'), isTrue);
    expect(await channel.cancel('stale'), isFalse);
  });
}
