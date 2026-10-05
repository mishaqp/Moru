import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_device.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_bridge.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_runtime.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/core/services/scheduled_tasks_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/mini_apps/mini_app_launcher.dart';
import 'package:Kelivo/features/mini_apps/mini_app_job_runner.dart';
import 'package:Kelivo/features/mini_apps/pages/mini_app_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';
import '../../support/fake_webview_platform.dart';

class _Platform extends FakeWebViewPlatform {
  final controllers = <_Controller>[];
  void Function(_Controller)? onCreated;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params);
    controllers.add(controller);
    onCreated?.call(controller);
    return controller;
  }
}

class _Controller extends FakeWebViewController {
  _Controller(super.params);
  @override
  Future<void> enableZoom(bool enabled) async {}
  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage) listener,
  ) async {}
  @override
  Future<void> loadFile(String path) =>
      loadRequest(LoadRequestParams(uri: Uri.file(path)));
}

class _Device extends MiniAppDeviceService {
  int subscriptions = 0;
  bool hold = false;
  int finished = 0;
  ToolCallCancellation? nativeCancellation;
  late final events = StreamController<Map<String, dynamic>>.broadcast(
    onListen: () => subscriptions++,
    onCancel: () => subscriptions--,
  );
  @override
  Stream<Map<String, dynamic>> get changes => events.stream;
  @override
  Future<Map<String, dynamic>> snapshot() async => {
    'battery': {'level': 70},
  };
  @override
  Future<Map<String, dynamic>> execute(
    String handler,
    Map<String, dynamic> arguments,
  ) async {
    nativeCancellation = ToolCallCancellation.current;
    if (hold) await nativeCancellation!.cancelled;
    finished++;
    return {'status': 'applied', 'state': await snapshot()};
  }
}

