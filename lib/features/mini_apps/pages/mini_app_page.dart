import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/mini_apps/mini_app_bridge.dart';
import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/mini_apps/mini_app_servers.dart';
import '../../../core/services/mini_apps/mini_app_web_server.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../mini_app_display.dart';
import '../mini_app_launcher.dart';
import '../mini_app_permissions_sheet.dart';
import '../../home/services/tool_approval_service.dart';
import '../widgets/mini_app_sheets.dart';

/// Runs one installed mini app full screen, with `window.moru` wired to
/// [MiniAppBridge].
class MiniAppPage extends StatefulWidget {
  const MiniAppPage({super.key, required this.app, this._store, this.runtime});

  final MiniApp app;
  final MiniAppStore? _store;
  final MiniAppRuntime? runtime;

  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final Future<void> _configured;
  MiniAppBridge? _bridge;
  MiniAppWebServer? _localHost;
  StreamSubscription<Map<String, dynamic>>? _stateChanges;
  late final MiniAppRuntime _runtime =
      widget.runtime ??
      (identical(_store, MiniAppStore.instance)
          ? MiniAppLauncher.runtime
          : MiniAppRuntime(store: _store));
  late final bool _ownsRuntime =
      widget.runtime == null && !identical(_store, MiniAppStore.instance);
  final String _approvalScope = 'mini-app-web-${UniqueKey()}';
  ToolApprovalService? _approvals;
  int _epoch = 0;
  bool _closed = false;
  bool _paused = false;
  bool _detached = false;
  Future<void>? _detaching;
  bool _hasChannel = false;

  /// The app's server while the page is open; a rollback may change it.
  late MiniAppServerLease _server;
  StreamSubscription<({String appId, String key})>? _changes;
  bool _loading = true;

  /// The code on screen; a rollback replaces it.
  late MiniApp _app = widget.app;

  /// Entries in the error journal, and whether one came in while the app
  /// is open.
  int _errors = 0;
  bool _freshErrors = false;

  /// Problems this page sent to the journal since it loaded.
  int _logged = 0;

