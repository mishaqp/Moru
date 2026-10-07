import "../support/business_test_harness.dart";
import '../support/long_chat_harness.dart' show installLongChatPlatformStubs;

import 'dart:async';
import 'dart:io';

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/chat/utils/chat_ui_work.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/chat/widgets/chat_gradient_background.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/frosted/chat_frosted_backdrop.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart'
    as scroll_ctrl;
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/message_list_view.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<ToolUIPart> _tools(int n) => <ToolUIPart>[
  for (var i = 0; i < n; i++)
    ToolUIPart(
      id: 'tool-$i',
      toolName: 'read_file',
      arguments: {'path': 'lib/foo/bar_$i.dart'},
      content: '工具返回的普通文本结果 $i',
      loading: false,
    ),
];

int _countElements(WidgetTester tester) {
  var n = 0;
  void visit(Element e) {
    n++;
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return n;
}

int _countRenderObjects(WidgetTester tester) {
  var n = 0;
  void visit(RenderObject r) {
    n++;
    r.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return n;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Keep the four original cases and their timing loop unchanged by default.
  // This opt-in run measures real backgrounds' UI work, not device raster or
  // Android video decoding: --dart-define=CHAT_BACKGROUND_BENCH=true.
  if (const bool.fromEnvironment('CHAT_BACKGROUND_BENCH')) {
    _backgroundBench();
    return;
  }

  for (final cfg in const <(int, int, bool)>[
    (40, 0, false),
    (40, 4, false),
    (40, 12, false),
    (40, 4, true),
  ]) {
    final rounds = cfg.$1;
    final perTurn = cfg.$2;
    final glass = cfg.$3;
    testWidgets('scroll rounds=$rounds tools=$perTurn glass=$glass', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2100);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final key = GlobalKey<_HState>();
      await tester.pumpWidget(_H(key: key, rounds: rounds, perTurn: perTurn));
      await tester.pump(const Duration(milliseconds: 100));
      final state = key.currentState!;
      // Measure settled scrolling, excluding one-off preference migrations.
      await state.settings.loaded;
      await tester.pump(const Duration(milliseconds: 100));
      if (glass) {
        await state.settings.setGlassTheme(true);
        await tester.pump(const Duration(milliseconds: 100));
      }

      final elements = _countElements(tester);
      final renders = _countRenderObjects(tester);

      // Root rebuild (what a HomePage setState costs).
      final rb = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        state.bump();
        await tester.pump();
      }
      rb.stop();

      // Scroll from bottom to top in ~40 steps.
      final pos = state.scrollController.position;
      final total = pos.maxScrollExtent;
      final sc = Stopwatch()..start();
      var frames = 0;
      final worst = <int>[];
      for (var i = 0; i < 40; i++) {
        final f = Stopwatch()..start();
        pos.jumpTo((total * (1 - i / 40)).clamp(0.0, total));
        await tester.pump();
        f.stop();
        worst.add(f.elapsedMicroseconds);
        frames++;
      }
      sc.stop();
      worst.sort();
      // Walk the whole list slowly so every item gets measured.
      var corrections = 0;
      var prev = pos.maxScrollExtent;
      for (var i = 0; i <= 200; i++) {
        pos.jumpTo(
          (pos.maxScrollExtent * (i / 200)).clamp(0.0, pos.maxScrollExtent),
        );
        await tester.pump();
        if ((pos.maxScrollExtent - prev).abs() > 1) corrections++;
        prev = pos.maxScrollExtent;
      }
      final measuredExtent = pos.maxScrollExtent;

      // ignore: avoid_print
      print(
        'RESULT rounds=$rounds tools=$perTurn glass=$glass elements=$elements renders=$renders '
        'estExtent=${total.toStringAsFixed(0)} measuredExtent=${measuredExtent.toStringAsFixed(0)} '
        'extentCorrections=$corrections '
        'rootRebuildMs=${(rb.elapsedMicroseconds / 20 / 1000).toStringAsFixed(2)} '
        'scrollAvgMs=${(sc.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} '
        'scrollP90Ms=${(worst[(frames * 0.9).floor()] / 1000).toStringAsFixed(2)} '
        'scrollMaxMs=${(worst.last / 1000).toStringAsFixed(2)}',
      );
    });
  }
}

