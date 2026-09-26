import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/services/mini_apps/mini_app_bridge.dart';
import '../../core/services/mini_apps/mini_app_check.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import 'mini_app_launcher.dart';

/// Opens a freshly published mini app in a WebView that is never shown, so
/// the agent learns about script errors, missing files and failing `moru.*`
/// calls before the user opens the app.
class MiniAppChecker {
  const MiniAppChecker._();

  static const Duration loadTimeout = Duration(seconds: 15);

  /// Time for the page's startup code (storage reads, first render) to run
  /// after the load event.
  static const Duration settle = Duration(seconds: 2);

  static Future<MiniAppCheckReport> run(MiniApp app) async {
    final sandbox = await MiniAppSandbox.create(
      app,
      fetch: MiniAppLauncher.fetcher,
    );
    final bridge = sandbox.bridge;
    final console = <String>[];
    final loaded = Completer<void>();
    final controller = WebViewController();
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'MoruBridge',
        onMessageReceived: (message) async {
          final script = await bridge.handle(message.message);
          if (script != null) await controller.runJavaScript(script);
        },
      );
      await controller.setOnConsoleMessage((message) {
        if ((message.level == JavaScriptLogLevel.error ||
                message.level == JavaScriptLogLevel.warning) &&
            console.length < MiniAppBridge.maxProblems) {
          console.add('${message.level.name}: ${message.message}');
        }
      });
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
          onNavigationRequest: (request) => request.url.startsWith('file://')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      await controller.loadFile(sandbox.app.entryPath);
      var didLoad = true;
      try {
        await loaded.future.timeout(loadTimeout);
      } on TimeoutException {
        didLoad = false;
      }
      int? visible;
      if (didLoad) {
        await Future<void>.delayed(settle);
        final result = await controller.runJavaScriptReturningResult(
          'document.body ? document.body.innerText.trim().length + '
          'document.querySelectorAll("img,canvas,svg,video").length : 0',
        );
        visible = result is num ? result.toInt() : int.tryParse('$result');
      }
      return MiniAppCheckReport(
        loaded: didLoad,
        pageErrors: List.of(bridge.pageErrors),
        console: console,
        failedCalls: List.of(bridge.failedCalls),
        visibleContent: visible,
      );
    } finally {
      // Stop the app's timers before its sandbox goes away.
      await controller.loadHtmlString('');
      await sandbox.dispose();
    }
  }
}
