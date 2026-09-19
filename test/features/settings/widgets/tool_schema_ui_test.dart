import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/settings/widgets/tool_schema_ui.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  Widget buildHarness({
    required Locale locale,
    required ValueChanged<bool> onResult,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final confirmed = await confirmFullToolTrust(context);
            onResult(confirmed);
          },
          child: const Text('trigger'),
        ),
      ),
    );
  }

  testWidgets(
    'cancelling the full-trust dialog does not confirm and shows the risk text',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        buildHarness(
          locale: const Locale('en'),
          onResult: (value) => result = value,
        ),
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Full tool trust'), findsOneWidget);
      expect(
        find.text(
          'Moru will stop asking for confirmation before tool actions. '
          'The AI may click and type in the browser, run shell commands, '
          'modify files, and use other enabled tools automatically. '
          'This does not bypass Android system permissions.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('Full tool trust'), findsNothing);
    },
  );

  testWidgets('acknowledging the risk in the full-trust dialog confirms it', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      buildHarness(
        locale: const Locale('en'),
        onResult: (value) => result = value,
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I understand — allow everything'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('shows the Russian risk explanation under a Russian locale', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      buildHarness(
        locale: const Locale('ru'),
        onResult: (value) => result = value,
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Полное доверие инструментам'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
