import 'dart:ui' as ui;

import 'package:Kelivo/features/home/widgets/chat_input_overlay_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  testWidgets('消息画布铺到系统状态栏后方，底部覆盖层贴住底部', (tester) async {
    const rootKey = Key('root');
    const contentKey = Key('content');
    const overlayKey = Key('overlay');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: rootKey,
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(key: contentKey, color: Colors.blue),
              bottomOverlay: SizedBox(key: overlayKey, width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
    expect(tester.getBottomLeft(find.byKey(contentKey)).dy, 600);
    expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
  });

  testWidgets('底部覆盖层内的居中包装不会把输入框推到中间', (tester) async {
    const overlayKey = Key('overlay');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: Center(
                child: SizedBox(key: overlayKey, width: 200, height: 50),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
  });

  testWidgets('输入框层位于前景遮罩上方', (tester) async {
    var inputTaps = 0;
    var foregroundTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: const ColoredBox(color: Colors.blue),
              foreground: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => foregroundTaps++,
              ),
              bottomOverlay: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => inputTaps++,
                child: const SizedBox(width: 400, height: 88),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 560));
    await tester.pump();

    expect(inputTaps, 1);
    expect(foregroundTaps, 0);
  });

  testWidgets('底部覆盖层后方有渐变遮罩隔开消息内容', (tester) async {
    const fadeKey = Key('chat-input-overlay-bottom-fade');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    final fadeFinder = find.byKey(fadeKey);
    expect(fadeFinder, findsOneWidget);
    expect(tester.getTopLeft(fadeFinder).dy, 420);
    expect(tester.getBottomLeft(fadeFinder).dy, 600);

    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: fadeFinder, matching: find.byType(DecoratedBox)),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final gradient = boxDecoration.gradient as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors[1].a, greaterThan(0.80));
    // Opaque over the last fifth, where the gesture bar sits.
    expect(gradient.stops, const [0.0, 0.48, 0.8, 1.0]);
    expect(gradient.colors[2].a, 1);
    expect(gradient.colors.last.a, 1);
  });

  testWidgets('顶部导航栏后方有渐变遮罩隔开消息内容', (tester) async {
    const fadeKey = Key('chat-input-overlay-top-fade');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    final fadeFinder = find.byKey(fadeKey);
    expect(fadeFinder, findsOneWidget);
    expect(tester.getTopLeft(fadeFinder).dy, 0);
    expect(tester.getBottomLeft(fadeFinder).dy, 124);

    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: fadeFinder, matching: find.byType(DecoratedBox)),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final gradient = boxDecoration.gradient as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    // Opaque down to the header's bottom edge, fading only below it.
    expect(gradient.stops, [0.0, 100 / 124, 1.0]);
    expect(gradient.colors.first.a, 1);
    expect(gradient.colors[1].a, inInclusiveRange(0.97, 0.995));
    expect(gradient.colors.last.a, 0);
  });

  testWidgets('滚动中的消息持续绘制到系统状态栏区域', (tester) async {
    const firstMessageKey = Key('overflow-message');
    final scrollController = ScrollController(initialScrollOffset: 132);
    final listController = ListController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: SuperListView.builder(
                controller: scrollController,
                listController: listController,
                padding: const EdgeInsets.only(top: 108),
                itemCount: 12,
                itemBuilder: (context, index) => ColoredBox(
                  key: index == 0 ? firstMessageKey : null,
                  color: index.isEven
                      ? const Color(0xFF0055FF)
                      : const Color(0xFF00CC66),
                  child: const SizedBox(height: 80),
                ),
              ),
              bottomOverlay: const SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final listFinder = find.byType(SuperListView);
    expect(tester.getTopLeft(listFinder).dy, 0);
    expect(tester.getTopLeft(find.byKey(firstMessageKey)).dy, -24);

    scrollController.dispose();
    listController.dispose();
  });

  testWidgets('背景图模式下用背景覆盖顶部且不渲染纯色遮罩', (tester) async {
    const bottomFadeKey = Key('chat-input-overlay-bottom-fade');
    const bottomBackgroundKey = Key('chat-input-overlay-bottom-background');
    const topFadeKey = Key('chat-input-overlay-top-fade');
    const topBackgroundKey = Key('chat-input-overlay-top-background');
    const backgroundKey = Key('background');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              backgroundImageActive: true,
              topBackground: ColoredBox(
                key: backgroundKey,
                color: Colors.green,
              ),
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(bottomFadeKey), findsNothing);
    expect(find.byKey(bottomBackgroundKey), findsOneWidget);
    expect(find.byKey(topFadeKey), findsNothing);
    expect(find.byKey(topBackgroundKey), findsOneWidget);
    expect(find.byKey(backgroundKey), findsNWidgets(2));

    final clipRect = tester.widget<ClipRect>(
      find.ancestor(
        of: find.byKey(topBackgroundKey),
        matching: find.byType(ClipRect),
      ),
    );
    final clip = clipRect.clipper!.getClip(const Size(400, 600));
    expect(clip.height, 124);

    final bottomClipRect = tester.widget<ClipRect>(
      find.ancestor(
        of: find.byKey(bottomBackgroundKey),
        matching: find.byType(ClipRect),
      ),
    );
    final bottomClip = bottomClipRect.clipper!.getClip(const Size(400, 600));
    expect(bottomClip.top, 420);
    expect(bottomClip.height, 180);
  });

  testWidgets('键盘弹出时背景仍按键盘收起时的高度布局', (tester) async {
    const backgroundKey = Key('background');
    const contentKey = Key('content');

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget build() {
      return const MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: true,
          body: ChatInputOverlayLayout(
            topInset: 100,
            backgroundImageActive: true,
            topBackground: ColoredBox(key: backgroundKey, color: Colors.green),
            content: ColoredBox(key: contentKey, color: Colors.blue),
            bottomOverlay: SizedBox(width: 200, height: 50),
          ),
        ),
      );
    }

    await tester.pumpWidget(build());
    final closedContentHeight = tester.getSize(find.byKey(contentKey)).height;
    final closedBackgroundHeight = tester
        .getSize(find.byKey(backgroundKey).first)
        .height;
    expect(closedBackgroundHeight, closedContentHeight);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpWidget(build());

    // The body really did shrink around the keyboard...
    expect(
      tester.getSize(find.byKey(contentKey)).height,
      closedContentHeight - 300,
    );
    // ...but the artwork keeps its original box, so BoxFit.cover does not
    // re-crop and the background stays put.
    expect(
      tester.getSize(find.byKey(backgroundKey).first).height,
      closedBackgroundHeight,
    );
    expect(tester.getTopLeft(find.byKey(backgroundKey).first).dy, 0);
  });

  for (final size in [
    const Size(390, 844),
    const Size(1024, 768),
    const Size(844, 390),
  ]) {
    for (final brightness in Brightness.values) {
      for (final glass in [false, true]) {
        for (final keyboard in [false, true]) {
          testWidgets('shared wallpaper remains visible at chat edges: '
              '$size / $brightness / glass=$glass / keyboard=$keyboard', (
            tester,
          ) async {
            const wallpaper = Color(0xFF2858D0);
            const gestureInset = 24.0;
            final keyboardInset = keyboard ? 200.0 : 0.0;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            tester.view.viewPadding = const FakeViewPadding(
              top: 24,
              bottom: gestureInset,
            );
            tester.view.padding = FakeViewPadding(
              top: 24,
              bottom: keyboard ? 0 : gestureInset,
            );
            tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
            addTearDown(tester.view.reset);

            final theme = ThemeData(brightness: brightness);
            final root = GlobalKey();
            final scroll = ScrollController(initialScrollOffset: 132);
            addTearDown(scroll.dispose);
            const composer = Key('wallpaper-edge-composer');
            Widget app({bool messages = false}) => MaterialApp(
              theme: theme,
              home: RepaintBoundary(
                key: root,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: wallpaper),
                    Scaffold(
                      backgroundColor: Colors.transparent,
                      extendBodyBehindAppBar: true,
                      appBar: AppBar(
                        automaticallyImplyLeading: false,
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                      ),
                      body: ChatInputOverlayLayout(
                        topInset: 100,
                        backgroundImageActive: true,
                        frostedTopSigma: glass ? 14 : null,
                        content: messages
                            ? ListView.builder(
                                controller: scroll,
                                padding: const EdgeInsets.only(top: 108),
                                itemExtent: 80,
                                itemCount: 20,
                                itemBuilder: (context, index) => ColoredBox(
                                  key: index == 0
                                      ? const Key(
                                          'wallpaper-edge-first-message',
                                        )
                                      : null,
                                  color: index.isEven
                                      ? const Color(0xFFFFEE00)
                                      : const Color(0xFFFF0040),
                                  child: const Text('CONTRASTING MESSAGE'),
                                ),
                              )
                            : const SizedBox.expand(),
                        bottomOverlay: const SafeArea(
                          top: false,
                          left: false,
                          right: false,
                          child: SizedBox(
                            key: composer,
                            width: 300,
                            height: 50,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            await tester.pumpWidget(app());
            await tester.pump();

            final visibleHeight = size.height - keyboardInset;
            expect(
              tester.getBottomLeft(find.byKey(composer)).dy,
              visibleHeight - (keyboard ? 0 : gestureInset),
            );
            final points = [
              const Offset(4, 10), // Status bar.
              const Offset(4, 60), // Header.
              const Offset(4, 98), // Header's lower title/model line.
              Offset(4, visibleHeight - 60), // Around the composer.
              Offset(4, visibleHeight - 2), // Gesture bar / above IME.
              Offset(4, visibleHeight - gestureInset - 2), // Visible messages.
            ];
            final backdropColors = await _colorsAt(tester, root, points);
            final surface = theme.colorScheme.surface;
            final originalContrast =
                (wallpaper.r - surface.r).abs() +
                (wallpaper.g - surface.g).abs() +
                (wallpaper.b - surface.b).abs();
            for (var i = 0; i < points.length; i++) {
              final actual = backdropColors[i];
              final contrast =
                  (actual.r - surface.r).abs() +
                  (actual.g - surface.g).abs() +
                  (actual.b - surface.b).abs();
              expect(
                contrast / originalContrast,
                greaterThan(0.30),
                reason:
                    'Wallpaper is covered by a surface fill at ${points[i]}',
              );
            }

            await tester.pumpWidget(app(messages: true));
            await tester.pump();
            expect(
              tester
                  .getTopLeft(
                    find.byKey(const Key('wallpaper-edge-first-message')),
                  )
                  .dy,
              -24,
            );
            for (final offset in [132.0, 332.0]) {
              scroll.jumpTo(offset);
              await tester.pump();
              final messageColors = await _colorsAt(tester, root, points);
              if (!glass) {
                for (var i = 0; i < 3; i++) {
                  expect(
                    messageColors[i],
                    backdropColors[i],
                    reason:
                        'A scrolling message paints the title at ${points[i]}',
                  );
                }
              } else {
                expect(
                  messageColors[1],
                  isNot(backdropColors[1]),
                  reason:
                      'Glass keeps messages scrolling beneath the header blur',
                );
              }
              expect(
                messageColors[4],
                keyboard ? isNot(backdropColors[4]) : backdropColors[4],
                reason: keyboard
                    ? 'No gesture inset is reserved above the keyboard'
                    : 'A scrolling message paints the gesture area',
              );
              expect(
                messageColors.last,
                isNot(backdropColors.last),
                reason:
                    'The message canvas remains visible above the gesture area',
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }
  }
}

Future<List<Color>> _colorsAt(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final pixels = bytes!.buffer.asUint8List();
    return [
      for (final point in points)
        Color.fromARGB(
          pixels[(point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 3],
          pixels[(point.dy.toInt() * image.width + point.dx.toInt()) * 4],
          pixels[(point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 1],
          pixels[(point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 2],
        ),
    ];
  } finally {
    image.dispose();
  }
}