  MiniAppStore get _store => widget._store ?? MiniAppStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController();
    _server = _leaseServer(widget.app);
    // Data the chat changed while the app is open.
    _changes = _store.changes
        .where((change) => change.appId == widget.app.id)
        .listen(
          (change) => unawaited(_send(MiniAppBridge.changedScript(change.key))),
        );
    MiniAppDisplay.apply(null, _app);
    _configured = _configure();
    unawaited(_configured.then((_) => _load()).catchError(_loadFailed));
  }

  void _loadFailed(Object error) {
    if (mounted && !_closed && !_detached) {
      _logError('$error');
      setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final detached = _detached;
      _paused = false;
      _detached = false;
      if (detached) {
        final epoch = ++_epoch;
        unawaited(_resumeAfterDetach(epoch).catchError(_loadFailed));
      } else {
        _watchState(_epoch, _app);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _paused = true;
      if (state == AppLifecycleState.detached) {
        _detached = true;
        _epoch++;
        // Android retains this Flutter engine after Activity detachment.
        // Mounted alone cannot own a pending native operation.
        _bridge?.dispose();
        _approvals?.cancelForConversation(_approvalScope);
        _detaching = _detachResources().catchError(_loadFailed);
        unawaited(_detaching);
      } else {
        final watch = _stateChanges;
        _stateChanges = null;
        unawaited(watch?.cancel());
      }
    }
  }

  Future<void> _detachResources() async {
    final previous = _detaching;
    final watch = _stateChanges;
    final host = _localHost;
    final server = _server;
    _stateChanges = null;
    _localHost = null;
    await previous;
    try {
      await watch?.cancel();
    } finally {
      try {
        await host?.stop();
      } finally {
        await server.release();
      }
    }
  }

  Future<void> _resumeAfterDetach(int epoch) async {
    await _detaching;
    await _configured;
    if (!_active(epoch, _app)) return;
    _server = _leaseServer(_app);
    await _load();
  }

  void _watchState(int epoch, MiniApp app) {
    if (_paused ||
        _stateChanges != null ||
        app.formatVersion < 2 ||
        !_active(epoch, app)) {
      return;
    }
    _stateChanges = _runtime.watch(app.id, (state) {
      if (_active(epoch, app)) {
        unawaited(_send(MiniAppBridge.stateChangedScript(state)));
      }
    });
  }

  Future<void> _configure() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Double taps are game input, not zoom.
    await _controller.enableZoom(false);
    await _controller.setOnConsoleMessage((message) {
      // Chromium's own line for a missing file; the bridge reports it
      // with the file name.
      if (message.level == JavaScriptLogLevel.error &&
          !message.message.startsWith('Failed to load resource')) {
        _logError('console: ${message.message}');
      }
    });
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (mounted && !_closed) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          // Pages of the app stay inside; everything else opens outside.
          final uri = Uri.tryParse(request.url);
          if (_app.formatVersion >= 2) {
            if (uri != null && (_localHost?.allowsNavigation(uri) ?? false)) {
              return NavigationDecision.navigate;
            }
            // A foreign frame cannot trigger privileged calls or an
            // external application launch on behalf of this page.
            if (!request.isMainFrame) return NavigationDecision.prevent;
          } else if (request.url.startsWith('file://')) {
            return NavigationDecision.navigate;
          }
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
          return NavigationDecision.prevent;
        },
      ),
    );
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // Sounds start from game code, not only right after a tap.
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    }
  }

  MiniAppServerLease _leaseServer(MiniApp app) => MiniAppLauncher.servers.lease(
    app,
    MiniAppLauncher.serverEnvironment(
      context.read<WorkspaceRuntimeProvider>(),
      context.read<EnvironmentProvider>(),
    ),
  );

  Future<void> _load() async {
    if (_closed || _detached || !mounted) return;
    final epoch = ++_epoch;
    final app = _app;
    _bridge?.dispose();
    _approvals?.cancelForConversation(_approvalScope);
    await _stateChanges?.cancel();
    _stateChanges = null;
    final previousHost = _localHost;
    _localHost = null;
    await previousHost?.stop();
    if (!_active(epoch, app)) return;
    await _store.refreshBridge(app);
    if (!_active(epoch, app)) return;
    final errors = await _store.readErrors(app.id);
    if (!mounted || !_active(epoch, app)) return;
    if (mounted && errors.isNotEmpty) setState(() => _errors = errors.length);
    _bridge = MiniAppBridge(
      store: _store,
      appId: app.id,
      host: MiniAppLauncher.hostFor(
        app,
        context.read<SettingsProvider>(),
        context.read<AssistantProvider>(),
        runtime: _runtime,
        isAllowed: () => _active(epoch, app),
        approve: (app, action, arguments) async {
          if (!_active(epoch, app)) return false;
          ToolApprovalService? approvals;
          try {
            approvals = context.read<ToolApprovalService>();
          } catch (_) {}
          if (approvals == null) return false;
          _approvals = approvals;
          return requestMiniAppActionApproval(
            context,
            app: app,
            action: action,
            arguments: arguments,
            isActive: () => _active(epoch, app),
            scope: _approvalScope,
            approvals: approvals,
          );
        },
        close: () async {
          if (_active(epoch, app)) Navigator.of(context).pop();
        },
        server: (args) => _server.fetch(args),
        serverUrl: (path) => _server.url(path),
      ),
      onProblem: (kind, problem) {
        if (kind != 'error' && kind != 'promise') _logError(problem);
      },
    );
    if (app.formatVersion >= 2) {
      if (_hasChannel) {
        await _controller.removeJavaScriptChannel('MoruBridge');
        _hasChannel = false;
      }
      if (!_active(epoch, app)) return;
      final bridge = _bridge!;
      final host = MiniAppWebServer(
        store: _store,
        protectedApp: app,
        bridgeFor: (_) => bridge,
      );
      // Publish ownership before bind so dispose can cancel a late start.
      _localHost = host;
      await host.start(port: 0, localhostOnly: true);
      if (!_active(epoch, app)) {
        await host.stop();
        return;
      }
      await _controller.loadRequest(host.appUri!);
      if (!_active(epoch, app)) return;
      _watchState(epoch, app);
    } else {
      if (!_hasChannel) {
        await _controller.addJavaScriptChannel(
          'MoruBridge',
          onMessageReceived: (message) => unawaited(_answer(message.message)),
        );
        _hasChannel = true;
      }
      if (!_active(epoch, app)) return;
      await _controller.loadFile(app.entryPath);
    }
  }

  bool _active(int epoch, MiniApp app) =>
      mounted &&
      !_closed &&
      !_detached &&
      epoch == _epoch &&
      identical(_store.byId(app.id), app);

  Future<void> _send(String script) async {
    if (!mounted || _closed) return;
    final epoch = _epoch;
    final app = _app;
    if (app.formatVersion >= 2) {
      final url = await _controller.currentUrl();
      if (url == null ||
          !(_localHost?.allowsNavigation(Uri.parse(url)) ?? false)) {
        return;
      }
    }
    if (!_active(epoch, app)) return;
    await _controller.runJavaScript(script);
  }

  void _logError(String problem) {
    // One page cannot fill the journal with a loop.
    if (_logged++ >= MiniAppBridge.maxProblems) return;
    unawaited(_store.logError(_app.id, problem).catchError((_) {}));
    if (!mounted) return;
    setState(() {
      _errors++;
      _freshErrors = true;
    });
  }

  Future<void> _showErrors() async {
    setState(() => _freshErrors = false);
    await showMiniAppErrors(context, store: _store, app: _app);
    final errors = await _store.readErrors(_app.id);
    if (mounted) setState(() => _errors = errors.length);
  }

  Future<void> _more() async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showOptionSheet<String>(
      context,
      title: _app.name,
      items: [
        if (_app.formatVersion >= 2)
          OptionSheetItem(
            value: 'permissions',
            icon: Lucide.Shield,
            label: l10n.miniAppsPermissionsTitle,
          ),
        OptionSheetItem(
          value: 'versions',
          icon: Lucide.History,
          label: l10n.miniAppsVersions,
        ),
        if (_app.serverCommand != null)
          OptionSheetItem(
            value: 'server',
            icon: Lucide.Server,
            label: l10n.miniAppsServer,
          ),
        OptionSheetItem(
          value: 'jobs',
          icon: Lucide.CalendarClock,
          label: l10n.miniAppsJobs,
        ),
        OptionSheetItem(
          value: 'errors',
          icon: Lucide.Bug,
          label: l10n.miniAppsErrors,
        ),
        OptionSheetItem(
          value: 'pin',
          icon: Lucide.Smartphone,
          label: l10n.miniAppsAddToHomeScreen,
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'permissions':
        await showMiniAppPermissions(
          context,
          app: _app,
          runtime: _runtime,
          store: _store,
        );
      case 'versions':
        final restored = await showMiniAppVersions(
          context,
          store: _store,
          app: _app,
        );
        if (restored == null || !mounted) return;
        if (restored.uiEngine == MiniAppUiEngine.native) {
          final navigator = Navigator.of(context);
          navigator.pop();
          unawaited(
            MiniAppLauncher.open(navigator.context, restored.id, store: _store),
          );
          return;
        }
        MiniAppDisplay.apply(_app, restored);
        // The restored code may run another server.
        unawaited(_server.release());
        _server = _leaseServer(restored);
        setState(() {
          _app = restored;
          _errors = 0;
          _freshErrors = false;
          _logged = 0;
          _loading = true;
        });
        await _load();
      case 'server':
        await showMiniAppServer(
          context,
          servers: MiniAppLauncher.servers,
          app: _app,
        );
      case 'jobs':
        await showMiniAppJobs(context, jobs: MiniAppLauncher.jobs, app: _app);
      case 'errors':
        await _showErrors();
      case 'pin':
        await _pin();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    _epoch++;
    _bridge?.dispose();
    _approvals?.cancelForConversation(_approvalScope);
    unawaited(_localHost?.stop());
    unawaited(_stateChanges?.cancel());
    if (_ownsRuntime) unawaited(_runtime.dispose());
    unawaited(_controller.loadHtmlString('<html></html>').catchError((_) {}));
    MiniAppDisplay.apply(_app, null);
    unawaited(_server.release());
    _controlsTimer?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _answer(String message) async {
    final script = await _bridge?.handle(message);
    if (script == null || !mounted) return;
    await _send(script);
  }

  Future<void> _pin() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await MiniAppLauncher.pinShortcut(_app);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok ? l10n.miniAppsPinRequested : l10n.miniAppsPinUnsupported,
      type: ok ? NotificationType.success : NotificationType.warning,
    );
  }

  /// Fullscreen apps have no app bar: back first shows these controls for a
  /// few seconds, a second back leaves.
  bool _controls = false;
  Timer? _controlsTimer;

  void _showControls() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
    setState(() => _controls = true);
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (_app.fullscreen && !_controls) {
      _showControls();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  List<Widget> _actions(AppLocalizations l10n) => [
    if (_errors > 0)
      Tooltip(
        message: l10n.miniAppsErrors,
        child: IosIconButton(
          icon: Lucide.Bug,
          minSize: 44,
          size: 20,
          color: _freshErrors ? Theme.of(context).colorScheme.error : null,
          onTap: () => unawaited(_showErrors()),
        ),
      ),
    Tooltip(
      message: l10n.miniAppsReload,
      child: IosIconButton(
        icon: Lucide.RefreshCw,
        minSize: 44,
        size: 20,
        onTap: () => unawaited(_controller.reload()),
      ),
    ),
    Tooltip(
      message: l10n.miniAppsMore,
      child: IosIconButton(
        icon: Lucide.Ellipsis,
        minSize: 44,
        size: 20,
        onTap: () => unawaited(_more()),
      ),
    ),
  ];

  Widget _backButton(AppLocalizations l10n) => Tooltip(
    message: l10n.settingsPageBackButton,
    child: IosIconButton(
      icon: Lucide.ArrowLeft,
      minSize: 44,
      size: 22,
      onTap: () => Navigator.of(context).pop(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final web = Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: _app.fullscreen
          ? Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  // Only the display cutout; the system bars are hidden.
                  SafeArea(child: web),
                  _FullscreenControls(
                    visible: _controls,
                    title: _app.name,
                    hint: l10n.miniAppsBackAgainToExit,
                    leading: _backButton(l10n),
                    actions: _actions(l10n),
                  ),
                ],
              ),
            )
          : Scaffold(
              appBar: AppBar(
                leading: _backButton(l10n),
                title: Text(_app.name),
                actions: [..._actions(l10n), const SizedBox(width: 4)],
              ),
              body: web,
            ),
    );
  }
}

/// The app bar of a fullscreen app, shown over it after a back gesture.
class _FullscreenControls extends StatelessWidget {
  const _FullscreenControls({
    required this.visible,
    required this.title,
    required this.hint,
    required this.leading,
    required this.actions,
  });

  final bool visible;
  final String title;
  final String hint;
  final Widget leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(blurRadius: 16, color: Color(0x33000000)),
                ],
              ),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