void _backgroundBench() {
  setUp(() {
    installLongChatPlatformStubs();
    const tts = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(tts, (call) async {
      return switch (call.method) {
        'getLanguages' => <String>['en-US'],
        'getEngines' => <String>[],
        _ => 1,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(tts, null));
  });

  for (final mode in const [
    'none',
    'image',
    'gif',
    'gradient-static',
    'gradient-animated',
  ]) {
    for (final glass in const [false, true]) {
      testWidgets('background scroll mode=$mode glass=$glass', (tester) async {
        tester.view.physicalSize = const Size(1170, 2100);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        addTearDown(() => ChatUiWork.debugObserver = null);

        final directory = Directory.systemTemp.createTempSync('chat-bg-bench-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final first = image.Image(width: 64, height: 96, frameDuration: 68);
        image.fill(first, color: image.ColorRgb8(48, 112, 176));
        final png = File('${directory.path}/wallpaper.png')
          ..writeAsBytesSync(image.encodePng(first));
        final second = image.Image(width: 64, height: 96, frameDuration: 68);
        image.fill(second, color: image.ColorRgb8(176, 80, 48));
        first.addFrame(second);
        final gif = File('${directory.path}/wallpaper.gif')
          ..writeAsBytesSync(image.encodeGif(first));
        final configuration = switch (mode) {
          'image' => ChatBackgroundSettings(
            type: ChatBackgroundType.image,
            path: png.path,
          ),
          'gif' => ChatBackgroundSettings(
            type: ChatBackgroundType.gif,
            path: gif.path,
          ),
          'gradient-static' => const ChatBackgroundSettings(
            type: ChatBackgroundType.gradient,
            gradientAnimated: false,
          ),
          'gradient-animated' => const ChatBackgroundSettings(
            type: ChatBackgroundType.gradient,
          ),
          _ => const ChatBackgroundSettings(),
        };
        // Start file IO and codec decoding in the real async zone before the
        // renderer mounts. Awaiting an already-started fake-zone image decode
        // inside runAsync prevents its first-frame callback from completing.
        if (mode == 'image' || mode == 'gif') {
          await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
          var mediaReady = false;
          Object? mediaError;
          await tester.runAsync(() async {
            unawaited(
              precacheImage(
                ResizeImage(
                  FileImage(mode == 'image' ? png : gif),
                  width: 1170,
                  height: 2100,
                  policy: ResizeImagePolicy.fit,
                  allowUpscaling: false,
                ),
                tester.element(find.byType(SizedBox).first),
                onError: (error, _) => mediaError = error,
              ).then((_) => mediaReady = true),
            );
            await Future<void>.delayed(Duration.zero);
          });
          final loading = Stopwatch()..start();
          // Animated image streams publish their first decoded frame from a
          // frame callback. Pump outside runAsync while IO/codec work finishes.
          while (!mediaReady) {
            if (loading.elapsed > const Duration(seconds: 10)) {
              throw TimeoutException('Background fixture first frame');
            }
            await tester.pump(const Duration(milliseconds: 34));
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          }
          if (mediaError != null) throw mediaError!;
        }
        final key = GlobalKey<_HState>();
        await tester.pumpWidget(
          _H(key: key, rounds: 40, perTurn: 4, background: configuration),
        );
        final state = key.currentState!;
        await state.settings.loaded;
        await state.settings.setChatAppearance(
          ChatAppearanceSettings(light: configuration),
        );
        if (glass) await state.settings.setGlassTheme(true);
        await tester.pump(const Duration(milliseconds: 100));

        var decodedWidth = 0;
        var decodedHeight = 0;
        var imageFrames = 0;
        ImageStream? imageStream;
        ImageStreamListener? imageListener;
        Future<void> disposeBackground() async {
          final stream = imageStream;
          final listener = imageListener;
          if (stream != null && listener != null) {
            stream.removeListener(listener);
          }
          imageStream = null;
          imageListener = null;
          await tester.pumpWidget(const SizedBox.shrink());
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }

        addTearDown(disposeBackground);
        final imageWidgets = tester.widgetList<Image>(
          find.descendant(
            of: find.byType(ChatBackground),
            matching: find.byType(Image),
          ),
        );
        if (imageWidgets.isNotEmpty) {
          final stream = imageWidgets.first.image.resolve(
            createLocalImageConfiguration(
              tester.element(find.byType(ChatBackground)),
            ),
          );
          final listener = ImageStreamListener((info, _) {
            decodedWidth = info.image.width;
            decodedHeight = info.image.height;
            imageFrames++;
            info.dispose();
          });
          stream.addListener(listener);
          imageStream = stream;
          imageListener = listener;
        }
        // Advance real media/gradient clocks, unlike the original zero-time
        // pump loop. The event-loop yield lets native GIF decoding finish.
        Future<void> pumpFrame() async {
          await tester.pump(const Duration(milliseconds: 34));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }

        for (var i = 0; i < 10; i++) {
          await pumpFrame();
        }
        final work = <String, int>{};
        ChatUiWork.debugObserver = (name, _, _) {
          work.update(name, (count) => count + 1, ifAbsent: () => 1);
        };
        final picturesBefore = debugGradientPictureBuildCount;
        final shadersBefore = debugGradientShaderBuildCount;
        final filtersBefore = debugChatBackgroundFilterBuildCount;
        final providersBefore = debugChatBackgroundImageProviderBuildCount;
        final capturesBefore = state.backdropController?.debugCaptureCount ?? 0;
        final imageFramesBefore = imageFrames;

        final rebuild = Stopwatch()..start();
        for (var i = 0; i < 20; i++) {
          state.bump();
          await pumpFrame();
        }
        rebuild.stop();
        final position = state.scrollController.position;
        final extent = position.maxScrollExtent;
        final scroll = Stopwatch()..start();
        final frames = <int>[];
        for (var i = 0; i < 40; i++) {
          final frame = Stopwatch()..start();
          position.jumpTo((extent * (1 - i / 40)).clamp(0.0, extent));
          await pumpFrame();
          frame.stop();
          frames.add(frame.elapsedMicroseconds);
        }
        scroll.stop();
        frames.sort();
        final activeBuilds = work['message.build'] ?? 0;
        final activeDecodes = work['timeline.jsonDecode'] ?? 0;
        // Settle new list rows before measuring background-only animation.
        for (var i = 0; i < 5; i++) {
          await pumpFrame();
        }
        work.clear();
        final idlePosition = position.pixels;
        final idlePicturesBefore = debugGradientPictureBuildCount;
        final idleImageFramesBefore = imageFrames;
        for (var i = 0; i < 90; i++) {
          await pumpFrame();
        }

        // ignore: avoid_print
        print(
          'BACKGROUND_RESULT mode=$mode glass=$glass rounds=40 tools=4 '
          'rootRebuildMs=${(rebuild.elapsedMicroseconds / 20 / 1000).toStringAsFixed(2)} '
          'scrollAvgMs=${(scroll.elapsedMicroseconds / 40 / 1000).toStringAsFixed(2)} '
          'scrollP90Ms=${(frames[36] / 1000).toStringAsFixed(2)} '
          'scrollMaxMs=${(frames.last / 1000).toStringAsFixed(2)} '
          'activeMessageBuilds=$activeBuilds activeJsonDecodes=$activeDecodes '
          'idleMessageBuilds=${work['message.build'] ?? 0} '
          'idleJsonDecodes=${work['timeline.jsonDecode'] ?? 0} '
          'idleScrollDelta=${(position.pixels - idlePosition).abs().toStringAsFixed(2)} '
          'decodedPixels=${decodedWidth}x$decodedHeight '
          'imageFrames=${imageFrames - imageFramesBefore} '
          'idleImageFrames=${imageFrames - idleImageFramesBefore} '
          'gradientPictures=${debugGradientPictureBuildCount - picturesBefore} '
          'idleGradientPictures=${debugGradientPictureBuildCount - idlePicturesBefore} '
          'gradientShaders=${debugGradientShaderBuildCount - shadersBefore} '
          'filterBuilds=${debugChatBackgroundFilterBuildCount - filtersBefore} '
          'imageProviderBuilds=${debugChatBackgroundImageProviderBuildCount - providersBefore} '
          'frostedCaptures=${(state.backdropController?.debugCaptureCount ?? 0) - capturesBefore} '
          'frostedMode=${state.backdropController?.mode.name ?? 'none'}',
        );
        // Widget-test timer invariants run before addTearDown callbacks. End
        // the observation listener and GIF playback before returning the body.
        await disposeBackground();
      });
    }
  }
}

class _H extends StatefulWidget {
  const _H({
    super.key,
    required this.rounds,
    required this.perTurn,
    this.background,
  });
  final int rounds;
  final int perTurn;
  final ChatBackgroundSettings? background;

  @override
  State<_H> createState() => _HState();
}

class _HState extends State<_H> {
  final scrollController = scroll_ctrl.ChatAutoFollowScrollController();
  late final scroll_ctrl.ChatScrollController scrollCtrl;
  final processingFilesMessageId = ValueNotifier<String?>(null);
  final settings = SettingsProvider(createBusinessTestPreferences());
  ChatFrostedBackdropController? backdropController;
  int tick = 0;

  late final List<ChatMessage> messages = <ChatMessage>[
    for (var i = 0; i < widget.rounds * 2; i++)
      ChatMessage(
        id: 'm-$i',
        role: i.isEven ? 'user' : 'assistant',
        content: i.isEven ? '用户提问 $i' : '好的，我来看看。',
        conversationId: 'c1',
      ),
  ];

  late final Map<String, List<ToolUIPart>> toolParts = {
    for (var i = 1; i < widget.rounds * 2; i += 2)
      'm-$i': _tools(widget.perTurn),
  };

  @override
  void initState() {
    super.initState();
    scrollCtrl = scroll_ctrl.ChatScrollController(
      scrollController: scrollController,
      getAutoScrollEnabled: () => false,
      getAutoScrollIdleSeconds: () => 3,
      isGenerating: () => false,
    );
  }

  void bump() => setState(() => tick++);

  Widget _withBackground(Widget child) {
    final configuration = widget.background;
    if (configuration == null) return child;
    return ChatFrostedBackdrop(
      configuration: configuration,
      backdrop: ChatBackground(configuration: configuration),
      child: Builder(
        builder: (context) {
          backdropController = ChatFrostedBackdropScope.maybeOfStatic(
            context,
          )?.controller;
          return child;
        },
      ),
    );
  }

  @override
  void dispose() {
    scrollCtrl.dispose();
    scrollController.dispose();
    processingFilesMessageId.dispose();
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _withBackground(
            MessageListView(
              key: ValueKey(tick == -1),
              scrollController: scrollController,
              listController: scrollCtrl.messageListController,
              messages: messages,
              byGroup: const {},
              versionSelections: const {},
              reasoning: const {},
              reasoningSegments: const {},
              contentSplits: const {},
              toolParts: toolParts,
              translations: const {},
              selecting: false,
              selectedItems: const {},
              dividerPadding: EdgeInsets.zero,
              processingFilesMessageId: processingFilesMessageId,
            ),
          ),
        ),
      ),
    );
  }
}
