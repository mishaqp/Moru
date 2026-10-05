import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/services/mini_apps/mini_app_bridge.dart';
import '../../core/services/mini_apps/mini_app_check.dart';
import '../../core/services/mini_apps/mini_app_jobs.dart';
import '../../core/services/mini_apps/mini_app_manifest.dart';
import '../../core/services/mini_apps/mini_app_servers.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../core/services/mini_apps/mini_app_web_server.dart';
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
    if (app.uiEngine == MiniAppUiEngine.native) {
      try {
        MiniAppManifest.validateScreen(
          jsonDecode(await File(app.entryPath).readAsString()),
          app.actions,
        );
        return const MiniAppCheckReport(loaded: true);
      } catch (error) {
        return MiniAppCheckReport(
          loaded: false,
          failedCalls: ['${app.entry}: $error'],
        );
      }
    }
    final sandbox = await MiniAppSandbox.create(
      app,
      fetch: MiniAppLauncher.fetcher,
      serverEnvironment: serverEnvironment,
    );
    final bridge = sandbox.bridge;
    final console = <String>[];
    final loaded = Completer<void>();
    final controller = WebViewController();
    MiniAppWebServer? localHost;
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (app.formatVersion < 2) {
        await controller.addJavaScriptChannel(
          'MoruBridge',
          onMessageReceived: (message) async {
            final script = await bridge.handle(message.message);
            if (script != null) await controller.runJavaScript(script);
          },
        );
      } else {
        localHost = MiniAppWebServer(
          store: sandbox.store,
          protectedApp: sandbox.app,
          bridgeFor: (_) => bridge,
        );
        await localHost.start(port: 0, localhostOnly: true);
      }
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
          onNavigationRequest: (request) =>
              (localHost == null
                  ? request.url.startsWith('file://')
                  : localHost.allowsNavigation(Uri.parse(request.url)))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      if (localHost == null) {
        await controller.loadFile(sandbox.app.entryPath);
      } else {
        await controller.loadRequest(localHost.appUri!);
      }
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
      bridge.dispose();
      try {
        await controller.loadHtmlString('<html></html>');
      } finally {
        try {
          await localHost?.stop();
        } finally {
          await sandbox.dispose();
        }
      }
    }
  }
}
