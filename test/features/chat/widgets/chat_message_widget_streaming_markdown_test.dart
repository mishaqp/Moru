import "../../../support/business_test_harness.dart";
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/bounded_large_text_view.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/chat/widgets/reasoning_window.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/mermaid_image_cache.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildHarness({required Widget child}) {
  SharedPreferences.setMockInitialValues(const {});
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            TtsProvider(preferences: createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

String _allRichTextPlainText(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((widget) => widget.text.toPlainText())
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reasoning overflow retains the Markdown renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildHarness(
        child: SizedBox(
          width: 360,
          child: ChatMessageWidget(
            message: ChatMessage(
              id: 'reasoning-overflow',
              role: 'assistant',
              content: '',
              conversationId: 'conversation-1',
              isStreaming: true,
            ),
            reasoningText: List.generate(
              80,
              (i) => 'Paragraph $i **bold** 中文。',
            ).join('\n\n'),
            reasoningLoading: true,
            showModelIcon: false,
          ),
        ),
      ),
    );
    final markdown = find.byType(MarkdownWithCodeHighlight);
    expect(markdown, findsOneWidget);
    final first = tester.state(markdown);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // The first layout detects overflow and enables its edge fade next frame.
    await tester.pump();
    expect(tester.state(markdown), same(first));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position,
      same(position),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long reasoning streams only its end and finishes as plain '
      'text', (tester) async {
    // 30 000 characters: line i starts with "L<i> ".
    final text = List.generate(
      1000,
      (i) => 'L${i.toString().padLeft(4, '0')} ${'x' * 23}',
    ).join('\n');
    // In a scrolling list, as in the chat.
    Widget message({required bool loading}) => _buildHarness(
      child: SingleChildScrollView(
        child: ChatMessageWidget(
          message: ChatMessage(
            id: 'long-reasoning',
            role: 'assistant',
            content: '',
            conversationId: 'conversation-1',
            isStreaming: loading,
          ),
          reasoningText: text,
          reasoningLoading: loading,
          reasoningExpanded: true,
          showModelIcon: false,
        ),
      ),
    );

    await tester.pumpWidget(message(loading: true));
    await tester.pump();
    final streamed = _allRichTextPlainText(tester);
    expect(streamed, contains('L0999'));
    expect(streamed, isNot(contains('L0000')));
    expect(find.text('29K'), findsOneWidget);
    expect(find.textContaining('of 29K characters'), findsOneWidget);

    await tester.pumpWidget(message(loading: false));
    await tester.pump();
    expect(find.byType(BoundedLargeTextView), findsOneWidget);
    expect(find.byType(MarkdownWithCodeHighlight), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('the reasoning tail starts at a whole line', () {
    expect(ReasoningWindow.tail('short'), (text: 'short', hidden: 0));
    final text = '${'a' * 50}\nsecond line\n${'b' * 20}';
    final tail = ReasoningWindow.tail(text, max: 33);
    expect(tail.text, 'second line\n${'b' * 20}');
    expect(tail.hidden, 51);
    // Without a line break nearby the cut is exact.
    final flat = 'c' * 1000;
    expect(ReasoningWindow.tail(flat, max: 100).text, 'c' * 100);
    expect(ReasoningWindow.sizeLabel(950), '950');
    expect(ReasoningWindow.sizeLabel(12345), '12K');
  });

  testWidgets('ChatMessageWidget preserves table scroll when streaming ends', (
    tester,
  ) async {
    final streaming = ValueNotifier(true);
    addTearDown(streaming.dispose);
    await tester.pumpWidget(
      _buildHarness(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            child: ValueListenableBuilder<bool>(
              valueListenable: streaming,
              builder: (context, value, _) => ChatMessageWidget(
                message: ChatMessage(
                  id: 'table-scroll',
                  role: 'assistant',
                  content:
                      '| A | B | C | D | E |\n'
                      '| --- | --- | --- | --- | --- |\n'
                      '| apple | banana | cherry | date | elderberry |',
                  conversationId: 'conversation-1',
                  isStreaming: value,
                ),
                enableStreamingTextMotion: true,
                showModelIcon: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final viewport = find.byKey(
      const ValueKey('markdown-table-horizontal-scroll'),
    );
    final scroll = find.descendant(
      of: viewport,
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scroll);
    await tester.drag(viewport, const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 300));
    final offset = state.position.pixels;
    expect(offset, greaterThan(50));

    final gesture = await tester.startGesture(tester.getCenter(viewport));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    final beforeComplete = state.position.pixels;
    streaming.value = false;
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scroll), same(state));
    expect(state.position.pixels, beforeComplete);
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(state.position.pixels, greaterThan(beforeComplete));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'ChatMessageWidget keeps a partial streaming table row in table layout',
    (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          child: ChatMessageWidget(
            message: ChatMessage(
              id: 'streaming-table',
              role: 'assistant',
              content: '''
| 水果 | 颜色 | 价格 |
| - | - | - |
| 葡萄 🍇''',
              conversationId: 'conversation-1',
              isStreaming: true,
            ),
            showModelIcon: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('葡萄 🍇', findRichText: true), findsOneWidget);
      expect(_allRichTextPlainText(tester), isNot(contains('| 葡萄 🍇')));
    },
  );

  testWidgets(
    'ChatMessageWidget keeps unfinished streaming Mermaid in the Mermaid block',
    (tester) async {
      addTearDown(MermaidImageCache.clear);
      MermaidImageCache.clear();

      await tester.pumpWidget(
        _buildHarness(
          child: ChatMessageWidget(
            message: ChatMessage(
              id: 'streaming-mermaid',
              role: 'assistant',
              content: '''
```mermaid
graph TD
A-->B''',
              conversationId: 'conversation-1',
              isStreaming: true,
            ),
            showModelIcon: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Image'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Generating image'), findsOneWidget);
      expect(_allRichTextPlainText(tester), isNot(contains('graph TD')));
    },
  );
}
