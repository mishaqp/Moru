import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_background.dart';
import 'package:Kelivo/features/home/widgets/sidebar_glass.dart';
import 'package:Kelivo/features/settings/widgets/sidebar_appearance_preview.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

Future<Uint8List> _pixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(() => image.toByteData());
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void _expectCrop(
  Uint8List panel,
  Uint8List screen,
  int width,
  int screenWidth,
) {
  for (var row = 0; row < panel.length ~/ (width * 4); row++) {
    expect(
      panel.sublist(row * width * 4, (row + 1) * width * 4),
      orderedEquals(
        screen.sublist(row * screenWidth * 4, (row * screenWidth + width) * 4),
      ),
      reason: 'The panel must show the screen artwork at row $row',
    );
  }
}

void main() {
  Future<(SettingsProvider, ChatBackgroundSettings)> setup(
    WidgetTester tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('sidebar-frame-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 960, 640),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(960, 640),
          [Colors.red, Colors.green, Colors.blue],
          [0, .5, 1],
        ),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(960, 640);
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    final file = File('${directory.path}/photo.png')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    final settings = (await tester.runAsync(() async {
      final value = SettingsProvider(createBusinessTestPreferences());
      await value.loaded;
      return value;
    }))!;
    addTearDown(settings.dispose);
    return (
      settings,
      ChatBackgroundSettings(
        type: ChatBackgroundType.image,
        path: file.path,
        focusX: .6,
        focusY: -.4,
        maskStrength: 0,
      ),
    );
  }

  Future<void> preload(
    WidgetTester tester,
    String path,
    List<Size> sizes,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    for (final size in sizes) {
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(
            FileImage(File(path)),
            width: size.width.ceil(),
            height: size.height.ceil(),
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          context,
        ),
      );
    }
  }

  for (final size in [
    const Size(390, 844),
    const Size(800, 600),
    const Size(844, 390),
  ]) {
    for (final fit in ChatBackgroundFit.values) {
      for (final glass in [false, true]) {
        testWidgets(
          'shared artwork preserves screen frame $size $fit glass=$glass',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final (settings, initial) = await setup(tester);
            final background = initial.copyWith(fit: fit);
            final appearance = SidebarAppearanceSettings(
              maskStrength: 0,
              blur: glass ? 8 : 0,
            );
            await tester.runAsync(() async {
              await settings.setChatAppearance(
                ChatAppearanceSettings(light: background),
              );
              await settings.setSidebarAppearance(appearance);
              if (glass) await settings.setGlassTheme(true);
            });
            const screenKey = Key('screen');
            const panelKey = Key('panel');
            final panelWidth = appearance
                .widthFor(size.width, wide: size.width >= 600)
                .floorToDouble();
            await preload(tester, background.path!, [
              size,
              Size(panelWidth, size.height),
            ]);
            await tester.pumpWidget(
              ChangeNotifierProvider.value(
                value: settings,
                child: MaterialApp(
                  theme: ThemeData(brightness: Brightness.dark),
                  home: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        key: screenKey,
                        child: glass
                            ? SidebarGlassBackdrop(
                                configuration: appearance.copyWith(
                                  backgroundMode: SidebarBackgroundMode.custom,
                                  customBackground: background,
                                ),
                              )
                            : ChatBackground(
                                configuration: background,
                                includeSurfaceFill: true,
                              ),
                      ),
                      Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: panelWidth,
                          child: const RepaintBoundary(
                            key: panelKey,
                            child: SidebarGlassBackdrop(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pump();
            _expectCrop(
              await _pixels(tester, find.byKey(panelKey)),
              await _pixels(tester, find.byKey(screenKey)),
              panelWidth.toInt(),
              size.width.toInt(),
            );
            final filters = debugChatBackgroundFilterBuildCount;
            final providers = debugChatBackgroundImageProviderBuildCount;
            await tester.pump(const Duration(milliseconds: 16));
            expect(debugChatBackgroundFilterBuildCount, filters);
            expect(debugChatBackgroundImageProviderBuildCount, providers);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  testWidgets('custom sidebar artwork keeps panel-relative fit', (
    tester,
  ) async {
    final (settings, background) = await setup(tester);
    final appearance = SidebarAppearanceSettings(
      backgroundMode: SidebarBackgroundMode.custom,
      customBackground: background,
      maskStrength: 0,
    );
    const reference = Key('reference');
    const panel = Key('panel');
    await preload(tester, background.path!, [const Size(240, 500)]);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: SizedBox.expand(
            child: Stack(
              children: [
                SizedBox(
                  width: 240,
                  height: 500,
                  child: RepaintBoundary(
                    key: reference,
                    child: ChatBackground(
                      configuration: background,
                      includeSurfaceFill: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  height: 500,
                  child: RepaintBoundary(
                    key: panel,
                    child: SidebarGlassBackdrop(configuration: appearance),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      await _pixels(tester, find.byKey(panel)),
      orderedEquals(await _pixels(tester, find.byKey(reference))),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'sidebar preview uses the full preview frame for shared artwork',
    (tester) async {
      final (settings, background) = await setup(tester);
      const appearance = SidebarAppearanceSettings(maskStrength: 0);
      final theme = ThemeData(brightness: Brightness.dark);
      await tester.runAsync(
        () => settings.setChatAppearance(
          ChatAppearanceSettings(light: background),
        ),
      );
      const reference = Key('reference');
      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final panelWidth =
          appearance.widthFor(screenSize.width, wide: screenSize.width >= 600) *
          360 /
          screenSize.width;
      await preload(tester, background.path!, [
        const Size(360, 240),
        Size(panelWidth, 240),
        screenSize,
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Stack(
              children: [
                SizedBox(
                  width: 360,
                  height: 240,
                  child: RepaintBoundary(
                    key: reference,
                    child: ChatBackground(
                      configuration: background,
                      includeSurfaceFill: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: Material(
                    child: SidebarAppearancePreview(
                      appearance: appearance,
                      backgroundConfiguration: background,
                      theme: theme,
                      height: 240,
                      showThumbnails: false,
                      shortcuts: const [],
                      glass: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final backdrop = find
          .descendant(
            of: find.byType(SidebarGlassBackdrop),
            matching: find.byType(RepaintBoundary),
          )
          .first;
      expect(tester.getSize(backdrop), const Size(360, 240));
      final width = tester.getSize(backdrop).width.toInt();
      _expectCrop(
        await _pixels(tester, backdrop),
        await _pixels(tester, find.byKey(reference)),
        width,
        360,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
