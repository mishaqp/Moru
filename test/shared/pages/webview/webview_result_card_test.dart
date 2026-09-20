import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
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

    expect(find.text('Full long answer text'), findsOneWidget);
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
