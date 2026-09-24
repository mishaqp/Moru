import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/chat/widgets/token_display_widget.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('compact numbers', () {
    expect(TokenStatsRow.compact(537), '537');
    expect(TokenStatsRow.compact(1000), '1k');
    expect(TokenStatsRow.compact(1234), '1.2k');
    expect(TokenStatsRow.compact(18450), '18.4k');
    expect(TokenStatsRow.compact(128000), '128k');
    expect(TokenStatsRow.compact(1250000), '1.3M');
  });

  testWidgets('shows every figure inline without a popup', (tester) async {
    await tester.pumpWidget(
      _host(
        const TokenStatsRow(
          totalTokens: 18987,
          promptTokens: 18450,
          completionTokens: 537,
          cachedTokens: 18176,
          durationMs: 2100,
        ),
      ),
    );

    expect(find.text('18.4k'), findsOneWidget);
    expect(find.text('18.2k'), findsOneWidget);
    expect(find.text('537'), findsOneWidget);
    expect(find.textContaining('255.7'), findsOneWidget);
    expect(find.textContaining('2.1'), findsOneWidget);
    // The full numbers stay available to screen readers.
    expect(
      tester.getSemantics(find.byType(TokenStatsRow)).label,
      allOf(contains('18450'), contains('18176'), contains('537')),
    );
  });

  testWidgets('falls back to the total when details are missing', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const TokenStatsRow(totalTokens: 4200)));
    expect(find.text('4.2k'), findsOneWidget);
  });
}
