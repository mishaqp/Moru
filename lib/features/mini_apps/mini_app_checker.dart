import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/services/mini_apps/mini_app_bridge.dart';
import '../../core/services/mini_apps/mini_app_check.dart';
import '../../core/services/mini_apps/mini_app_jobs.dart';
import '../../core/services/mini_apps/mini_app_local_session.dart';
import '../../core/services/mini_apps/mini_app_servers.dart';
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

  static Future<MiniAppCheckReport> run(
    MiniApp app, {
    MiniAppServerEnvironment? serverEnvironment,
    MiniAppJobs? jobs,
  }) async {
    final sandbox = await MiniAppSandbox.create(
      app,
      fetch: MiniAppLauncher.fetcher,
      serverEnvironment: serverEnvironment,
    );
    final bridge = sandbox.bridge;
    final console = <String>[];
    final loaded = Completer<void>();
    final controller = WebViewController();
    MiniAppLocalSession? local;
    try {
      local = await MiniAppLocalSession.start(
        store: sandbox.store,
        app: sandbox.app,
        ephemeral: true,
      );
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
          onPageFinished: (url) {
            if (local!.pageFinished(url)) return;
            if (!loaded.isCompleted) loaded.complete();
          },
          onNavigationRequest: (request) => local!.allowsNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      await local.prepare(controller);
      await controller.loadRequest(local.entryUri(sandbox.app));
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
      final failedCalls = List.of(bridge.failedCalls);
      var scheduled = const <String>[];
      // Jobs of an app that works are scheduled for the installed app.
      if (jobs != null &&
          didLoad &&
          bridge.pageErrors.isEmpty &&
          failedCalls.isEmpty) {
        try {
          scheduled = await sandbox.adoptJobs(jobs);
        } on MiniAppException catch (e) {
          failedCalls.add('jobs.set: ${e.message}');
        }
      }
      return MiniAppCheckReport(
        loaded: didLoad,
        pageErrors: List.of(bridge.pageErrors),
        console: console,
        failedCalls: failedCalls,
        visibleContent: visible,
        server: await sandbox.serverStatus(),
        scheduledJobs: scheduled,
      );
    } finally {
      // Stop the app's timers before its sandbox goes away.
      try {
        await controller.loadHtmlString('<!doctype html><html></html>');
      } finally {
        await local?.close();
        await sandbox.dispose();
      }
    }
  }
}
