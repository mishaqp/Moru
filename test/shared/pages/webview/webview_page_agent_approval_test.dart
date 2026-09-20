import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  Widget agentApp(Widget child, {required ToolApprovalService approval}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BrowserAskAiBridge>(
            create: (_) => BrowserAskAiBridge(),
          ),
          ChangeNotifierProvider<ToolApprovalService>.value(value: approval),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );

  testWidgets('the approval card takes over the panel and Deny/Allow call the '
      'right service methods', (tester) async {
    final approval = ToolApprovalService();
    BrowserAgentSession.instance.setOwnerConversationId('conv-1');
    // ignore: unawaited_futures
    approval.requestApproval(
      toolCallId: 'call-1',
      toolName: 'browser_use',
      arguments: {'action': 'click', 'element_id': 2},
      conversationId: 'conv-1',
    );

    await tester.pumpWidget(
      agentApp(
        const WebViewPage(url: 'https://example.com', agentSession: true),
        approval: approval,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('browser_approval_card')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('browser_approval_allow')));
    await tester.pump();

    expect(approval.pendingRequests, isEmpty);
  });
}
