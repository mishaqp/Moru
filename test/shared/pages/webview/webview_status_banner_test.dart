import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_guard.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = BrowserAgentSession.instance;

  tearDown(() {
    session
      ..challenge.value = null
      ..currentActivity.value = null
      ..endAction();
  });

  Widget wrap({bool showActivity = true}) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: WebViewStatusBanner(showActivity: showActivity)),
  );

  BrowserActivity running() =>
      BrowserActivity(id: '1', action: 'click', startedAt: DateTime(2026));

  testWidgets('shows what the site asks for', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.byKey(WebViewStatusBanner.challengeKey), findsNothing);

    session.challenge.value = const BrowserChallenge(
      kind: 'cloudflare',
      blocking: true,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(WebViewStatusBanner.challengeKey), findsOneWidget);
    expect(find.textContaining('Complete the check yourself'), findsOneWidget);

    session.challenge.value = const BrowserChallenge(
      kind: 'rate_limited',
      blocking: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('limits requests'), findsOneWidget);

    session.challenge.value = null;
    await tester.pumpAndSettle();
    expect(find.byKey(WebViewStatusBanner.challengeKey), findsNothing);
  });

  testWidgets('shows the running action with a Stop that stops it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    session
      ..beginAction()
      ..currentActivity.value = running();
    // The strip grows in; the dot pulses forever, so no pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(WebViewStatusBanner.activityKey), findsOneWidget);

    await tester.tap(find.byKey(WebViewStatusBanner.stopKey));
    expect(session.stopRequested, isTrue);

    session.currentActivity.value = null;
    await tester.pumpAndSettle();
    expect(find.byKey(WebViewStatusBanner.activityKey), findsNothing);
  });

  testWidgets('leaves the action to the Ask-AI panel when it shows it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(showActivity: false));
    session.currentActivity.value = running();
    await tester.pumpAndSettle();
    expect(find.byKey(WebViewStatusBanner.activityKey), findsNothing);
  });
}
