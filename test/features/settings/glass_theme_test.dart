import '../../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/models/chat_appearance.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_surface.dart';
import 'package:Kelivo/features/chat/widgets/frosted/chat_frosted_backdrop.dart';
import 'package:Kelivo/features/chat/widgets/frosted/frosted_surface.dart';
import 'package:Kelivo/features/home/widgets/chat_input_overlay_layout.dart';
import 'package:Kelivo/features/settings/pages/glass_theme_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/theme/chat_bubble_style.dart';

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
    expect(settings.glassEconomy, isFalse);

    await settings.setGlassTheme(true);
    await settings.setGlassEconomy(true);

    final reloaded = SettingsProvider(harness.preferences);
    await reloaded.loaded;
    expect(reloaded.glassTheme, isTrue);
    expect(reloaded.glassEconomy, isTrue);
    settings.dispose();
    reloaded.dispose();
  });

  test(
    'glass writes the message style and restores the previous one',
    () async {
      final harness = await createBusinessTestHarness(initial: {});
      final settings = SettingsProvider(harness.preferences);
      await settings.loaded;
      await settings.setChatMessageBackgroundStyle(
        ChatMessageBackgroundStyle.solid,
      );
      const mine = ChatBubbleStyleOverrides(cornerRadius: 6, blurSigma: 9);
      await settings.setChatBubbleStyleOverrides(mine);

      await settings.setGlassTheme(
        true,
        accentLight: const Color(0xFF5B48E8),
        accentDark: const Color(0xFF6F5CF6),
      );
      expect(
        settings.chatMessageBackgroundStyle,
        ChatMessageBackgroundStyle.frosted,
      );
      final assistant = settings.assistantChatBubbleStyleOverrides;
      expect(assistant.frostedOpacity, 0.34);
      expect(assistant.blurSigma, 9, reason: 'the user blur carries over');
      final user = settings.userChatBubbleStyleOverrides;
      expect(user.backgroundArgbLight, 0xFF5B48E8);
      expect(user.backgroundArgbDark, 0xFF6F5CF6);

      // The glass style and the saved one survive a restart.
      final reloaded = SettingsProvider(harness.preferences);
      await reloaded.loaded;
      expect(
        reloaded.chatMessageBackgroundStyle,
        ChatMessageBackgroundStyle.frosted,
      );
      await reloaded.setGlassTheme(false);
      expect(
        reloaded.chatMessageBackgroundStyle,
        ChatMessageBackgroundStyle.solid,
      );
      expect(reloaded.assistantChatBubbleStyleOverrides, mine);
      expect(reloaded.userChatBubbleStyleOverrides, mine);

      final again = SettingsProvider(harness.preferences);
      await again.loaded;
      expect(again.glassTheme, isFalse);
      expect(
        again.chatMessageBackgroundStyle,
        ChatMessageBackgroundStyle.solid,
      );
      expect(again.assistantChatBubbleStyleOverrides, mine);
      for (final s in [settings, reloaded, again]) {
        s.dispose();
      }
    },
  );

  testWidgets(
    'glass respects global none and an explicitly selected gradient',
    (tester) async {
      final settings = await _settings();
      addTearDown(settings.dispose);
      await settings.setChatAppearance(const ChatAppearanceSettings());
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
      expect(spec.active, isFalse);
      expect(spec.useGradientBackground, isFalse);

      await settings.setChatAppearance(
        const ChatAppearanceSettings(
          light: ChatBackgroundSettings(type: ChatBackgroundType.gradient),
        ),
      );
      await tester.pump();
      expect(spec.active, isTrue);
      expect(spec.useGradientBackground, isTrue);
    },
  );

  testWidgets('glass bubbles are frosted; economy drops the blur', (
    tester,
  ) async {
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
    await tester.pump();
    final frosted = tester.widget<FrostedSurface>(find.byType(FrostedSurface));
    expect(frosted.style.blurSigma, 14);

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

  testWidgets('glass page switches the theme and economy mode', (tester) async {
    final settings = await _settings();
    await tester.pumpWidget(_app(settings, const GlassThemeSettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('glassTheme')));
    await tester.pumpAndSettle();
    expect(settings.glassTheme, isTrue);
    expect(
      settings.userChatBubbleStyleOverrides.backgroundArgbLight,
      isNotNull,
      reason: 'the page hands the palette accent to the preset',
    );

    await tester.tap(find.byKey(const ValueKey('glassEconomy')));
    await tester.pumpAndSettle();
    expect(settings.glassEconomy, isTrue);
  });
}
