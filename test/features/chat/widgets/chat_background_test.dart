import 'dart:io';
import 'dart:ui' as ui;

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/chat/widgets/chat_gradient_background.dart';
import 'package:Kelivo/features/chat/widgets/frosted/chat_frosted_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  testWidgets('photo fit, focus and effects reuse a screen-bounded decode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('chat-background-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/photo.png');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1000, 1000),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(1000, 0, 1000, 1000),
      Paint()..color = const Color(0xFF0000FF),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2000, 1000);
    final png = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    file.writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();

    await tester.pumpWidget(const SizedBox());
    final provider = ResizeImage(
      FileImage(file),
      width: 100,
      height: 100,
      policy: ResizeImagePolicy.fit,
    );
    await tester.runAsync(
      () => precacheImage(provider, tester.element(find.byType(SizedBox))),
    );
    final key = GlobalKey();
    var settings = ChatBackgroundSettings(
      type: ChatBackgroundType.image,
      path: file.path,
      maskStrength: 0,
    );
    Widget app() => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: RepaintBoundary(
            key: key,
            child: ChatBackground(
              configuration: settings,
              includeSurfaceFill: true,
            ),
          ),
        ),
      ),
    );
    Future<Color> sample(int x, int y) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = boundary.toImageSync();
      final bytes = await tester.runAsync(() => rendered.toByteData());
      final pixels = bytes!.buffer.asUint8List();
      final index = (y * rendered.width + x) * 4;
      final color = Color.fromARGB(
        pixels[index + 3],
        pixels[index],
        pixels[index + 1],
        pixels[index + 2],
      );
      rendered.dispose();
      return color;
    }

    settings = settings.copyWith(focusX: -1);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(await sample(25, 50), const Color(0xFFFF0000));
    settings = settings.copyWith(focusX: 1);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(await sample(75, 50), const Color(0xFF0000FF));
    final resized =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(resized.width, 100);
    expect(resized.height, 100);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(resized.allowUpscaling, isFalse);
    final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(decoded.width, lessThanOrEqualTo(100));
    expect(decoded.height, lessThanOrEqualTo(100));

    settings = settings.copyWith(fit: ChatBackgroundFit.contain, focusX: 0);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(await sample(25, 50), const Color(0xFFFF0000));
    expect(await sample(75, 50), const Color(0xFF0000FF));
    expect(await sample(25, 5), isNot(const Color(0xFFFF0000)));
    settings = settings.copyWith(fit: ChatBackgroundFit.fill);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(await sample(25, 5), const Color(0xFFFF0000));
    settings = settings.copyWith(fit: ChatBackgroundFit.tile);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(tester.widget<Image>(find.byType(Image)).repeat, ImageRepeat.repeat);
    expect(await sample(25, 5), await sample(25, 55));

    settings = settings.copyWith(
      fit: ChatBackgroundFit.fill,
      saturation: 0,
      brightness: 0.5,
      blur: 4,
    );
    await tester.pumpWidget(app());
    await tester.pump();
    final grey = await sample(25, 50);
    expect((grey.r - grey.g).abs(), lessThan(0.01));
    expect((grey.g - grey.b).abs(), lessThan(0.01));
    final filters = debugChatBackgroundFilterBuildCount;
    final providers = debugChatBackgroundImageProviderBuildCount;
    for (var frame = 0; frame < 10; frame++) {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(debugChatBackgroundFilterBuildCount, filters);
    expect(debugChatBackgroundImageProviderBuildCount, providers);
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'explicit none stays empty in Glass and economy freezes gradient',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;
      await settings.setGlassTheme(true);
      addTearDown(settings.dispose);
      var configuration = const ChatBackgroundSettings();
      Widget app() => ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: ChatFrostedBackdrop(
            configuration: configuration,
            backdrop: ChatBackground(configuration: configuration),
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpWidget(app());
      expect(find.byType(ChatGradientBackground), findsNothing);
      expect(find.byType(Image), findsNothing);
      final controller = tester
          .widget<ChatFrostedBackdropScope>(
            find.byType(ChatFrostedBackdropScope),
          )
          .controller;
      expect(controller.mode, FrostedRenderMode.uniform);

      configuration = const ChatBackgroundSettings(
        type: ChatBackgroundType.gradient,
      );
      await tester.pumpWidget(app());
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settings.setGlassEconomy(true);
      await tester.pump();
      final pictures = debugGradientPictureBuildCount;
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(debugGradientPictureBuildCount, pictures);
      expect(tester.binding.transientCallbackCount, 0);
      await settings.setGlassEconomy(false);
      await tester.pump();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(debugGradientPictureBuildCount, greaterThan(pictures));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
