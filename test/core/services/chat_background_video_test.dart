import 'package:Kelivo/core/services/chat/chat_background_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.chat_background_video');

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'video preparation passes physical bounds independent of orientation',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'prepare');
        expect(call.arguments, {
          'sourcePath': '/private/images/chat_backgrounds/source.mov',
          'maxWidth': 1080,
          'maxHeight': 2400,
        });
        return '/private/cache/chat_backgrounds/screen.mp4';
      });

      expect(
        await ChatBackgroundVideo.prepare(
          '/private/images/chat_backgrounds/source.mov',
          maxWidth: 2400,
          maxHeight: 1080,
        ),
        '/private/cache/chat_backgrounds/screen.mp4',
      );
    },
  );

  test('video preparation derives bounds from physical view size', () async {
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 3120);
    addTearDown(view.resetPhysicalSize);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect((call.arguments as Map)['maxWidth'], 1440);
      expect((call.arguments as Map)['maxHeight'], 3120);
      return '/private/cache/chat_backgrounds/screen.mp4';
    });

    await ChatBackgroundVideo.prepare('/private/source.mp4');
  });

  test(
    'empty native result cannot fall back to high resolution source',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => '',
      );
      await expectLater(
        ChatBackgroundVideo.prepare(
          '/private/source.mp4',
          maxWidth: 1080,
          maxHeight: 2400,
        ),
        throwsStateError,
      );
    },
  );

  test('invalid bounds are refused before native preparation', () async {
    await expectLater(
      ChatBackgroundVideo.prepare(
        '/private/source.mp4',
        maxWidth: 0,
        maxHeight: 2400,
      ),
      throwsArgumentError,
    );
  });
}
