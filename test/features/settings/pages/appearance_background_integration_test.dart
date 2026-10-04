import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_assistant_background.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/chat/widgets/frosted/chat_frosted_backdrop.dart';
import 'package:Kelivo/features/settings/pages/appearance_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../support/business_test_harness.dart';

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

Future<Uint8List> _previewPixels(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('appearancePreview')));
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(ChatBackground).last,
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(() => image.toByteData());
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<void> _dragSlider(WidgetTester tester, String key, double target) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final slider = tester.widget<SfSlider>(finder);
  final rect = tester.getRect(finder);
  final current = (slider.value as double) / (slider.max - slider.min);
  final start = Offset(
    rect.left + 16 + (rect.width - 32) * current,
    rect.center.dy,
  );
  final end = Offset(
    rect.left + 16 + (rect.width - 32) * target,
    rect.center.dy,
  );
  final gesture = await tester.startGesture(start);
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _chooseFit(WidgetTester tester, String label) async {
  final fit = find.byKey(const ValueKey('appearanceFit'));
  await tester.ensureVisible(fit);
  await tester.pumpAndSettle();
  await tester.tap(fit);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a dark appearance slider changes the actual dark chat artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    addTearDown(settings.dispose);
    const initial = ChatAppearanceSettings(
      shared: false,
      dark: ChatBackgroundSettings(
        type: ChatBackgroundType.gradient,
        gradientAnimated: false,
        maskStrength: 0,
      ),
    );
    await settings.setChatAppearance(initial);
    final navigatorKey = GlobalKey<NavigatorState>();
    final homeKey = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(brightness: Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RepaintBoundary(
            key: homeKey,
            child: ChatFrostedBackdrop(
              backdrop: const ChatAssistantBackground(),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppearanceSettingsPage(),
                        ),
                      ),
                      child: const Text('Open appearance'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = await _pixels(tester, homeKey);
    await tester.tap(find.text('Open appearance'));
    await tester.pumpAndSettle();
    final brightness = find.byKey(const ValueKey('appearanceBrightness'));
    await tester.ensureVisible(brightness);
    await tester.pumpAndSettle();
    final sliderRect = tester.getRect(brightness);
    final gesture = await tester.startGesture(sliderRect.center);
    await gesture.moveBy(Offset(-sliderRect.width * .25, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(settings.chatAppearance.dark.brightness, lessThan(.9));
    expect(settings.chatAppearance.light, initial.light);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    final after = await _pixels(tester, homeKey);
    expect(after, isNot(orderedEquals(before)));
    expect(after[0], lessThan(before[0]));
    expect(after[1], lessThan(before[1]));
    expect(after[2], lessThan(before[2]));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shared photo controls change preview and actual chat pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('appearance-photo-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final photo = File('${directory.path}/photo.png');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 600, 600),
      Paint()..color = Colors.red,
    );
    canvas.drawRect(
      const Rect.fromLTWH(600, 0, 600, 600),
      Paint()..color = Colors.blue,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 120, 120),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1200, 600);
    final png = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    photo.writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    await tester.pumpWidget(const SizedBox());
    for (final size in [const Size(400, 850), const Size(368, 240)]) {
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(
            FileImage(photo),
            width: size.width.toInt(),
            height: size.height.toInt(),
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          tester.element(find.byType(SizedBox)),
        ),
      );
    }
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    addTearDown(settings.dispose);
    final background = ChatBackgroundSettings(
      type: ChatBackgroundType.image,
      path: photo.path,
      maskStrength: 0,
    );
    await settings.setChatAppearance(
      ChatAppearanceSettings(light: background, dark: background),
    );
    final homeKey = GlobalKey();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(brightness: Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RepaintBoundary(
            key: homeKey,
            child: ChatFrostedBackdrop(
              backdrop: const ChatAssistantBackground(),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppearanceSettingsPage(),
                        ),
                      ),
                      child: const Text('Open appearance'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final homeBefore = await _pixels(tester, homeKey);
    await tester.tap(find.text('Open appearance'));
    await tester.pumpAndSettle();
    final cover = await _previewPixels(tester);
    await _chooseFit(tester, 'Contain');
    expect(settings.chatAppearance.light.fit, ChatBackgroundFit.contain);
    expect(await _previewPixels(tester), isNot(orderedEquals(cover)));
    await _chooseFit(tester, 'Fill');
    expect(settings.chatAppearance.light.fit, ChatBackgroundFit.fill);
    final filled = await _previewPixels(tester);
    expect(filled, isNot(orderedEquals(cover)));
    await _chooseFit(tester, 'Tile');
    expect(settings.chatAppearance.light.fit, ChatBackgroundFit.tile);
    expect(await _previewPixels(tester), isNot(orderedEquals(filled)));
    await _chooseFit(tester, 'Cover');
    final centered = await _previewPixels(tester);
    final focusGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('appearancePreview'))),
    );
    await focusGesture.moveBy(const Offset(40, 0));
    await focusGesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await focusGesture.up();
    await tester.pumpAndSettle();
    expect(settings.chatAppearance.light.focusX, lessThan(0));
    expect(await _previewPixels(tester), isNot(orderedEquals(centered)));
    await _dragSlider(tester, 'appearanceSaturation', 0);
    expect(settings.chatAppearance.light.saturation, lessThan(.05));
    final grey = await _previewPixels(tester);
    for (var pixel = 0; pixel < grey.length; pixel += 4) {
      expect((grey[pixel] - grey[pixel + 1]).abs(), lessThanOrEqualTo(2));
      expect((grey[pixel + 1] - grey[pixel + 2]).abs(), lessThanOrEqualTo(2));
    }
    await _dragSlider(tester, 'appearanceBlur', 1);
    expect(settings.chatAppearance.light.blur, greaterThan(28));
    expect(await _previewPixels(tester), isNot(orderedEquals(grey)));
    await _dragSlider(tester, 'appearanceBrightness', 0);
    expect(settings.chatAppearance.light.brightness, lessThan(.05));
    final darkened = await _previewPixels(tester);
    expect(darkened[0], lessThan(10));
    expect(darkened[1], lessThan(10));
    expect(darkened[2], lessThan(10));
    await _dragSlider(tester, 'appearanceMask', 1);
    expect(settings.chatAppearance.light.maskStrength, greaterThan(1.9));
    expect(await _previewPixels(tester), isNot(orderedEquals(darkened)));
    expect(settings.chatAppearance.light, settings.chatAppearance.dark);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await _pixels(tester, homeKey), isNot(orderedEquals(homeBefore)));
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}
