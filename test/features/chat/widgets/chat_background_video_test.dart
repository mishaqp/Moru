import 'dart:async';

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_background_video.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../support/business_test_harness.dart';

class _VideoController extends VideoPlayerController {
  _VideoController(
    super.file, {
    required VideoPlayerOptions options,
    this.ready,
  }) : super.file(videoPlayerOptions: options);

  final Future<void>? ready;
  bool disposed = false;
  int plays = 0;

  @override
  Future<void> initialize() async {
    await ready;
    if (disposed) return;
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 10),
      size: const Size(600, 400),
    );
  }

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> setLooping(bool looping) async =>
      value = value.copyWith(isLooping: looping);

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

void main() {
  final controllers = <_VideoController>[];
  Completer<void>? initialization;
  final preparations = <(String, int?, int?)>[];

  setUp(() {
    controllers.clear();
    preparations.clear();
    initialization = null;
    ChatBackgroundVideo.debugPrepareOverride =
        (path, {maxWidth, maxHeight}) async {
          preparations.add((path, maxWidth, maxHeight));
          return '$path.bounded.mp4';
        };
    debugChatBackgroundVideoControllerFactory = (file, options) {
      final controller = _VideoController(
        file,
        options: options,
        ready: initialization?.future,
      );
      controllers.add(controller);
      return controller;
    };
  });

  tearDown(() {
    ChatBackgroundVideo.debugPrepareOverride = null;
    debugChatBackgroundVideoControllerFactory = null;
  });

  Widget app({
    String path = '/tmp/background.mp4',
    bool active = true,
    bool ticker = true,
    bool reduced = false,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        devicePixelRatio: 2,
        disableAnimations: reduced,
      ),
      child: TickerMode(
        enabled: ticker,
        child: ChatBackground(
          configuration: ChatBackgroundSettings(
            type: ChatBackgroundType.video,
            path: path,
          ),
          active: active,
          includeSurfaceFill: true,
        ),
      ),
    ),
  );

  Future<void> initialize(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'bounded video is muted, loops, and observes all visibility gates',
    (tester) async {
      await tester.pumpWidget(app());
      await initialize(tester);
      final controller = controllers.single;
      expect(preparations.single, ('/tmp/background.mp4', 780, 1688));
      expect(controller.dataSource, endsWith('.bounded.mp4'));
      expect(controller.videoPlayerOptions!.allowBackgroundPlayback, isTrue);
      expect(
        controller.videoPlayerOptions!.preventsDisplaySleepDuringVideoPlayback,
        isFalse,
      );
      expect(controller.value.volume, 0);
      expect(controller.value.isLooping, isTrue);
      expect(controller.value.isPlaying, isTrue);

      await tester.pumpWidget(app(active: false));
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);

      await tester.pumpWidget(app());
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(controller.value.isPlaying, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(controller.value.isPlaying, isTrue);
      }
      for (final hidden in [app(ticker: false), app(reduced: true)]) {
        await tester.pumpWidget(hidden);
        await tester.pump();
        expect(controller.value.isPlaying, isFalse);
        await tester.pumpWidget(app());
        await tester.pump();
        expect(controller.value.isPlaying, isTrue);
      }
      expect(controllers, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.disposed, isTrue);
    },
  );

  testWidgets('source replacement disposes the previous video', (tester) async {
    await tester.pumpWidget(app());
    await initialize(tester);
    final previous = controllers.single;
    await tester.pumpWidget(app(path: '/tmp/other.mp4'));
    await initialize(tester);
    expect(previous.disposed, isTrue);
    expect(controllers, hasLength(2));
    expect(controllers.last.value.isPlaying, isTrue);
    expect(controllers.last.dataSource, contains('other.mp4.bounded.mp4'));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controllers.last.disposed, isTrue);
  });

  testWidgets(
    'Glass economy pauses the current frame without recreating video',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;
      await settings.setGlassTheme(true);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: settings, child: app()),
      );
      await initialize(tester);
      final controller = controllers.single;
      expect(controller.value.isPlaying, isTrue);
      await settings.setGlassEconomy(true);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);
      expect(controller.disposed, isFalse);
      await settings.setGlassEconomy(false);
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);
      expect(controllers, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('initialization finishing after removal never starts playback', (
    tester,
  ) async {
    initialization = Completer<void>();
    await tester.pumpWidget(app());
    await tester.pump();
    final controller = controllers.single;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.disposed, isTrue);
    initialization!.complete();
    await initialize(tester);
    expect(controller.plays, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preparation failure never plays the unrestricted source', (
    tester,
  ) async {
    ChatBackgroundVideo.debugPrepareOverride =
        (_, {maxWidth, maxHeight}) async =>
            throw const FormatException('video');
    await tester.pumpWidget(app());
    await initialize(tester);
    expect(controllers, isEmpty);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
