import '../../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_surface.dart';
import 'package:Kelivo/features/chat/widgets/frosted/chat_frosted_backdrop.dart';
import 'package:Kelivo/features/chat/widgets/frosted/frosted_surface.dart';
import 'package:Kelivo/features/home/widgets/chat_input_overlay_layout.dart';
import 'package:Kelivo/features/settings/pages/glass_theme_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Future<SettingsProvider> _settings() async {
  final harness = await createBusinessTestHarness(initial: {});
  final settings = SettingsProvider(harness.preferences);
  await settings.loaded;
  return settings;
}

Widget _app(SettingsProvider settings, Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ChangeNotifierProvider<AssistantProvider>(
      create: (_) =>
          AssistantProvider(preferences: createBusinessTestPreferences()),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('glass settings default off and persist', () async {
    final harness = await createBusinessTestHarness(initial: {});
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    expect(settings.glassTheme, isFalse);
    expect(settings.glassFrost, GlassFrost.medium);
    expect(settings.glassEconomy, isFalse);

    await settings.setGlassTheme(true);
    await settings.setGlassFrost(GlassFrost.strong);
    await settings.setGlassEconomy(true);

    final reloaded = SettingsProvider(harness.preferences);
    await reloaded.loaded;
    expect(reloaded.glassTheme, isTrue);
    expect(reloaded.glassFrost, GlassFrost.strong);
    expect(reloaded.glassEconomy, isTrue);
    settings.dispose();
    reloaded.dispose();
  });

  testWidgets('glass puts the gradient behind a chat without wallpaper', (
    tester,
  ) async {
    final settings = await _settings();
    late ChatBackdropSpec spec;
    await tester.pumpWidget(
      _app(
        settings,
        Builder(
          builder: (context) {
            spec = ChatBackdropSpec.resolve(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(spec.active, isFalse);
    expect(spec.useGradientBackground, isFalse);

    await settings.setGlassTheme(true);
    await tester.pump();
    expect(spec.active, isTrue);
    expect(spec.useGradientBackground, isTrue);
  });

  testWidgets('glass bubbles are frosted with the chosen blur', (tester) async {
    final settings = await _settings();
    await tester.pumpWidget(
      _app(
        settings,
        Builder(
          builder: (context) => buildSharedChatSurface(
            context,
            borderRadius: BorderRadius.circular(16),
            padding: EdgeInsets.zero,
            child: const Text('reply'),
          ),
        ),
      ),
    );
    expect(find.byType(FrostedSurface), findsNothing);

    await settings.setGlassTheme(true);
    await settings.setGlassFrost(GlassFrost.strong);
    await tester.pump();
    final strong = tester.widget<FrostedSurface>(find.byType(FrostedSurface));
    expect(strong.style.blurSigma, GlassFrost.strong.sigma);

    await settings.setGlassEconomy(true);
    await tester.pump();
    final economy = tester.widget<FrostedSurface>(find.byType(FrostedSurface));
    expect(economy.style.blurSigma, 0);
  });

  testWidgets('frosted header replaces the background copy', (tester) async {
    Widget layout({double? sigma}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: ChatInputOverlayLayout(
            topInset: 100,
            content: const ColoredBox(color: Colors.blue),
            bottomOverlay: const SizedBox(width: 200, height: 50),
            topBackground: const ColoredBox(color: Colors.red),
            backgroundImageActive: true,
            frostedTopSigma: sigma,
          ),
        ),
      ),
    );

    await tester.pumpWidget(layout());
    expect(
      find.byKey(const Key('chat-input-overlay-top-background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('chat-input-overlay-top-frosted')),
      findsNothing,
    );

    await tester.pumpWidget(layout(sigma: 14));
    expect(
      find.byKey(const Key('chat-input-overlay-top-frosted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('chat-input-overlay-top-background')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const Key('chat-input-overlay-top-frosted'))),
      const Size(400, 100),
    );
  });

  testWidgets('glass page switches the theme, frost and economy mode', (
    tester,
  ) async {
    final settings = await _settings();
    await tester.pumpWidget(_app(settings, const GlassThemeSettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('glassTheme')));
    await tester.pumpAndSettle();
    expect(settings.glassTheme, isTrue);

    await tester.tap(find.byKey(const ValueKey('glassFrost-soft')));
    await tester.pumpAndSettle();
    expect(settings.glassFrost, GlassFrost.soft);

    await tester.tap(find.byKey(const ValueKey('glassEconomy')));
    await tester.pumpAndSettle();
    expect(settings.glassEconomy, isTrue);
  });
}
