import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_library.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/webview_console.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../../support/fake_webview_platform.dart';

void main() {
  const normalUrl = 'https://normal.example/page?stateful=true#section-2';
  const privateValue = 'private-authentication-test-value';
  const queryUrl = 'https://login.example/callback?state=$privateValue';
  final originalLibrary = BrowserLibrary.instance;
  final originalOnVisit = BrowserAgentSession.instance.onVisit;
  final visits = <({String url, String? title})>[];
  late BrowserLibrary library;
  late Directory directory;

  setUp(() async {
    installFakeWebViewPlatform();
    BrowserAgentSession.instance.currentActivity.value = null;
    BrowserAgentSession.instance.recentActivityNotifier.value = const [];
    visits.clear();
    BrowserAgentSession.instance.onVisit = (url, title) {
      visits.add((url: url, title: title));
    };
    directory = await Directory.systemTemp.createTemp('browser-console-auth-');
    library = BrowserLibrary(directory: () async => directory);
    BrowserLibrary.instance = library;
    await library.load();
  });

  tearDown(() async {
    BrowserLibrary.instance = originalLibrary;
    BrowserAgentSession.instance.onVisit = originalOnVisit;
    await directory.delete(recursive: true);
  });

  Future<void> saveVisits(WidgetTester tester) async {
    final recorded = List.of(visits);
    visits.clear();
    await tester.runAsync(() async {
      for (final visit in recorded) {
        await library.recordVisit(visit.url, visit.title);
      }
    });
  }

  Future<FakeWebViewController> openBrowser(
    WidgetTester tester, {
    bool agentSession = true,
  }) async {
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WebViewPage(url: normalUrl, agentSession: agentSession),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    if (agentSession) {
      // Start and await all history IO outside the widget's fake event loop.
      await saveVisits(tester);
    }
    return FakeWebViewPlatform.lastCreated!;
  }

  Future<List<ConsoleMessage>> retainedConsole(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Console Logs'));
    await tester.pumpAndSettle();
    return tester.widget<ConsoleSheet>(find.byType(ConsoleSheet)).messages;
  }

  final destinations = <String, String>{
    'authorization query': queryUrl,
    'fragment route callback':
        'https://login.example/#/callback?code=$privateValue',
    'Codex device endpoint': 'https://auth.openai.com/codex/device',
  };
  for (final destination in destinations.entries) {
    testWidgets(
      '${destination.key} reached after navigation is filtered before console retention',
      (tester) async {
        final controller = await openBrowser(tester);
        // Simulate a redirect/click without passing its URL to browser_use.
        await controller.loadRequest(
          LoadRequestParams(uri: Uri.parse(destination.value)),
        );
        await tester.pump();
        await saveVisits(tester);
        controller.simulateWebResourceError(
          WebResourceError(
            errorCode: -6,
            description: 'Failed to load ${destination.value}',
            isForMainFrame: false,
          ),
        );
        await tester.pump();

        final messages = await retainedConsole(tester);

        expect(messages, hasLength(1));
        expect(messages.single.source, '[REDACTED]');
        expect(
          messages.single.message,
          contains('Web error -6: Failed to load'),
        );
        expect(messages.single.message, contains('[REDACTED]'));
        expect(messages.single.message, isNot(contains(destination.value)));
        expect(messages.single.message, isNot(contains(privateValue)));
        expect(controller.currentUrlSync, destination.value);
        expect(library.history.value.map((entry) => entry.url), [normalUrl]);
      },
    );
  }

  for (final agentSession in [true, false]) {
    testWidgets('JavaScript auth links are filtered before retention in '
        '${agentSession ? 'the agent' : 'the ordinary'} browser', (
      tester,
    ) async {
      final controller = await openBrowser(tester, agentSession: agentSession);
      controller.emitChannelMessage(
        'Console',
        jsonEncode({
          'level': 'warn',
          'message': 'Sign in at $queryUrl and continue loading.',
          'source': 'https://login.example/#refresh_token=$privateValue',
          'line': 42,
        }),
      );
      await tester.pump();

      final message = (await retainedConsole(tester)).single;

      expect(message.level, 'WARN');
      expect(message.message, 'Sign in at [REDACTED] and continue loading.');
      expect(message.source, '[REDACTED]');
      expect(message.line, 42);
    });
  }

  testWidgets('raw JavaScript channel messages also filter auth links', (
    tester,
  ) async {
    final controller = await openBrowser(tester);
    controller.emitChannelMessage('Console', 'Redirect $queryUrl\nReady.');
    await tester.pump();

    final message = (await retainedConsole(tester)).single;

    expect(message.message, 'Redirect [REDACTED]\nReady.');
    expect(message.source, isNull);
  });

  testWidgets('console level text cannot retain an authentication URL', (
    tester,
  ) async {
    final controller = await openBrowser(tester);
    controller.emitChannelMessage(
      'Console',
      jsonEncode({'level': 'warn $queryUrl', 'message': 'Ready.'}),
    );
    await tester.pump();

    final message = (await retainedConsole(tester)).single;

    expect(message.level, 'WARN [REDACTED]');
    expect(message.message, 'Ready.');
  });

  testWidgets(
    'ordinary console messages, source URLs and lines are unchanged',
    (tester) async {
      final controller = await openBrowser(tester);
      const text =
          'Image failed https://normal.example/icon.png?size=32#loaded';
      const source = 'https://normal.example/app.js?v=7#main';
      controller.emitChannelMessage(
        'Console',
        jsonEncode({
          'level': 'warn',
          'message': text,
          'source': source,
          'line': 99,
        }),
      );
      await tester.pump();

      final message = (await retainedConsole(tester)).single;

      expect(message.level, 'WARN');
      expect(message.message, text);
      expect(message.source, source);
      expect(message.line, 99);
    },
  );
}
