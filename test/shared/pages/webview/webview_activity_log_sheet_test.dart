import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_activity_log_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = BrowserAgentSession.instance;

  setUp(() {
    session.currentActivity.value = null;
    session.recentActivityNotifier.value = const [];
  });

  Widget wrap() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: ActivityLogSheet()),
  );

  testWidgets('shows an empty state with no activity', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('No activity yet'), findsOneWidget);
  });

  testWidgets('is reactive while open: recording two activities with the sheet '
      'already open shows both without closing it', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('No activity yet'), findsOneWidget);

    session.recordActivity(action: 'open', detail: 'https://example.com');
    await tester.pump();
    expect(find.textContaining('Open URL'), findsOneWidget);

    session.recordActivity(action: 'click', detail: null);
    await tester.pump();
    expect(find.textContaining('Open URL'), findsOneWidget);
    expect(find.textContaining('Click'), findsOneWidget);
  });

  testWidgets(
    'running/ok/failed/notFound render with visually distinct markers',
    (tester) async {
      final runningId = session.recordActivity(action: 'observe');
      final okId = session.recordActivity(action: 'click');
      final failedId = session.recordActivity(action: 'submit');
      final notFoundId = session.recordActivity(
        action: 'wait_for',
        detail: '.thing',
      );
      session.resolveActivity(okId, BrowserActivityOutcome.ok);
      session.resolveActivity(failedId, BrowserActivityOutcome.failed);
      session.resolveActivity(notFoundId, BrowserActivityOutcome.notFound);
      expect(runningId, isNotEmpty);

      await tester.pumpWidget(wrap());

      // Each row shows a distinct outcome icon (see _ActivityRow's switch)
      // plus the text-level marker already covered by
      // browser_agent_actions_test.dart.
      expect(find.byType(Icon), findsNWidgets(4));
      expect(find.textContaining('failed'), findsOneWidget);
      expect(find.textContaining('not found'), findsOneWidget);
    },
  );

  testWidgets(
    'no secret-shaped value appears in the visible summary (a long eval_js '
    'code string is never echoed in the log)',
    (tester) async {
      final longCode = 'x' * 500;
      session.recordActivity(action: 'eval_js', detail: null);
      await tester.pumpWidget(wrap());

      expect(find.textContaining(longCode), findsNothing);
    },
  );
}