void main() {
  late Directory temp;
  late MiniAppStore store;
  late MiniAppRuntime runtime;
  late _Device device;
  late _Platform platform;
  late SettingsProvider settings;
  late AssistantProvider assistants;
  late EnvironmentProvider environment;
  late ToolApprovalService approvals;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-page-runtime-');
    store = MiniAppStore(
      root: () async => Directory(p.join(temp.path, 'apps')),
    );
    device = _Device();
    runtime = MiniAppRuntime(store: store, device: device);
    platform = _Platform();
    WebViewPlatform.instance = platform;
    settings = SettingsProvider(createBusinessTestPreferences());
    assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    environment = EnvironmentProvider(
      preferences: createBusinessTestPreferences(),
    );
    approvals = ToolApprovalService();
    await Future.wait([settings.loaded, assistants.loaded, environment.loaded]);
  });
  tearDown(() async {
    await runtime.dispose();
    await device.events.close();
    approvals.dispose();
    settings.dispose();
    assistants.dispose();
    environment.dispose();
    await temp.delete(recursive: true);
  });

  Future<MiniApp> install({
    int version = 2,
    bool native = false,
    bool rootAction = false,
  }) async {
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'moru-app.json')).writeAsStringSync(
      jsonEncode({
        'id': 'panel',
        'name': 'Panel',
        'formatVersion': version,
        if (native) 'ui': {'engine': 'native'},
        if (version == 2)
          'permissions': [
            'device.battery.read',
            if (rootAction) 'device.root.power_save',
          ],
        if (rootAction)
          'actions': [
            {
              'name': 'power',
              'description': 'Set power saving',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'enabled': {'type': 'boolean'},
                },
                'required': ['enabled'],
                'additionalProperties': false,
              },
              'permissions': ['device.root.power_save'],
              'danger': 'root',
              'executor': {
                'kind': 'native',
                'handler': 'device.root.power_save.set',
              },
            },
          ],
      }),
    );
    File(p.join(source.path, 'index.html')).writeAsStringSync('<p>Panel</p>');
    File(p.join(source.path, 'screen.json')).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'components': [
          {'type': 'text', 'text': 'Native screen'},
        ],
      }),
    );
    return (await store.install(source)).app;
  }

  Widget wrap(Widget page) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: assistants),
      ChangeNotifierProvider.value(value: environment),
      ChangeNotifierProvider(create: (_) => WorkspaceRuntimeProvider()),
      ChangeNotifierProvider.value(value: approvals),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: page,
    ),
  );

  Future<void> ioUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  Future<String> invokePower(Uri uri) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, uri.port);
    try {
      final body = jsonEncode({
        'id': 1,
        'method': 'actions.invoke',
        'args': {
          'name': 'power',
          'arguments': {'enabled': true},
        },
      });
      socket.write(
        'POST ${uri.resolve('__moru').path} HTTP/1.1\r\n'
        'Host: ${uri.authority}\r\nOrigin: ${uri.origin}\r\n'
        'X-Moru-App-Token: ${uri.pathSegments[2]}\r\n'
        'Content-Length: ${utf8.encode(body).length}\r\n'
        'Connection: close\r\n\r\n$body',
      );
      return await utf8.decodeStream(socket);
    } finally {
      socket.destroy();
    }
  }

  testWidgets(
    'a retained web page cancels on detach and renews its bridge on resume',
    (tester) async {
      final app = (await tester.runAsync(() => install(rootAction: true)))!;
      await tester.runAsync(() async {
        await runtime.permissions.setGranted(
          app.id,
          'device.root.power_save',
          true,
        );
        await settings.setToolAutoApproveAll(true);
      });
      device.hold = true;
      await tester.pumpWidget(
        wrap(MiniAppPage(app: app, store: store, runtime: runtime)),
      );
      final controller = platform.controllers.single;
      await ioUntil(
        tester,
        () => controller.currentUrlSync?.startsWith('http:') ?? false,
      );
      final previous = Uri.parse(controller.currentUrlSync!);
      late Future<String> pending;
      await tester.runAsync(() async {
        pending = invokePower(previous);
      });
      await ioUntil(tester, () => device.nativeCancellation != null);
      final cancellation = device.nativeCancellation!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(cancellation.isCancelled(), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await ioUntil(
        tester,
        () => cancellation.isCancelled() && device.finished == 1,
      );
      await tester.runAsync(() async {
        await pending.timeout(const Duration(seconds: 2));
        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, previous.port),
          throwsA(isA<SocketException>()),
        );
      });
      device.hold = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await ioUntil(
        tester,
        () =>
            controller.currentUrlSync != previous.toString() &&
            (controller.currentUrlSync?.startsWith('http:') ?? false),
      );
      final current = Uri.parse(controller.currentUrlSync!);
      String? result;
      late Future<void> resumedCall;
      await tester.runAsync(() async {
        resumedCall = invokePower(current).then((response) {
          result = response;
        });
      });
      // The production listener belongs to the widget zone; pump its disk
      // and runtime continuations while the socket waits in the real zone.
      await ioUntil(tester, () => result != null);
      await tester.runAsync(() => resumedCall);
      expect(result, contains('"status":"applied"'));
      expect(device.finished, 2);
      expect(device.nativeCancellation, isNot(same(cancellation)));
      expect(controller.javaScriptChannels, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'v2 uses a private loopback origin and no native JavaScript channel',
    (tester) async {
      final app = (await tester.runAsync(() => install()))!;
      await tester.runAsync(
        () =>
            runtime.permissions.setGranted(app.id, 'device.battery.read', true),
      );
      await tester.pumpWidget(
        wrap(MiniAppPage(app: app, store: store, runtime: runtime)),
      );
      await ioUntil(
        tester,
        () =>
            platform.controllers.single.currentUrlSync?.startsWith('http:') ??
            false,
      );
      final controller = platform.controllers.single;
      final uri = Uri.parse(controller.currentUrlSync!);
      expect(uri.host, '127.0.0.1');
      expect(controller.javaScriptChannels, isEmpty);
      expect(
        await controller.navigationDelegate!.onNavigationRequest!(
          NavigationRequest(
            url: 'https://foreign.test/frame',
            isMainFrame: false,
          ),
        ),
        NavigationDecision.prevent,
      );
      await ioUntil(tester, () => device.subscriptions == 1);
      expect(device.subscriptions, 1);
      await tester.pumpWidget(const SizedBox());
      await ioUntil(tester, () => device.subscriptions == 0);
      await tester.runAsync(() async {
        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, uri.port),
          throwsA(isA<SocketException>()),
        );
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a v1 page retains its file transport and JavaScript bridge', (
    tester,
  ) async {
    final app = (await tester.runAsync(() => install(version: 1)))!;
    await tester.pumpWidget(
      wrap(MiniAppPage(app: app, store: store, runtime: runtime)),
    );
    await ioUntil(
      tester,
      () =>
          platform.controllers.single.currentUrlSync?.startsWith('file:') ??
          false,
    );
    expect(platform.controllers.single.javaScriptChannels, ['MoruBridge']);
    expect(device.subscriptions, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening a native app creates no WebView', (tester) async {
    final app = (await tester.runAsync(() => install(native: true)))!;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  MiniAppLauncher.open(context, app.id, store: store),
              child: const Text('Open panel'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open panel'));
    await ioUntil(
      tester,
      () => find.text('Native screen').evaluate().isNotEmpty,
    );
    expect(platform.controllers, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('native panels cannot start a hidden JavaScript job', (
    tester,
  ) async {
    final app = (await tester.runAsync(() => install(native: true)))!;
    await expectLater(
      MiniAppJobRunner.run(
        store: store,
        app: app,
        jobId: 'job',
        function: 'job',
        host: const MiniAppHost(),
      ),
      throwsA(
        isA<MiniAppException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
    expect(platform.controllers, isEmpty);
  });

  testWidgets(
    'v2 background jobs complete through the protected HTTP transport',
    (tester) async {
      final app = (await tester.runAsync(() => install()))!;
      late Uri uri;
      platform.onCreated = (controller) {
        controller.jsHandler = (script) {
          if (script.contains('var job = window')) {
            uri = Uri.parse(controller.currentUrlSync!);
            unawaited(() async {
              final socket = await Socket.connect(
                InternetAddress.loopbackIPv4,
                uri.port,
              );
              final body = jsonEncode({
                'method': '__jobDone',
                'args': {'error': null},
              });
              socket.write(
                'POST ${uri.resolve('__moru').path} HTTP/1.1\r\n'
                'Host: ${uri.authority}\r\nOrigin: ${uri.origin}\r\n'
                'X-Moru-App-Token: ${uri.pathSegments[2]}\r\n'
                'Content-Length: ${utf8.encode(body).length}\r\nConnection: close\r\n\r\n$body',
              );
              await utf8.decodeStream(socket);
            }());
          }
          return '""';
        };
      };
      await tester.runAsync(
        () => MiniAppJobRunner.run(
          store: store,
          app: app,
          jobId: 'job',
          function: 'job',
          host: MiniAppHost(
            runtime: runtime,
            background: true,
            invocation: const MiniAppInvocation(
              source: MiniAppInvocationSource.background,
            ),
          ),
        ),
      );
      expect(platform.controllers.single.javaScriptChannels, isEmpty);
      expect(device.subscriptions, 0);
      await tester.runAsync(() async {
        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, uri.port),
          throwsA(isA<SocketException>()),
        );
      });
    },
  );

  testWidgets(
    'cancel during job startup closes its late local host before loading',
    (tester) async {
      final app = (await tester.runAsync(() => install()))!;
      final cancellation = ScheduledRunCancellation();
      await tester.runAsync(() async {
        // Keep both sides of the I/O handshake in the real async zone.
        // A Completer created in the widget fake-clock zone cannot wake a
        // runAsync callback while that callback is awaiting the handshake.
        final configuring = Completer<void>();
        final continueConfiguration = Completer<void>();
        platform.onCreated = (controller) {
          controller.onSetNavigationDelegate = () {
            configuring.complete();
            return continueConfiguration.future;
          };
        };
        final running = MiniAppJobRunner.run(
          store: store,
          app: app,
          jobId: 'job',
          function: 'job',
          host: const MiniAppHost(background: true),
          cancellation: cancellation,
        );
        final denied = expectLater(running, throwsA(isA<StateError>()));
        try {
          await configuring.future.timeout(const Duration(seconds: 2));
          await cancellation.cancel().timeout(const Duration(seconds: 2));
        } finally {
          continueConfiguration.complete();
        }
        await denied.timeout(const Duration(seconds: 2));
      });
      expect(
        platform.controllers.single.loadedUrls.where(
          (url) => url.startsWith('http:'),
        ),
        isEmpty,
      );
      expect(platform.controllers.single.javaScriptChannels, isEmpty);
      expect(cancellation.onCancel, isNull);
    },
  );
}
