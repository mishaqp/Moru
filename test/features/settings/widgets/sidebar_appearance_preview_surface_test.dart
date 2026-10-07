import 'dart:ui' as ui;

import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/sidebar_omni_parts.dart';
import 'package:Kelivo/features/settings/widgets/sidebar_appearance_preview.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final height in [160.0, 240.0]) {
      testWidgets('preview surfaces follow opacity draft before save '
          '${brightness.name} height=$height', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const saved = SidebarAppearanceSettings(
          backgroundMode: SidebarBackgroundMode.theme,
        );
        final settings = (await tester.runAsync(() async {
          final value = SettingsProvider(createBusinessTestPreferences());
          await value.loaded;
          await value.setSidebarAppearance(saved);
          return value;
        }))!;
        addTearDown(settings.dispose);
        final key = GlobalKey();
        final theme = ThemeData(
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: brightness,
              ).copyWith(
                surface: const Color(0xffff0000),
                surfaceContainerLow: const Color(0xff00ff00),
              ),
        );

        Future<void> pump(SidebarAppearanceSettings draft) async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: settings,
              child: MaterialApp(
                theme: theme,
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 360,
                      child: RepaintBoundary(
                        key: key,
                        child: SidebarAppearancePreview(
                          appearance: draft,
                          backgroundConfiguration:
                              const ChatBackgroundSettings(),
                          theme: theme,
                          height: height,
                          showThumbnails: false,
                          shortcuts: const [],
                          glass: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }

        await pump(saved);
        final dock = tester.getRect(find.byType(SidebarDockCapsule));
        final panel = tester.getRect(
          find.byKey(const ValueKey('appearanceSidebarPreviewPanel')),
        );
        final samples = <String, Offset>{
          'panel backdrop': Offset(panel.right - 2, panel.center.dy),
          'dock': Offset(dock.center.dx, dock.top + 4),
        };
        if (height >= 180) {
          final search = tester.getRect(find.byType(SidebarSearchField));
          samples['search'] = Offset(search.center.dx, search.top + 4);
        }
        final opaque = await _pixelsAt(tester, key, samples);

        // The settings slider renders its local draft during a drag and
        // persists only on release. The control surfaces must respond to
        // that draft along with the backdrop while the provider stays saved.
        await pump(saved.copyWith(opacity: .25));
        final translucent = await _pixelsAt(tester, key, samples);
        for (final sample in samples.keys) {
          expect(
            translucent[sample]!.g - opaque[sample]!.g,
            greaterThan(20),
            reason:
                '$sample must reveal the green base during the draft; '
                '${opaque[sample]} became ${translucent[sample]}',
          );
        }
        expect(settings.sidebarAppearance, saved);

        // The opposite draft must also override saved clear surfaces.
        // A false draft value must not fall through to the provider.
        final savedTranslucent = saved.copyWith(opacity: .25);
        await tester.runAsync(
          () => settings.setSidebarAppearance(savedTranslucent),
        );
        await pump(saved);
        expect(await _pixelsAt(tester, key, samples), opaque);
        expect(settings.sidebarAppearance, savedTranslucent);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

Future<Map<String, ({int r, int g, int b})>> _pixelsAt(
  WidgetTester tester,
  GlobalKey key,
  Map<String, Offset> samples,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return {
      for (final sample in samples.entries)
        sample.key: (
          r: bytes!.getUint8(
            (sample.value.dy.floor() * image.width + sample.value.dx.floor()) *
                4,
          ),
          g: bytes.getUint8(
            (sample.value.dy.floor() * image.width + sample.value.dx.floor()) *
                    4 +
                1,
          ),
          b: bytes.getUint8(
            (sample.value.dy.floor() * image.width + sample.value.dx.floor()) *
                    4 +
                2,
          ),
        ),
    };
  } finally {
    image.dispose();
  }
}
