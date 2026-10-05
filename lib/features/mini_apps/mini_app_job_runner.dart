import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/services/mini_apps/mini_app_bridge.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../core/services/mini_apps/mini_app_web_server.dart';
import '../../core/services/scheduled_tasks_service.dart';

/// Runs a background job of a mini app: opens the app in a WebView that is
/// never shown, calls the job's global function and waits for it, including
/// a returned promise. Problems go to the app's error journal, marked with
/// the job.
class MiniAppJobRunner {
  const MiniAppJobRunner._();

  static const Duration loadTimeout = Duration(seconds: 15);
  static const Duration runTimeout = Duration(seconds: 30);

  /// Calls [function] and reports back through `MoruBridge` as `__jobDone`.
  static String callScript(String function) {
    final name = jsonEncode(function);
    return '''
(function () {
  function done(error) {
    MoruBridge.postMessage(JSON.stringify({ method: '__jobDone', args: { error: error } }));
  }
  var job = window[$name];
  if (typeof job !== 'function') {
    done('The app has no global function ' + $name + '.');
    return;
  }
  Promise.resolve().then(function () { return job(); }).then(
    function () { done(null); },
    function (e) { done(String(e && e.message ? e.message : e)); });
})();
''';
  }

  /// Throws a [StateError] with the reason when the job failed.
  static Future<void> run({
    required MiniAppStore store,
    required MiniApp app,
    required String jobId,
    required String function,
    required MiniAppHost host,
    ScheduledRunCancellation? cancellation,
  }) async {
    cancellation?.check();
    if (app.uiEngine == MiniAppUiEngine.native) {
      throw const MiniAppException(
        'unavailable',
        'Native panels do not run JavaScript jobs.',
      );
    }
    void log(String problem) => unawaited(
      store.logError(app.id, 'job $jobId: $problem').catchError((_) {}),
    );
    final loaded = Completer<void>();
    final finished = Completer<String?>();
    final bridge = MiniAppBridge(
      store: store,
      appId: app.id,
      host: host,
      onJobDone: (error) {
        if (!finished.isCompleted) finished.complete(error);
      },
      onProblem: (kind, problem) {
        // The console has the details of these.
        if (kind != 'error' && kind != 'promise') log(problem);
      },
    );
    final controller = WebViewController();
    MiniAppWebServer? localHost;
    // Set once the job is over: replies and console output that arrive
    // while the page is being cleared belong to no page and are dropped.
    var closed = false;
    Future<void> cancel() async {
      closed = true;
      bridge.dispose();
      if (!finished.isCompleted) finished.complete('cancelled');
      await localHost?.stop();
      await controller.loadHtmlString('<html></html>').catchError((_) {});
    }

    cancellation?.onCancel = cancel;
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      cancellation?.check();
      if (app.formatVersion < 2) {
        await controller.addJavaScriptChannel(
          'MoruBridge',
          onMessageReceived: (message) async {
            final script = await bridge.handle(message.message);
            if (script != null && !closed) {
              await controller.runJavaScript(script);
            }
          },
        );
      } else {
        localHost = MiniAppWebServer(
          store: store,
          protectedApp: app,
          bridgeFor: (_) => bridge,
        );
        await localHost.start(port: 0, localhostOnly: true);
        cancellation?.check();
      }
      await controller.setOnConsoleMessage((message) {
        if (!closed &&
            message.level == JavaScriptLogLevel.error &&
            !message.message.startsWith('Failed to load resource')) {
          log('console: ${message.message}');
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
      await store.refreshBridge(app);
      cancellation?.check();
      if (localHost == null) {
        await controller.loadFile(app.entryPath);
      } else {
        await controller.loadRequest(localHost.appUri!);
      }
      try {
        await loaded.future.timeout(loadTimeout);
      } on TimeoutException {
        throw _fail(log, 'the app did not load in time');
      }
      cancellation?.check();
      await controller.runJavaScript(callScript(function));
      final String? error;
      try {
        error = await finished.future.timeout(runTimeout);
      } on TimeoutException {
        throw _fail(
          log,
          '$function() did not finish within ${runTimeout.inSeconds} s',
        );
      }
      if (error != null) throw _fail(log, error);
    } finally {
      // Stop the app's timers and requests.
      closed = true;
      bridge.dispose();
      if (identical(cancellation?.onCancel, cancel)) {
        cancellation?.onCancel = null;
      }
      try {
        await controller.loadHtmlString('<html></html>');
      } finally {
        await localHost?.stop();
      }
    }
  }

  static StateError _fail(void Function(String) log, String reason) {
    log(reason);
    return StateError(reason);
  }
}
