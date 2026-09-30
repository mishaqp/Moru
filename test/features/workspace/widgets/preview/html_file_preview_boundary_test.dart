import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:Kelivo/features/workspace/widgets/preview/html_file_preview.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../../../support/fake_webview_platform.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _AndroidPreviewController extends FakeWebViewController
    implements AndroidWebViewController {
  _AndroidPreviewController(super.params);

  final loaded = Completer<void>();
  Future<void>? fileAccessBarrier;
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    await super.loadHtmlString(html, baseUrl: baseUrl);
    if (!loaded.isCompleted) loaded.complete();
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    await super.loadRequest(params);
    if (!loaded.isCompleted) loaded.complete();
  }

  bool? allowFileAccess;
  bool? allowContentAccess;

  @override
  Future<void> setAllowFileAccess(bool allow) async {
    allowFileAccess = allow;
    await fileAccessBarrier;
  }

  @override
  Future<void> setAllowContentAccess(bool allow) async =>
      allowContentAccess = allow;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewPlatform extends FakeWebViewPlatform {
  late _AndroidPreviewController controller;
  final created = Completer<_AndroidPreviewController>();
  Completer<_AndroidPreviewController>? nextCreated;
  Future<void>? firstFileAccessBarrier;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    controller = _AndroidPreviewController(params);
    if (!created.isCompleted) {
      controller.fileAccessBarrier = firstFileAccessBarrier;
      created.complete(controller);
    } else {
      nextCreated?.complete(controller);
      nextCreated = null;
    }
    return controller;
  }
}

