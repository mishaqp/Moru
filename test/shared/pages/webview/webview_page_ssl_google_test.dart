import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_guard.dart';
import 'package:Kelivo/core/services/browser/browser_handoffs.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/pages/webview/webview_status_banner.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart' show rootNavigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  final session = BrowserAgentSession.instance;

  setUp(() {
    installFakeWebViewPlatform();
    BrowserHandoffs.instance.drainForModel();
  });

  tearDown(() => session.currentActivity.value = null);

  Future<FakeWebViewController> openBrowser(
    WidgetTester tester,
    String url,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BrowserAskAiBridge>(
            create: (_) => BrowserAskAiBridge(),
          ),
          ChangeNotifierProvider<ToolApprovalService>(
            create: (_) => ToolApprovalService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          navigatorKey: rootNavigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('chat')),
        ),
      ),
    );
    rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => WebViewPage(url: url, agentSession: true),
      ),
    );
    await tester.pumpAndSettle();
    return FakeWebViewPlatform.lastCreated!;
  }

  test('Google sign-in pages are recognised by address', () {
    expect(
      BrowserGuard.isGoogleSignIn(
        'https://accounts.google.com/v3/signin/identifier?continue=x',
      ),
      isTrue,
    );
    expect(
      BrowserGuard.isGoogleSignIn('https://accounts.google.com/o/oauth2/auth'),
      isTrue,
    );
    expect(BrowserGuard.isGoogleSignIn('https://accounts.google.com/'), false);
    expect(BrowserGuard.isGoogleSignIn('https://google.com/signin'), false);
    expect(
      BrowserGuard.classify(
        url: 'https://accounts.google.com/ServiceLogin',
      )?.toJson()['kind'],
      'google_sign_in',
    );
  });

  testWidgets('a Google sign-in page shows why it cannot go on, with Open '
      'in Chrome', (tester) async {
    await openBrowser(
      tester,
      'https://accounts.google.com/v3/signin/identifier?continue=x',
    );
    expect(find.byKey(WebViewStatusBanner.challengeKey), findsOneWidget);
    expect(find.textContaining('Google does not allow'), findsOneWidget);
    expect(find.byKey(WebViewStatusBanner.openInChromeKey), findsOneWidget);
    expect(session.challenge.value?.blocking, isFalse);
  });

  testWidgets('the user decides about an invalid certificate while looking; '
      'a yes is remembered for the site', (tester) async {
    final fake = await openBrowser(tester, 'https://self-signed.example/');
    final first = FakeSslAuthError();
    fake.simulateSslError(first);
    await tester.pumpAndSettle();
    expect(find.text('Connection is not secure'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(await first.answer.future, 'proceed');

    final again = FakeSslAuthError();
    fake.simulateSslError(again);
    await tester.pumpAndSettle();
    expect(find.text('Connection is not secure'), findsNothing);
    expect(await again.answer.future, 'proceed');
  });

  testWidgets('while the model drives the page an invalid certificate is '
      'refused and the model is told', (tester) async {
    final fake = await openBrowser(tester, 'https://bad-cert.example/');
    session.currentActivity.value = BrowserActivity(
      id: 'o',
      action: 'open',
      startedAt: DateTime(2026),
    );
    final error = FakeSslAuthError();
    fake.simulateSslError(error);
    await tester.pump();
    expect(await error.answer.future, 'cancel');
    expect(find.text('Connection is not secure'), findsNothing);
    final notes = BrowserHandoffs.instance.drainForModel();
    expect(notes.single['kind'], 'ssl_error');
    expect(notes.single['site'], 'bad-cert.example');
  });

  testWidgets('a refused certificate leaves the page that was shown: no '
      'stuck progress, no visit, the wait ends', (tester) async {
    final fake = await openBrowser(tester, 'https://ok.example/');
    final visits = <String>[];
    final original = session.onVisit;
    session.onVisit = (url, _) => visits.add(url);
    addTearDown(() => session.onVisit = original);
    session.currentActivity.value = BrowserActivity(
      id: 'o',
      action: 'open',
      startedAt: DateTime(2026),
    );

    fake.autoFinish = false;
    final opened = session.load(Uri.parse('https://bad-cert.example/'));
    fake.startNext();
    fake.simulateProgress(10);
    final error = FakeSslAuthError();
    fake.simulateSslError(error);
    await tester.pump();
    expect(await error.answer.future, 'cancel');
    // Chromium may still report the refused load's end afterwards.
    fake.simulateProgress(10);
    fake.finishNext();
    await tester.pump();
    await opened;

    expect(
      find.byKey(const ValueKey('browser_address_progress')),
      findsNothing,
    );
    expect(find.textContaining('bad-cert.example'), findsNothing);
    expect(session.pageUrl.value, 'https://ok.example/');
    expect(session.pageLoading.value, isFalse);
    expect(visits, isEmpty);
  });
}
