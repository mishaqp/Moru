import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/widgets/context_usage_ring.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  Future<void> pump(WidgetTester tester, ContextUsageRing ring) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: ring)),
        ),
      );

  test('fill is used over window, unknown without a window', () {
    expect(
      const ContextUsageRing(usedTokens: 50000, windowTokens: 200000).ratio,
      0.25,
    );
    expect(
      const ContextUsageRing(usedTokens: 50000, windowTokens: null).ratio,
      isNull,
    );
  });

  testWidgets('tapping the ring shows the numbers', (tester) async {
    await pump(
      tester,
      const ContextUsageRing(usedTokens: 45200, windowTokens: 200000),
    );
    await tester.tap(find.byType(ContextUsageRing));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Context: 45.2k of 200k tokens (23%)'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('without a window the tip asks to set it', (tester) async {
    await pump(
      tester,
      const ContextUsageRing(usedTokens: 800, windowTokens: null),
    );
    await tester.tap(find.byType(ContextUsageRing));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Context: 800 tokens.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
