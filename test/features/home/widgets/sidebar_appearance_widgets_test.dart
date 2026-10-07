import 'package:Kelivo/core/models/sidebar_appearance.dart';
import 'package:Kelivo/features/home/widgets/sidebar_omni_parts.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    SidebarAppearanceSettings appearance, {
    bool current = false,
    bool selected = false,
    bool selectionMode = false,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                child: SidebarConversationCard(
                  appearance: appearance,
                  title: 'Conversation title',
                  isCurrent: current,
                  isSelected: selected,
                  selectionMode: selectionMode,
                  preview: 'The latest visible message',
                  timestamp: 'Oct 4, 2026 12:34',
                  assistantName: 'A helpful assistant with a long name',
                  modelName: 'A model with a long name',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ThemeData cardTheme(Brightness brightness) => ThemeData(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        ).copyWith(
          surface: brightness == Brightness.dark ? Colors.black : Colors.white,
          onSurface: brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
  );

  double contrastRatio(Color foreground, Color background) {
    final visible = Color.alphaBlend(foreground, background).computeLuminance();
    final surface = background.computeLuminance();
    return visible > surface
        ? (visible + 0.05) / (surface + 0.05)
        : (surface + 0.05) / (visible + 0.05);
  }

  void expectReadableCard(WidgetTester tester, Color background) {
    final card = find.byType(SidebarConversationCard);
    for (final text in tester.widgetList<Text>(
      find.descendant(of: card, matching: find.byType(Text)),
    )) {
      expect(
        contrastRatio(text.style!.color!, background),
        greaterThanOrEqualTo(4.5),
        reason: '${text.data} must be readable on $background',
      );
    }
    for (final icon in tester.widgetList<Icon>(
      find.descendant(of: card, matching: find.byType(Icon)),
    )) {
      expect(
        contrastRatio(icon.color!, background),
        greaterThanOrEqualTo(3),
        reason: 'Metadata icons must be readable on $background',
      );
    }
  }

  testWidgets('default card preserves a title without optional metadata', (
    tester,
  ) async {
    await pumpCard(tester, const SidebarAppearanceSettings());
    expect(find.text('Conversation title'), findsOneWidget);
    expect(find.text('The latest visible message'), findsNothing);
    expect(find.text('Oct 4, 2026 12:34'), findsNothing);
    expect(find.text('A helpful assistant with a long name'), findsNothing);
    expect(find.text('A model with a long name'), findsNothing);
    final press = tester.widget<IosCardPress>(find.byType(IosCardPress));
    expect(press.baseColor, Colors.transparent);
    expect(press.borderRadius, BorderRadius.circular(14));
  });

  testWidgets('card flags display independent metadata at large text scale', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const SidebarAppearanceSettings(
        showPreview: true,
        showTimestamp: true,
        showAssistant: true,
        showModel: true,
      ),
      textScale: 1.3,
    );
    for (final text in [
      'Conversation title',
      'The latest visible message',
      'Oct 4, 2026 12:34',
      'A helpful assistant with a long name',
      'A model with a long name',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    final preview = tester.widget<Text>(
      find.text('The latest visible message'),
    );
    expect(preview.maxLines, 1);

    await pumpCard(tester, const SidebarAppearanceSettings(showModel: true));
    expect(find.text('A model with a long name'), findsOneWidget);
    expect(find.text('A helpful assistant with a long name'), findsNothing);
    expect(find.text('Oct 4, 2026 12:34'), findsNothing);
  });

  testWidgets('card density, radius and translucent active fill are applied', (
    tester,
  ) async {
    final heights = <double>[];
    for (final density in SidebarDensity.values) {
      await pumpCard(
        tester,
        SidebarAppearanceSettings(
          density: density,
          cardRadius: 21,
          cardColor: 0x40112233,
          activeCardColor: 0x80445566,
        ),
        current: true,
      );
      heights.add(tester.getSize(find.byType(SidebarConversationCard)).height);
      final press = tester.widget<IosCardPress>(find.byType(IosCardPress));
      expect(press.baseColor, const Color(0x80445566));
      expect(press.borderRadius, BorderRadius.circular(21));
    }
    expect(heights[0], lessThan(heights[1]));
    expect(heights[1], lessThan(heights[2]));
  });

  testWidgets('custom fills keep card text and metadata icons readable', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final fill in [
        Colors.black,
        Colors.white,
        const Color(0xff808080),
      ]) {
        for (final current in [false, true]) {
          await pumpCard(
            tester,
            SidebarAppearanceSettings(
              cardColor: fill.toARGB32(),
              showPreview: true,
              showTimestamp: true,
              showAssistant: true,
              showModel: true,
            ),
            theme: cardTheme(brightness),
            current: current,
          );
          expectReadableCard(tester, fill);
        }
      }
    }
  });

  testWidgets('active fills keep current and selected cards readable', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final current in [false, true]) {
        await pumpCard(
          tester,
          const SidebarAppearanceSettings(
            cardColor: 0xff000000,
            activeCardColor: 0xffffffff,
            showPreview: true,
            showTimestamp: true,
            showAssistant: true,
            showModel: true,
          ),
          theme: cardTheme(brightness),
          current: current,
          selected: !current,
          selectionMode: !current,
        );
        final press = tester.widget<IosCardPress>(find.byType(IosCardPress));
        expect(press.baseColor, Colors.white);
        expectReadableCard(tester, Colors.white);
      }
    }
  });

  testWidgets('translucent custom fills account for the theme surface', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = cardTheme(brightness);
      for (final fill in [const Color(0x10000000), const Color(0x10ffffff)]) {
        await pumpCard(
          tester,
          SidebarAppearanceSettings(
            cardColor: fill.toARGB32(),
            showPreview: true,
            showTimestamp: true,
            showAssistant: true,
            showModel: true,
          ),
          theme: theme,
        );
        expectReadableCard(
          tester,
          Color.alphaBlend(fill, theme.colorScheme.surface),
        );
      }
    }
  });

  testWidgets('cards without custom fills preserve theme foregrounds', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = cardTheme(brightness);
      final cs = theme.colorScheme;
      for (final current in [false, true]) {
        await pumpCard(
          tester,
          const SidebarAppearanceSettings(
            showPreview: true,
            showTimestamp: true,
            showAssistant: true,
            showModel: true,
          ),
          theme: theme,
          current: current,
          selected: true,
          selectionMode: true,
        );
        final title = tester.widget<Text>(find.text('Conversation title'));
        expect(title.style!.color, current ? cs.primary : cs.onSurface);
        final preview = tester.widget<Text>(
          find.text('The latest visible message'),
        );
        expect(preview.style!.color, cs.onSurface.withValues(alpha: 0.62));
        final press = tester.widget<IosCardPress>(find.byType(IosCardPress));
        expect(press.baseColor, cs.primary.withValues(alpha: 0.16));
      }
    }
  });
}
