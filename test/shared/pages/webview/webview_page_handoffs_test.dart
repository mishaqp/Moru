import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_handoffs.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/shared/pages/webview/webview_error_view.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> opened;
  late Map<String, Object?> reply;

  setUp(() {
    installFakeWebViewPlatform();
    BrowserHandoffs.instance.drainForModel();
    opened = [];
    reply = {'opened': true};
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openExternal') {
        opened.add((call.arguments as Map)['url'] as String);
        return reply;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    BrowserAgentSession.instance.currentActivity.value = null;
  });

  Widget app(Widget page) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  );

  WebResourceError appLinkError(String url) => WebResourceError(
    errorCode: -10,
    description: 'net::ERR_UNKNOWN_URL_SCHEME',
    errorType: WebResourceErrorType.unsupportedScheme,
    isForMainFrame: true,
    url: url,
  );

  test('only non-web schemes are app links', () {
    expect(BrowserHandoffs.isAppLink('tel:+123'), isTrue);
    expect(BrowserHandoffs.isAppLink('intent://x#Intent;end'), isTrue);
    expect(BrowserHandoffs.isAppLink('https://example.com'), isFalse);
    expect(BrowserHandoffs.isAppLink('about:blank'), isFalse);
    expect(BrowserHandoffs.isAppLink('blob:https://a/b'), isFalse);
    expect(BrowserHandoffs.isAppLink(null), isFalse);
  });

  test('downloads reach the page and the model once', () async {
    await BrowserHandoffs.instance.handleNativeCall(
      const MethodCall('download', {
        'file': 'report.pdf',
        'path': '/storage/emulated/0/Download/report.pdf',
        'url': 'https://example.com/report',
      }),
    );
    expect(BrowserHandoffs.instance.latestDownload.value?.file, 'report.pdf');
    expect(BrowserHandoffs.instance.drainForModel(), [
      {
        'kind': 'download',
        'file': 'report.pdf',
        'path': '/storage/emulated/0/Download/report.pdf',
        'status': 'downloading',
      },
    ]);
    expect(BrowserHandoffs.instance.drainForModel(), isEmpty);
  });

  testWidgets('an app link the user taps opens its app instead of an error '
      'page', (tester) async {
    await tester.pumpWidget(
      app(const WebViewPage(url: 'https://shop.example')),
    );
    await tester.pump();
    FakeWebViewPlatform.lastCreated!.simulateWebResourceError(
      appLinkError('tel:+123'),
    );
    await tester.pumpAndSettle();
    expect(opened, ['tel:+123']);
    expect(find.byType(WebViewErrorView), findsNothing);
  });

  testWidgets('without an app, the link\'s web fallback loads', (tester) async {
    reply = {'opened': false, 'fallback': 'https://shop.example/app'};
    await tester.pumpWidget(
      app(const WebViewPage(url: 'https://shop.example')),
    );
    await tester.pump();
    final fake = FakeWebViewPlatform.lastCreated!;
    fake.simulateWebResourceError(
      appLinkError('intent://x#Intent;scheme=shop;end'),
    );
    await tester.pumpAndSettle();
    expect(await fake.currentUrl(), 'https://shop.example/app');
  });

  testWidgets('while the assistant drives the page no app opens; the model '
      'is told', (tester) async {
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
        child: app(
          const WebViewPage(url: 'https://shop.example', agentSession: true),
        ),
      ),
    );
    await tester.pump();
    BrowserAgentSession.instance.currentActivity.value = BrowserActivity(
      id: 'c',
      action: 'click',
      startedAt: DateTime(2026),
    );
    FakeWebViewPlatform.lastCreated!.simulateWebResourceError(
      appLinkError('market://details?id=x'),
    );
    await tester.pump();
    await tester.pump();
    expect(opened, isEmpty);
    expect(BrowserHandoffs.instance.drainForModel(), [
      {
        'kind': 'app_link',
        'url': 'market://details?id=x',
        'status': 'not_opened_while_assistant_works',
      },
    ]);
  });
}