void main() {
  late Directory temporary;
  late _PreviewPlatform platform;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('html_preview_boundary_');
    platform = _PreviewPlatform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  testWidgets(
    'HTML preview loads capability URL and relative assets with local file access disabled',
    (tester) async {
      const html =
          '<h1>Preview marker</h1><link rel="stylesheet" href="style.css"><img src="file:///private/secret.png">';
      final file = File('${temporary.path}/index.html')
        ..writeAsStringSync(html);
      File(
        '${temporary.path}/style.css',
      ).writeAsStringSync('body { color: red; }');
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: HtmlFilePreview(file: file)),
          ),
        ),
      );
      final controller = await tester.runAsync(() => platform.created.future);
      await tester.runAsync(() => controller!.loaded.future);
      await tester.pump();
      expect(platform.controller.lastLoadedHtml, isNull);
      final uri = Uri.parse(platform.controller.currentUrlSync!);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final client = HttpClient();
          try {
            final response = await (await client.getUrl(uri)).close();
            expect(response.statusCode, HttpStatus.ok);
            expect(
              await response.transform(utf8.decoder).join(),
              contains('Preview marker'),
            );
            expect(
              response.headers.value('content-security-policy'),
              contains("base-uri 'none'"),
            );
            final css = await (await client.getUrl(
              uri.resolve('style.css'),
            )).close();
            expect(
              await css.transform(utf8.decoder).join(),
              'body { color: red; }',
            );
          } finally {
            client.close(force: true);
          }
        }, _RealHttpOverrides()),
      );
      expect(platform.controller.allowFileAccess, isFalse);
      expect(platform.controller.allowContentAccess, isFalse);
      final navigate =
          platform.controller.navigationDelegate!.onNavigationRequest!;
      for (final url in [
        'about:blank',
        'file:///private/secret.txt',
        'content://private/secret',
        'javascript:location.href="file:///private"',
      ]) {
        expect(
          await navigate(NavigationRequest(url: url, isMainFrame: true)),
          NavigationDecision.prevent,
        );
      }
      expect(
        await navigate(
          const NavigationRequest(
            url: 'https://example.com/',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.navigate,
      );
      final state = tester.state<HtmlFilePreviewState>(
        find.byType(HtmlFilePreview),
      );
      await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
      await tester.runAsync(() => state.serverClosed);
      await tester.runAsync(() async {
        await expectLater(
          Socket.connect(uri.host, uri.port),
          throwsA(isA<SocketException>()),
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('disposing during a late bind closes the late owned listener', (
    tester,
  ) async {
    final file = File('${temporary.path}/index.html')
      ..writeAsStringSync('<h1>late</h1>');
    // IO phase barriers must be created in the real zone: a FakeAsync
    // Completer schedules completion on fake microtasks during runAsync.
    final bound = (await tester.runAsync(() async => Completer<void>()))!;
    final release = (await tester.runAsync(
      () async => Completer<ServerSocket>(),
    ))!;
    final listener = await tester.runAsync(
      () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    final port = listener!.port;
    addTearDown(() async {
      if (!release.isCompleted) release.complete(listener);
      await listener.close();
    });
    await tester.pumpWidget(_app(file, autoLoad: false));
    final state = tester.state<HtmlFilePreviewState>(
      find.byType(HtmlFilePreview),
    );
    await tester.runAsync(() async {
      final nativeZone = Zone.current;
      // This SDK's default IOOverrides.fseGetType loses the native path
      // terminator. Delegate real type checks to the unmodified zone; only
      // bind is delayed. No filesystem guard or assertion is bypassed.
      final loading = IOOverrides.runZoned(
        () => state.load(),
        fseGetType: (path, followLinks) => nativeZone.run(
          () => FileSystemEntity.type(path, followLinks: followLinks),
        ),
        serverSocketBind:
            (address, port, {backlog = 0, v6Only = false, shared = false}) {
              bound.complete();
              return release.future;
            },
      );
      final reachedBind = await Future.any([
        bound.future.then((_) => true),
        loading.then((_) => false),
      ]);
      expect(
        reachedBind,
        isTrue,
        reason: 'initialization must reach the injected bind',
      );
    });
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    release.complete(listener);
    await tester.runAsync(() => state.serverClosed);
    expect(platform.created.isCompleted, isFalse);
    await tester.runAsync(() async {
      await expectLater(
        Socket.connect('127.0.0.1', port),
        throwsA(isA<SocketException>()),
      );
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh closes old ownership and cancelled init cannot register later',
    (tester) async {
      final first = File('${temporary.path}/index.html')
        ..writeAsStringSync('<h1>first</h1>');
      final second = File('${temporary.path}/next.html')
        ..writeAsStringSync('<h1>second</h1>');
      final release = (await tester.runAsync(() async => Completer<void>()))!;
      platform.firstFileAccessBarrier = release.future;
      await tester.runAsync(() => tester.pumpWidget(_app(first)));
      final oldController = await tester.runAsync(
        () => platform.created.future,
      );
      final state = tester.state<HtmlFilePreviewState>(
        find.byType(HtmlFilePreview),
      );
      final oldUri = state.renderedUri!;
      final next = (await tester.runAsync(
        () async => Completer<_AndroidPreviewController>(),
      ))!;
      platform.nextCreated = next;
      await tester.runAsync(() => tester.pumpWidget(_app(second)));
      final current = await tester.runAsync(() => next.future);
      await tester.runAsync(() => current!.loaded.future);
      final currentUri = state.renderedUri!;
      expect(currentUri, isNot(oldUri));
      await tester.runAsync(() async {
        await expectLater(
          Socket.connect(oldUri.host, oldUri.port),
          throwsA(isA<SocketException>()),
        );
      });
      release.complete();
      await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
      await tester.runAsync(() => state.serverClosed);
      expect(oldController!.loaded.isCompleted, isFalse);
      expect(current!.currentUrlSync, currentUri.toString());
      await tester.runAsync(() async {
        await expectLater(
          Socket.connect(currentUri.host, currentUri.port),
          throwsA(isA<SocketException>()),
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(File file, {bool autoLoad = true}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: HtmlFilePreview(
      key: const ValueKey('owned-html-preview'),
      file: file,
      autoLoad: autoLoad,
    ),
  ),
);
