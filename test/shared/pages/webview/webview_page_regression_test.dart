import 'dart:convert';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_bottom_panel.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_webview_platform.dart';

/// Regression coverage for the two pre-existing modes: HTML preview and a
/// plain (`agentSession: false`) link/browser page. Split into its own file
/// (see webview_page_agent_session_test.dart for why) so each test gets a
/// clean process.
void main() {
  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  Widget plainApp(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets(
    'HTML preview mode has no address/nav row and loads its base64 HTML',
    (tester) async {
      const html = '<html><body>Hi there</body></html>';
      final b64 = base64Encode(utf8.encode(html));

      await tester.pumpWidget(plainApp(WebViewPage(contentBase64: b64)));
      await tester.pump();
      await tester.pump();

      expect(find.byType(WebViewBottomPanel), findsNothing);
      expect(find.byType(WebViewNavRow), findsNothing);
      expect(FakeWebViewPlatform.lastCreated?.lastLoadedHtml, html);
    },
  );

  testWidgets(
    'a plain (agentSession: false) link page opens, navigates, has a nav '
    'row but no Ask-AI panel, and builds without any agent-only provider '
    'in the tree',
    (tester) async {
      // Deliberately no BrowserAskAiBridge/ToolApprovalService provided --
      // if the plain page referenced either, this would throw a
      // ProviderNotFoundException during build.
      await tester.pumpWidget(
        plainApp(const WebViewPage(url: 'https://example.com')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(WebViewBottomPanel), findsNothing);
      expect(find.byType(WebViewNavRow), findsOneWidget);
      expect(
        FakeWebViewPlatform.lastCreated?.currentUrlSync,
        'https://example.com',
      );
    },
  );
}
