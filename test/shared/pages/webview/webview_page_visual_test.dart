// Visual-review-only snapshots for the browser overhaul (AGENTS.md section
// 12). These assert nothing about pass/fail beyond "it built" -- they exist
// so the PNGs under BROWSER_QA_DIR can be looked at by a human (or another
// agent) reviewing the UI. Pass --dart-define=BROWSER_QA_DIR=/some/path to
// capture; without it, every snapshot() call is a no-op, so this file is
// inert in normal CI runs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/settings/pages/browser_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_activity_log_sheet.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../../support/business_test_harness.dart';
import '../../../support/fake_webview_platform.dart';

void main() {
  setUp(() {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
  });

  Future<void> snapshot(WidgetTester tester, GlobalKey key, String name) async {
    const directory = String.fromEnvironment('BROWSER_QA_DIR');
    if (directory.isEmpty) return;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> setUpDevice(
    WidgetTester tester, {
    required double widthDp,
    required double heightDp,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(widthDp * 2, heightDp * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget app({
    required Brightness brightness,
    required GlobalKey key,
    required BrowserAskAiBridge bridge,
    required ToolApprovalService approval,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BrowserAskAiBridge>.value(value: bridge),
        ChangeNotifierProvider<ToolApprovalService>.value(value: approval),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: brightness, useMaterial3: true),
        home: RepaintBoundary(
          key: key,
          child: const WebViewPage(
            url: 'https://example.com',
            agentSession: true,
          ),
        ),
      ),
    );
  }

  testWidgets('360dp light idle', (tester) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740);
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        brightness: Brightness.light,
        key: key,
        bridge: BrowserAskAiBridge(),
        approval: ToolApprovalService(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await snapshot(tester, key, 'browser-360-light-idle');
  });

  testWidgets('360dp dark running', (tester) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740);
    final key = GlobalKey();
    final bridge = BrowserAskAiBridge();
    await tester.pumpWidget(
      app(
        brightness: Brightness.dark,
        key: key,
        bridge: bridge,
        approval: ToolApprovalService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'find flights to Tokyo');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    BrowserAgentSession.instance.recordActivity(
      action: 'observe',
      detail: null,
    );
    await tester.pump();

    await snapshot(tester, key, 'browser-360-dark-running');
  });

  testWidgets('412dp light approval card', (tester) async {
    await setUpDevice(tester, widthDp: 412, heightDp: 800);
    final key = GlobalKey();
    final approval = ToolApprovalService();
    BrowserAgentSession.instance.setOwnerConversationId('conv-1');
    // ignore: unawaited_futures
    approval.requestApproval(
      toolCallId: 'call-1',
      toolName: 'browser_use',
      arguments: {'action': 'click', 'element_id': 7},
      conversationId: 'conv-1',
    );
    await tester.pumpWidget(
      app(
        brightness: Brightness.light,
        key: key,
        bridge: BrowserAskAiBridge(),
        approval: approval,
      ),
    );
    await tester.pump();
    await tester.pump();

    await snapshot(tester, key, 'browser-412-light-approval');
  });

  testWidgets('412dp light approval card with a long eval_js script', (
    tester,
  ) async {
    await setUpDevice(tester, widthDp: 412, heightDp: 800);
    final key = GlobalKey();
    final approval = ToolApprovalService();
    BrowserAgentSession.instance.setOwnerConversationId('conv-1');
    final longScript = List.generate(
      14,
      (i) => "console.log('step $i: doing something on the page');",
    ).join('\n');
    // ignore: unawaited_futures
    approval.requestApproval(
      toolCallId: 'call-2',
      toolName: 'browser_use',
      arguments: {'action': 'eval_js', 'code': longScript},
      conversationId: 'conv-1',
    );
    await tester.pumpWidget(
      app(
        brightness: Brightness.light,
        key: key,
        bridge: BrowserAskAiBridge(),
        approval: approval,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Prove the whole script is actually present in the tree (not just the
    // first few lines), matching what the screenshot should show inside the
    // scrollable code box.
    expect(find.textContaining('step 13'), findsOneWidget);

    await snapshot(tester, key, 'browser-412-light-approval-evaljs');
  });

  testWidgets('360dp light plain (non-agent) browser page', (tester) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        home: RepaintBoundary(
          key: key,
          child: const WebViewPage(
            url: 'https://example.com',
            // Plain link/browser mode: no Ask-AI composer, no approval bar,
            // no BrowserAgentSession/ToolApprovalService reference at all.
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await snapshot(tester, key, 'browser-360-light-plain');
  });

  testWidgets('360dp light activity log sheet, reactive while open', (
    tester,
  ) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740);
    final key = GlobalKey();
    // The RepaintBoundary must wrap the whole MaterialApp (not just the
    // home route) to capture a modal bottom sheet, which is a sibling
    // OverlayEntry above the home route's content, not a descendant of it.
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(
          brightness: Brightness.light,
          key: GlobalKey(),
          bridge: BrowserAskAiBridge(),
          approval: ToolApprovalService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    BrowserAgentSession.instance.recordActivity(
      action: 'open',
      detail: 'https://example.com',
    );
    final waitForId = BrowserAgentSession.instance.recordActivity(
      action: 'wait_for',
      detail: '.results',
    );
    BrowserAgentSession.instance.resolveActivity(
      waitForId,
      BrowserActivityOutcome.notFound,
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Activity log'));
    await tester.pumpAndSettle();
    // Both activities (including the resolved wait_for -> notFound one)
    // must be visible without closing and reopening the sheet.
    expect(find.byType(ActivityLogSheet), findsOneWidget);

    await snapshot(tester, key, 'browser-360-light-activity-log');
  });

  testWidgets('360dp light browser settings page', (tester) async {
    tester.view.physicalSize = const Size(720, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();

    final settings = SettingsProvider(createBusinessTestPreferences());
    addTearDown(settings.dispose);
    await settings.loaded;
    await settings.setBrowserActionEnabled('eval_js', false);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
          home: RepaintBoundary(key: key, child: const BrowserSettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await snapshot(tester, key, 'browser-360-light-settings');
  });

  testWidgets('360dp light textScale 200% composer with keyboard', (
    tester,
  ) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740, textScale: 2.0);
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        brightness: Brightness.light,
        key: key,
        bridge: BrowserAskAiBridge(),
        approval: ToolApprovalService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.showKeyboard(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pump();

    await snapshot(tester, key, 'browser-360-light-textscale200-keyboard');
  });

  testWidgets('360dp light result card expanded', (tester) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740);
    final key = GlobalKey();
    final bridge = BrowserAskAiBridge();
    // Listen before submitting: bridge.requests is broadcast-only (no
    // replay), so a listener attached after submit() can miss the event.
    final requests = <String>[];
    bridge.requests.listen((r) => requests.add(r.id));
    await tester.pumpWidget(
      app(
        brightness: Brightness.light,
        key: key,
        bridge: bridge,
        approval: ToolApprovalService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'summarize this page');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    final requestId = requests.single;
    bridge.reportOutcome(
      BrowserAskAiOutcome(
        requestId: requestId,
        ok: true,
        answerText:
            'This page is the IANA example domain, reserved for use in '
            'illustrative examples in documents.',
        conversationId: 'conv-1',
        assistantMessageId: 'msg-1',
      ),
    );
    await tester.pump();
    await tester.pump();

    await snapshot(tester, key, 'browser-360-light-result-card');
  });

  testWidgets('360dp light main-frame error', (tester) async {
    await setUpDevice(tester, widthDp: 360, heightDp: 740);
    final key = GlobalKey();
    await tester.pumpWidget(
      app(
        brightness: Brightness.light,
        key: key,
        bridge: BrowserAskAiBridge(),
        approval: ToolApprovalService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    FakeWebViewPlatform.lastCreated!.simulateWebResourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'net::ERR_NAME_NOT_RESOLVED',
        errorType: WebResourceErrorType.hostLookup,
        isForMainFrame: true,
      ),
    );
    await tester.pump();

    await snapshot(tester, key, 'browser-360-light-main-frame-error');
  });
}
