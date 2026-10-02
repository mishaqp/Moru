import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

TextStyle? _styleFor(InlineSpan span, String text, [TextStyle? parent]) {
  if (span is! TextSpan) return null;
  final style = parent?.merge(span.style) ?? span.style;
  if (span.text?.contains(text) ?? false) return style;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final found = _styleFor(child, text, style);
    if (found != null) return found;
  }
  return null;
}

void main() {
  for (final markdown in [
    '1. Начало пункта\n   продолжение пункта\n2. Следующий пункт',
    '- Начало пункта\n  продолжение пункта\n- Следующий пункт',
    '1. Родитель\n   - Начало пункта\n     продолжение пункта\n2. Следующий пункт',
    '- Родитель\n  1. Начало пункта\n     продолжение пункта\n- Следующий пункт',
    '-   Начало пункта\n    продолжение пункта\n- Следующий пункт',
    '1.   Начало пункта\n     продолжение пункта\n2. Следующий пункт',
    '- Начало пункта\n    продолжение пункта\n- Следующий пункт',
    '1. Начало пункта\n     продолжение пункта\n2. Следующий пункт',
    '- Начало пункта\n\tпродолжение пункта\n- Следующий пункт',
    '1. Начало пункта\n\tпродолжение пункта\n2. Следующий пункт',
  ]) {
    for (final scale in [0.8, 1.0, 1.4]) {
      testWidgets(
        'list continuation stays in its paragraph at $scale: $markdown',
        (tester) async {
          await tester.pumpWidget(
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(createBusinessTestPreferences()),
              child: MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: MarkdownWithCodeHighlight(
                      text: markdown,
                      baseStyle: const TextStyle(fontSize: 19, height: 1.6),
                    ),
                  ),
                ),
              ),
            ),
          );
          final paragraphs = tester.widgetList<RichText>(find.byType(RichText));
          final paragraph = paragraphs.firstWhere(
            (p) => p.text.toPlainText().contains('Начало пункта'),
          );
          expect(paragraph.text.toPlainText(), contains('продолжение пункта'));
          expect(
            _styleFor(paragraph.text, 'продолжение пункта'),
            _styleFor(paragraph.text, 'Начало пункта'),
          );
          expect(_styleFor(paragraph.text, 'Начало пункта')?.fontSize, 19);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('nested list scaling stays stable after a streaming append', (
    tester,
  ) async {
    final source = ValueNotifier(
      '1. Родитель\n   - Начало пункта\n     продолжение пункта',
    );
    addTearDown(source.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: source,
                builder: (_, text, _) =>
                    MarkdownWithCodeHighlight(text: text, streaming: true),
              ),
            ),
          ),
        ),
      ),
    );
    RichText paragraph() => tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().contains('Начало пункта'));
    final before = paragraph().textScaler.scale(19);
    source.value += ' — ещё текст';
    await tester.pump();
    expect(paragraph().textScaler.scale(19), before);
    expect(paragraph().text.toPlainText(), contains('продолжение пункта'));
  });

  testWidgets('gpt_markdown keeps emphasis and code in a continued item', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GptMarkdown(
            '1. Начало **жирный текст** и `код`\n   продолжение\n2. Конец',
            style: TextStyle(fontSize: 19),
          ),
        ),
      ),
    );
    final paragraph = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().contains('Начало'));
    expect(paragraph.text.toPlainText(), contains('продолжение'));
    expect(
      _styleFor(paragraph.text, 'жирный текст')?.fontWeight,
      FontWeight.bold,
    );
    expect(_styleFor(paragraph.text, 'код')?.fontSize, 19);
  });
}
