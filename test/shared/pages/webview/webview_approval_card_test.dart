import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_approval_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ToolApprovalService service;

  setUp(() {
    service = ToolApprovalService();
  });

  ToolApprovalRequest requestFor(Map<String, dynamic> arguments) {
    // Fire-and-forget: requestApproval() only completes once approved or
    // denied, which is exactly what these tests exercise.
    // ignore: unawaited_futures
    service.requestApproval(
      toolCallId: 'call-1',
      toolName: 'browser_use',
      arguments: arguments,
      conversationId: 'conv-1',
    );
    return service.pendingRequests.single;
  }

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('Allow calls approve with the right toolCallId/conversationId', (
    tester,
  ) async {
    final request = requestFor({'action': 'click', 'element_id': 3});
    await tester.pumpWidget(
      wrap(
        BrowserApprovalCard(
          request: request,
          siteUrl: 'https://example.com/page',
          ru: false,
          onApprove: () => service.approve(
            request.toolCallId,
            conversationId: request.conversationId,
          ),
          onDeny: () => service.deny(
            request.toolCallId,
            conversationId: request.conversationId,
          ),
          onChangeTrustSettings: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('browser_approval_allow')));
    await tester.pump();

    final result = await request.future;
    expect(result.approved, isTrue);
    expect(service.pendingRequests, isEmpty);
  });

  testWidgets('Deny calls deny with the right toolCallId/conversationId', (
    tester,
  ) async {
    final request = requestFor({'action': 'type', 'element_id': 5});
    await tester.pumpWidget(
      wrap(
        BrowserApprovalCard(
          request: request,
          siteUrl: 'https://example.com',
          ru: false,
          onApprove: () => service.approve(
            request.toolCallId,
            conversationId: request.conversationId,
          ),
          onDeny: () => service.deny(
            request.toolCallId,
            conversationId: request.conversationId,
          ),
          onChangeTrustSettings: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('browser_approval_deny')));
    await tester.pump();

    final result = await request.future;
    expect(result.approved, isFalse);
  });

  testWidgets('"Always allow" is gone from this card', (tester) async {
    final request = requestFor({'action': 'click', 'element_id': 1});
    await tester.pumpWidget(
      wrap(
        BrowserApprovalCard(
          request: request,
          siteUrl: 'https://example.com',
          ru: false,
          onApprove: () {},
          onDeny: () {},
          onChangeTrustSettings: () {},
        ),
      ),
    );

    expect(find.text('Always allow'), findsNothing);
    expect(find.textContaining('Always'), findsNothing);
  });

  testWidgets(
    'the trust-settings link navigates without itself flipping the toggle',
    (tester) async {
      final request = requestFor({'action': 'click', 'element_id': 1});
      var navigated = false;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => BrowserApprovalCard(
              request: request,
              siteUrl: 'https://example.com',
              ru: false,
              onApprove: () {},
              onDeny: () {},
              onChangeTrustSettings: () {
                navigated = true;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('TRUST PAGE')),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('browser_approval_change_trust')),
      );
      await tester.pumpAndSettle();

      expect(navigated, isTrue);
      expect(find.text('TRUST PAGE'), findsOneWidget);
    },
  );

  testWidgets('an eval_js approval with a long script renders all of it '
      'inside a scrollable ancestor', (tester) async {
    final lines = List.generate(30, (i) => 'console.log("line $i");');
    final code = lines.join('\n');
    final request = requestFor({'action': 'eval_js', 'code': code});

    await tester.pumpWidget(
      wrap(
        BrowserApprovalCard(
          request: request,
          siteUrl: 'https://example.com',
          ru: false,
          onApprove: () {},
          onDeny: () {},
          onChangeTrustSettings: () {},
        ),
      ),
    );

    final distinguishing = find.textContaining('line 29');
    expect(distinguishing, findsOneWidget);
    expect(
      find.ancestor(
        of: distinguishing,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    // Not clipped/ellipsized.
    final textWidget = tester.widget<Text>(
      find.descendant(
        of: find.ancestor(
          of: distinguishing,
          matching: find.byType(SingleChildScrollView),
        ),
        matching: find.byType(Text),
      ),
    );
    expect(textWidget.maxLines, isNull);
    expect(textWidget.data, contains('line 0'));
    expect(textWidget.data, contains('line 29'));
  });

  testWidgets('shows the action, site, and element id', (tester) async {
    final request = requestFor({'action': 'click', 'element_id': 42});
    await tester.pumpWidget(
      wrap(
        BrowserApprovalCard(
          request: request,
          siteUrl: 'https://example.com/some/page',
          ru: false,
          onApprove: () {},
          onDeny: () {},
          onChangeTrustSettings: () {},
        ),
      ),
    );

    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.textContaining('Click'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
  });
}
