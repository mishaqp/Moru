import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/browser/browser_agent_session.dart';
import 'package:Kelivo/core/services/browser/browser_handoffs.dart';
import 'package:Kelivo/core/services/browser/browser_http_auth.dart';
import 'package:Kelivo/features/home/services/browser_ask_ai_bridge.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/home/widgets/chat_header_switcher.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/pages/webview/browser_mini_window.dart';
import 'package:Kelivo/shared/pages/webview/webview_page.dart';
import 'package:Kelivo/shared/pages/webview/webview_status_banner.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart' show rootNavigatorKey;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../support/fake_webview_platform.dart';

const _minimize = ValueKey('browser_minimize');

void main() {
  late int chatTaps;

  setUp(() {
    installFakeWebViewPlatform();
    chatTaps = 0;
  });

  tearDown(() async {
    FakeWebViewPlatform.onCreated = null;
    final session = BrowserAgentSession.instance;
    if (session.minimized.value) await session.closeMinimized();
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrowserAskAiBridge>(
        create: (_) => BrowserAskAiBridge(),
      ),
      ChangeNotifierProvider<ToolApprovalService>(
        create: (_) => ToolApprovalService(),
      ),
    ],
    child: MaterialApp(
      navigatorKey: rootNavigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => Overlay.wrap(
        child: Stack(children: [child!, const BrowserMiniWindow()]),
      ),
      home: Scaffold(
        appBar: AppBar(actions: const [ChatHeaderSwitcher()]),
        body: Align(
          alignment: Alignment.topLeft,
          child: TextButton(
            onPressed: () => chatTaps++,
            child: const Text('chat'),
          ),
        ),
      ),
    ),
  );

  Future<void> openBrowser(WidgetTester tester) async {
    await tester.tap(find.byKey(ChatHeaderSwitcher.browserKey));
    await tester.pumpAndSettle();
    expect(find.byType(WebViewPage), findsOneWidget);
  }

  for (final state in ['first', 'attached', 'minimized', 'reopened']) {
    testWidgets('authenticated agent opens a fresh controller when $state', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      final session = BrowserAgentSession.instance;
      FakeWebViewController? previous;
      if (state != 'first') {
        await openBrowser(tester);
        previous = session.controller!.platform as FakeWebViewController;
        if (state == 'minimized') {
          await tester.tap(find.byKey(_minimize));
          await tester.pumpAndSettle();
        } else if (state == 'reopened') {
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
        }
      }
      final created = <FakeWebViewController>[];
      Object? loadFailure;
      StackTrace? loadFailureStack;
      FakeWebViewPlatform.onCreated = (fake) {
        created.add(fake);
        fake.autoFinish = false;
        fake.onLoadRequest = (request) async {
          try {
            fake.startNext();
            if (request.uri.path == '/session') {
              expectSync(fake.javaScriptMode, JavaScriptMode.disabled);
              expectSync(fake.javaScriptChannels, isEmpty);
              expectSync(session.controller?.platform, isNot(same(fake)));
              fake.simulateHttpAuthRequest(
                HttpAuthRequest(
                  host: '127.0.0.1',
                  realm: 'Secure Area',
                  onProceed: (credential) {
                    expectSync(credential.user, 'opencode');
                    expectSync(
                      credential.password,
                      'test-secret-never-a-url-or-script',
                    );
                  },
                  onCancel: () => fail('expected sole trusted challenge'),
                ),
              );
            } else {
              expectSync(request.uri.toString(), 'http://127.0.0.1:4321/');
              expectSync(fake.javaScriptMode, JavaScriptMode.unrestricted);
              expectSync(fake.javaScriptChannels, ['Console']);
            }
            fake.finishNext();
          } catch (error, stack) {
            loadFailure = error;
            loadFailureStack = stack;
            rethrow;
          }
        };
      };
      Object? openingFailure;
      final opening =
          openSharedBrowser(
            startUrl: 'http://127.0.0.1:4321/',
            authentication: BrowserHttpAuth(
              origin: Uri.parse('http://127.0.0.1:4321/'),
              username: 'opencode',
              password: 'test-secret-never-a-url-or-script',
            ),
            newTab: true,
          ).catchError((Object error) {
            openingFailure = error;
          });
      await tester.pumpAndSettle();
      await opening;
      if (loadFailure != null) {
        Error.throwWithStackTrace(loadFailure!, loadFailureStack!);
      }
      expect(openingFailure, isNull);
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
      final active = session.controller!.platform as FakeWebViewController;
      expect(active, same(created.single));
      expect(active, isNot(same(previous)));
      expect(active.loadedUrls, [
        'http://127.0.0.1:4321/session',
        'http://127.0.0.1:4321/',
      ]);
      expect(session.pageUrl.value, 'http://127.0.0.1:4321/');
      var cancelled = false;
      active.simulateHttpAuthRequest(
        HttpAuthRequest(
          host: '127.0.0.1',
          realm: 'Secure Area',
          onProceed: (_) => fail('ordinary browser received credentials'),
          onCancel: () => cancelled = true,
        ),
      );
      expect(cancelled, isTrue);
      FakeWebViewPlatform.onCreated = null;
      // Close the old tab through the session while the tree is unlocked;
      // the fake reports native background navigation synchronously.
      for (final tab
          in session.tabs.value.where((tab) => !tab.active).toList()) {
        await session.closeTab(tab.id);
      }
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });
  }

  for (final state in ['attached', 'minimized']) {
    testWidgets(
      'full $state tab list rejects and retires an authenticated controller',
      (tester) async {
        await tester.pumpWidget(app());
        await openBrowser(tester);
        final session = BrowserAgentSession.instance;
        for (var i = 1; i < BrowserAgentSession.maxTabs; i++) {
          await session.newTab(url: 'https://tab$i.example/');
        }
        await tester.pumpAndSettle();
        final previous = session.controller;
        if (state == 'minimized') {
          await tester.tap(find.byKey(_minimize));
          await tester.pumpAndSettle();
        }
        FakeWebViewController? prepared;
        FakeWebViewPlatform.onCreated = (fake) {
          prepared = fake;
          fake.autoFinish = false;
          fake.onLoadRequest = (_) async {
            fake.startNext();
            fake.finishNext();
          };
        };
        Object? failure;
        final opening =
            openSharedBrowser(
              startUrl: 'http://127.0.0.1:4321/',
              authentication: BrowserHttpAuth(
                origin: Uri.parse('http://127.0.0.1:4321/'),
                username: 'opencode',
                password: 'test-secret-never-a-url-or-script',
              ),
            ).catchError((Object error) {
              failure = error;
            });
        await tester.pumpAndSettle();
        await opening;
        expect(failure, isA<BrowserHttpAuthException>());
        expect(session.controller, same(previous));
        expect(session.tabs.value, hasLength(BrowserAgentSession.maxTabs));
        expect(prepared!.javaScriptMode, JavaScriptMode.disabled);
        expect(prepared!.loadedUrls.last, 'about:blank');
        FakeWebViewPlatform.onCreated = null;
        for (final tab
            in session.tabs.value.where((tab) => !tab.active).toList()) {
          await session.closeTab(tab.id);
        }
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('stopping during bootstrap rejects and never registers a tab', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final auth = BrowserHttpAuth(
      origin: Uri.parse('http://127.0.0.1:4321/'),
      username: 'opencode',
      password: 'test-secret-never-a-url-or-script',
    );
    FakeWebViewController? prepared;
    void Function(String)? lateFinish;
    FakeWebViewPlatform.onCreated = (fake) {
      prepared = fake;
      fake.autoFinish = false;
      fake.onLoadRequest = (request) async {
        fake.startNext();
        if (request.uri.path == '/session') {
          lateFinish = fake.navigationDelegate?.onPageFinished;
          auth.dispose();
        } else {
          fake.finishNext();
        }
      };
    };
    Object? failure;
    final opening =
        openSharedBrowser(
          startUrl: 'http://127.0.0.1:4321/',
          authentication: auth,
        ).catchError((Object error) {
          failure = error;
        });
    await tester.pumpAndSettle();
    expect(failure, isA<BrowserHttpAuthException>());
    await opening;
    expect(BrowserAgentSession.instance.isAttached, isFalse);
    expect(find.byType(WebViewPage), findsNothing);
    expect(prepared!.loadedUrls.last, 'about:blank');
    lateFinish?.call('http://127.0.0.1:4321/session');
    await tester.pumpAndSettle();
    expect(BrowserAgentSession.instance.isAttached, isFalse);
    expect(find.byType(WebViewPage), findsNothing);
  });

  for (final failureMode in ['stop', 'browser-close']) {
    testWidgets('$failureMode during native tab setup rejects the handoff', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await openBrowser(tester);
      final session = BrowserAgentSession.instance;
      final previous = session.controller;
      final auth = BrowserHttpAuth(
        origin: Uri.parse('http://127.0.0.1:4321/'),
        username: 'opencode',
        password: 'test-secret-never-a-url-or-script',
      );
      FakeWebViewController? prepared;
      FakeWebViewPlatform.onCreated = (fake) {
        prepared = fake;
        fake.onSetNavigationDelegate = () async {
          if (fake.javaScriptMode == JavaScriptMode.unrestricted) {
            if (failureMode == 'stop') {
              auth.dispose();
            } else {
              session.unregister(previous!);
            }
          }
        };
      };
      Object? failure;
      final opening =
          openSharedBrowser(
            startUrl: 'http://127.0.0.1:4321/',
            authentication: auth,
          ).catchError((Object error) {
            failure = error;
          });
      await tester.pumpAndSettle();
      await opening;
      expect(failure, isA<BrowserHttpAuthException>());
      expect(prepared!.loadedUrls.last, 'about:blank');
      expect(session.tabs.value, hasLength(failureMode == 'stop' ? 1 : 0));
      if (failureMode == 'stop') expect(session.controller, same(previous));
      FakeWebViewPlatform.onCreated = null;
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('minimize keeps the page alive and expand does not reload it', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    final session = BrowserAgentSession.instance;
    final fake = FakeWebViewPlatform.lastCreated!;
    final loadedUrl = await session.controller!.currentUrl();

    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    expect(find.byType(WebViewPage), findsNothing);
    expect(find.byKey(BrowserMiniWindow.windowKey), findsOneWidget);
    expect(session.isAttached, isTrue);
    expect(session.minimized.value, isTrue);

    // The chat under the mini window still takes taps.
    await tester.tap(find.text('chat'));
    expect(chatTaps, 1);

    await tester.tap(find.byKey(BrowserMiniWindow.expandKey));
    await tester.pumpAndSettle();

    expect(find.byType(WebViewPage), findsOneWidget);
    expect(find.byKey(BrowserMiniWindow.windowKey), findsNothing);
    expect(identical(FakeWebViewPlatform.lastCreated, fake), isTrue);
    expect(await session.controller!.currentUrl(), loadedUrl);
    expect(session.minimized.value, isFalse);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(session.isAttached, isFalse);
  });

  testWidgets('closing the mini window ends the session', (tester) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(BrowserMiniWindow.closeKey));
    await tester.pumpAndSettle();

    final session = BrowserAgentSession.instance;
    expect(find.byKey(BrowserMiniWindow.windowKey), findsNothing);
    expect(session.isAttached, isFalse);
    expect(session.minimized.value, isFalse);
  });

  testWidgets('browser_use close also closes a minimized browser', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    await BrowserAgentSession.instance.close();
    await tester.pumpAndSettle();

    expect(find.byKey(BrowserMiniWindow.windowKey), findsNothing);
    expect(BrowserAgentSession.instance.isAttached, isFalse);
  });

  testWidgets('the header shows only the browser without a workspace', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.byKey(ChatHeaderSwitcher.filesKey), findsNothing);
    expect(find.byKey(ChatHeaderSwitcher.terminalKey), findsNothing);
    expect(find.byKey(ChatHeaderSwitcher.browserKey), findsOneWidget);
  });

  testWidgets('the mini window shows the site, the running action with '
      'Stop, and glides to the nearer edge after a drag', (tester) async {
    await tester.pumpWidget(app());
    await openBrowser(tester);
    final session = BrowserAgentSession.instance;
    session.pageFinished('https://www.example.org/page');
    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();

    expect(find.text('example.org'), findsOneWidget);

    session.currentActivity.value = BrowserActivity(
      id: 'a',
      action: 'scroll',
      startedAt: DateTime(2026),
    );
    await tester.pump();
    expect(find.byKey(WebViewStatusBanner.stopKey), findsOneWidget);
    session.currentActivity.value = null;
    await tester.pumpAndSettle();
    expect(find.byKey(WebViewStatusBanner.stopKey), findsNothing);

    final window = find.byKey(BrowserMiniWindow.windowKey);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getCenter(window).dx, greaterThan(screenWidth / 2));
    // Dragged a little to the left it returns to the right edge ...
    await tester.drag(find.text('example.org'), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(window).right, closeTo(screenWidth - 12, 1));
    // ... dragged past the middle it settles on the left.
    await tester.drag(find.text('example.org'), Offset(-screenWidth * 0.6, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(window).left, closeTo(8, 1));
  });

  testWidgets('downloads are watched after every navigation delegate, so the '
      'plugin cannot replace the listener (page and mini window)', (
    tester,
  ) async {
    final handoffs = BrowserHandoffs.instance;
    final originalId = handoffs.webViewId;
    addTearDown(() => handoffs.webViewId = originalId);
    handoffs.webViewId = (_) => 7;
    final delegatesAtWatch = <int>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('app.browser'), (
      call,
    ) async {
      if (call.method == 'watchDownloads') {
        expect((call.arguments as Map)['id'], 7);
        delegatesAtWatch.add(FakeWebViewPlatform.lastCreated!.delegatesSet);
      }
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('app.browser'),
        null,
      ),
    );

    await tester.pumpWidget(app());
    await openBrowser(tester);
    expect(delegatesAtWatch, [1]);

    await tester.tap(find.byKey(_minimize));
    await tester.pumpAndSettle();
    expect(delegatesAtWatch, [1, 2]);

    await tester.tap(find.byKey(BrowserMiniWindow.expandKey));
    await tester.pumpAndSettle();
    expect(delegatesAtWatch, [1, 2, 3]);
  });
}
