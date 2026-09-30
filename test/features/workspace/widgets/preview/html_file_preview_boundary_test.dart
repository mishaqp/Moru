import 'dart:io';
import 'dart:async';

import 'package:Kelivo/features/workspace/widgets/preview/html_file_preview.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../../../support/fake_webview_platform.dart';

class _AndroidPreviewController extends FakeWebViewController
    implements AndroidWebViewController {
  _AndroidPreviewController(super.params);

  final loaded = Completer<void>();
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    await super.loadHtmlString(html, baseUrl: baseUrl);
    loaded.complete();
  }

  bool? allowFileAccess;
  bool? allowContentAccess;

  @override
  Future<void> setAllowFileAccess(bool allow) async => allowFileAccess = allow;
  @override
  Future<void> setAllowContentAccess(bool allow) async =>
      allowContentAccess = allow;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewPlatform extends FakeWebViewPlatform {
  late _AndroidPreviewController controller;
  final created = Completer<_AndroidPreviewController>();
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    controller = _AndroidPreviewController(params);
    created.complete(controller);
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
    'HTML preview renders checked text with local file access disabled',
    (tester) async {
      const html =
          '<h1>Preview marker</h1><img src="file:///private/secret.png">';
      final file = File('${temporary.path}/index.html')
        ..writeAsStringSync(html);
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
      expect(platform.controller.lastLoadedHtml, contains('Preview marker'));
      expect(platform.controller.allowFileAccess, isFalse);
      expect(platform.controller.allowContentAccess, isFalse);
      expect(
        platform.controller.lastLoadedHtml,
        contains('Content-Security-Policy'),
      );
      final navigate =
          platform.controller.navigationDelegate!.onNavigationRequest!;
      for (final url in [
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
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
