import 'dart:typed_data';

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_background_video.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/chat/widgets/chat_gradient_background.dart';
import 'package:Kelivo/features/home/widgets/sidebar_glass.dart';
import 'package:Kelivo/shared/widgets/interactive_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../support/business_test_harness.dart';

class _VideoController extends VideoPlayerController {
  _VideoController(super.file, {required VideoPlayerOptions options})
    : super.file(videoPlayerOptions: options);

  @override
  Future<void> initialize() async => value = value.copyWith(
    isInitialized: true,
    duration: const Duration(seconds: 10),
    size: const Size(600, 400),
  );

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);
  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);
  @override
  Future<void> setLooping(bool looping) async =>
      value = value.copyWith(isLooping: looping);
  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(() => image.toByteData());
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  Future<SettingsProvider> settings() async {
    final value = SettingsProvider(createBusinessTestPreferences());
    await value.loaded;
    addTearDown(value.dispose);
    return value;
  }

  testWidgets('sidebar modes and Glass use the selected global or own scene', (
    tester,
  ) async {
    final value = await settings();
    const global = ChatBackgroundSettings(
      type: ChatBackgroundType.gradient,
      gradientAnimated: false,
      saturation: .3,
      gradientOffsetX: .7,
      maskStrength: 2,
    );
    await value.setChatAppearance(const ChatAppearanceSettings(light: global));
    Widget app() => ChangeNotifierProvider.value(
      value: value,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const SidebarGlassBackdrop(),
      ),
    );
    await tester.pumpWidget(app());
    expect(
      tester.widget<ChatBackground>(find.byType(ChatBackground)).configuration,
      global.copyWith(maskStrength: 1, blur: 0),
    );
    const own = ChatBackgroundSettings(
      type: ChatBackgroundType.gradient,
      gradientAnimated: false,
      brightness: .2,
      gradientPhase: 13,
    );
    await value.setSidebarAppearance(
      value.sidebarAppearance.copyWith(
        backgroundMode: SidebarBackgroundMode.custom,
        customBackground: own,
      ),
    );
    await value.setGlassTheme(true);
    await tester.pump();
    expect(
      tester.widget<ChatBackground>(find.byType(ChatBackground)).configuration,
      own.copyWith(maskStrength: 1, blur: 0),
    );
    expect(find.byType(ImageFiltered), findsOneWidget);
    await value.setGlassEconomy(true);
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(ChatGradientBackground), findsOneWidget);
    await value.setSidebarAppearance(
      value.sidebarAppearance.copyWith(
        backgroundMode: SidebarBackgroundMode.theme,
      ),
    );
    await tester.pump();
    expect(find.byType(ChatGradientBackground), findsNothing);
    expect(value.chatAppearance.light, global);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('panel mask, blur and opacity change background pixels only', (
    tester,
  ) async {
    final value = await settings();
    final key = GlobalKey();
    var appearance = const SidebarAppearanceSettings(
      backgroundMode: SidebarBackgroundMode.custom,
      customBackground: ChatBackgroundSettings(
        type: ChatBackgroundType.gradient,
        gradientAnimated: false,
        maskStrength: 2,
      ),
      maskStrength: 0,
    );
    Widget app() => ChangeNotifierProvider.value(
      value: value,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Center(
          child: SizedBox(
            width: 120,
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  key: key,
                  child: SidebarGlassBackdrop(configuration: appearance),
                ),
                const Center(child: Text('Readable foreground')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    final original = await _pixels(tester, key);
    appearance = appearance.copyWith(maskStrength: 2);
    await tester.pumpWidget(app());
    final masked = await _pixels(tester, key);
    expect(masked, isNot(orderedEquals(original)));
    appearance = appearance.copyWith(maskStrength: 0, blur: 20);
    await tester.pumpWidget(app());
    expect(await _pixels(tester, key), isNot(orderedEquals(original)));
    appearance = appearance.copyWith(opacity: 0);
    await tester.pumpWidget(app());
    final transparent = await _pixels(tester, key);
    for (var pixel = 3; pixel < transparent.length; pixel += 4) {
      expect(transparent[pixel], 0);
    }
    expect(find.text('Readable foreground').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'bounded sidebar video pauses when the drawer or route is hidden',
    (tester) async {
      final value = await settings();
      await value.setChatAppearance(
        const ChatAppearanceSettings(
          light: ChatBackgroundSettings(
            type: ChatBackgroundType.video,
            path: '/tmp/sidebar.mp4',
          ),
        ),
      );
      final drawer = InteractiveDrawerController();
      addTearDown(drawer.dispose);
      final controllers = <_VideoController>[];
      ChatBackgroundVideo.debugPrepareOverride =
          (path, {maxWidth, maxHeight}) async => '$path.bounded.mp4';
      debugChatBackgroundVideoControllerFactory = (file, options) {
        final controller = _VideoController(file, options: options);
        controllers.add(controller);
        return controller;
      };
      addTearDown(() {
        ChatBackgroundVideo.debugPrepareOverride = null;
        debugChatBackgroundVideoControllerFactory = null;
      });
      Widget app({bool active = true}) => ChangeNotifierProvider.value(
        value: value,
        child: MaterialApp(
          home: TickerMode(
            enabled: active,
            child: InteractiveDrawer(
              controller: drawer,
              drawer: const SidebarGlassBackdrop(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
      }
      final controller = controllers.single;
      expect(controller.dataSource, endsWith('.bounded.mp4'));
      expect(controller.value.isPlaying, isFalse);
      drawer.jumpTo(1);
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.volume, 0);
      drawer.jumpTo(.5);
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);
      drawer.jumpTo(0);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);
      drawer.jumpTo(1);
      await tester.pumpWidget(app(active: false));
      expect(controller.value.isPlaying, isFalse);
      await tester.pumpWidget(app());
      expect(controller.value.isPlaying, isTrue);
      await value.setSidebarAppearance(
        value.sidebarAppearance.copyWith(opacity: 0),
      );
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);
      await value.setSidebarAppearance(
        value.sidebarAppearance.copyWith(opacity: 1),
      );
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);
      expect(controllers, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
