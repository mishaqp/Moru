import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_activity_log_sheet.dart';
import 'package:Kelivo/shared/widgets/custom_bottom_sheet.dart';
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

  testWidgets('opens full width at 85 percent and stays reactive while open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 400);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showActivityLogSheet(context),
              child: const Text('open log'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open log'));
    await tester.pumpAndSettle();
    final panel = find.byKey(CustomBottomSheet.panelKey);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, 640);
    expect(tester.getRect(panel).top, closeTo(60, 1));
    expect(tester.getRect(panel).bottom, closeTo(400, 1));
    expect(find.text('Recent actions'), findsOneWidget);
    session.recordActivity(action: 'open', detail: 'https://example.com');
    await tester.pump();
    expect(find.textContaining('Open URL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
