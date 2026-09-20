import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // MarkdownWithCodeHighlight (used by the full-answer sheet) reads
  // SettingsProvider for math/code-font preferences.
  Widget wrap(Widget child) => ChangeNotifierProvider<SettingsProvider>(
    create: (_) => SettingsProvider(createBusinessTestPreferences()),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('shows the answer text', (tester) async {
    await tester.pumpWidget(
      wrap(
        BrowserAskAiResultCard(
          answerText: 'The page is about flights.',
          onExpand: () {},
          onCopy: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.textContaining('The page is about flights.'), findsOneWidget);
  });

  testWidgets('expand opens the full-text sheet', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => BrowserAskAiResultCard(
            answerText: 'Short preview',
            onExpand: () =>
                showBrowserAskAiResultSheet(context, 'Full long answer text'),
            onCopy: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('View full answer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Full long answer text'), findsOneWidget);
  });

  testWidgets('copy action invokes the clipboard', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      wrap(
        BrowserAskAiResultCard(
          answerText: 'Copy me',
          onExpand: () {},
          onCopy: () => Clipboard.setData(const ClipboardData(text: 'Copy me')),
          onDismiss: () {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Copy answer'));
    await tester.pump();

    expect(calls.any((c) => c.method == 'Clipboard.setData'), isTrue);
  });

  testWidgets(
    'the preview shows plain text -- no Markdown markers -- clamped to '
    'three lines',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          BrowserAskAiResultCard(
            answerText: '**Bold** and `code` and\n\n# Heading\n- item',
            onExpand: () {},
            onCopy: () {},
            onDismiss: () {},
          ),
        ),
      );

      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('`'), findsNothing);
      expect(find.textContaining('#'), findsNothing);
      final preview = tester.widget<Text>(
        find.text('Bold and code and\nHeading\nitem'),
      );
      expect(preview.maxLines, 3);
      expect(preview.overflow, TextOverflow.ellipsis);
    },
  );

  testWidgets(
    'the full-answer sheet renders Markdown as formatted text, not the '
    'literal source',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showBrowserAskAiResultSheet(
                context,
                '**bold answer** with `inline code`',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('**bold answer**'), findsNothing);
      expect(find.textContaining('bold answer'), findsOneWidget);
      expect(find.textContaining('inline code'), findsOneWidget);
    },
  );

  testWidgets(
    'the sheet\'s copy button copies the full, unmodified Markdown source',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const source = '**Full** raw *markdown* source, not the preview.';
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showBrowserAskAiResultSheet(context, source),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy answer'));
      await tester.pump();

      final setDataCall = calls.firstWhere(
        (c) => c.method == 'Clipboard.setData',
      );
      expect((setDataCall.arguments as Map)['text'], source);
    },
  );

  testWidgets(
    'a long answer with a code block scrolls inside a bounded sheet instead '
    'of overflowing',
    (tester) async {
      final longCode = List.generate(80, (i) => 'line $i of code').join('\n');
      final longText =
          'Intro paragraph.\n\n```dart\n$longCode\n```\n\nOutro paragraph.';

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showBrowserAskAiResultSheet(context, longText),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      final sheetHeight = tester
          .getRect(
            find.byType(ConstrainedBox).first,
          )
          .height;
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(sheetHeight, lessThanOrEqualTo(screenHeight));
    },
  );

  testWidgets('explicit close removes the card', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => dismissed
              ? const SizedBox.shrink()
              : BrowserAskAiResultCard(
                  answerText: 'Answer',
                  onExpand: () {},
                  onCopy: () {},
                  onDismiss: () => setState(() => dismissed = true),
                ),
        ),
      ),
    );

    expect(find.textContaining('Answer'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss answer'));
    await tester.pump();
    expect(find.textContaining('Answer'), findsNothing);
  });
}
