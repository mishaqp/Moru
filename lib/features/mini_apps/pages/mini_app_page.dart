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
import '../../../core/services/mini_apps/mini_app_servers.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../mini_app_display.dart';
import '../mini_app_launcher.dart';
import '../widgets/mini_app_sheets.dart';

/// Runs one installed mini app full screen, with `window.moru` wired to
/// [MiniAppBridge].
class MiniAppPage extends StatefulWidget {
  const MiniAppPage({super.key, required this.app, this._store});

  final MiniApp app;
  final MiniAppStore? _store;

  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> {
  late final WebViewController _controller;
  late final MiniAppBridge _bridge;

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
    _server = _leaseServer(widget.app);
    _bridge = MiniAppBridge(
      store: _store,
      appId: widget.app.id,
      host: MiniAppLauncher.hostFor(
        widget.app,
        context.read<SettingsProvider>(),
        context.read<AssistantProvider>(),
        close: () async {
          if (mounted) Navigator.of(context).pop();
        },
        // The current lease, also after a rollback.
        server: (args) => _server.fetch(args),
      ),
      onProblem: (kind, problem) {
        // The console reports script errors and rejected promises with
        // their details; the page's own report of them is often only
        // "Script error.".
        if (kind == 'error' || kind == 'promise') return;
        _logError(problem);
      },
    );
    // Data the chat changed while the app is open.
    _changes = _store.changes
        .where((change) => change.appId == widget.app.id)
        .listen(
          (change) => unawaited(
            _controller.runJavaScript(MiniAppBridge.changedScript(change.key)),
          ),
        );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Double taps are game input, not zoom.
      ..enableZoom(false)
      ..addJavaScriptChannel(
        'MoruBridge',
        onMessageReceived: (message) => unawaited(_answer(message.message)),
      )
      ..setOnConsoleMessage((message) {
        // Chromium's own line for a missing file; the bridge reports it
        // with the file name.
        if (message.level == JavaScriptLogLevel.error &&
            !message.message.startsWith('Failed to load resource')) {
          _logError('console: ${message.message}');
        }
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            // Pages of the app stay inside; everything else opens outside.
            if (request.url.startsWith('file://')) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null) {
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
    MiniAppDisplay.apply(null, _app);
    unawaited(_load());
  }

  MiniAppServerLease _leaseServer(MiniApp app) => MiniAppLauncher.servers.lease(
    app,
    MiniAppLauncher.serverEnvironment(
      context.read<WorkspaceRuntimeProvider>(),
      context.read<EnvironmentProvider>(),
    ),
  );

  Future<void> _load() async {
    await _store.refreshBridge(_app);
    final errors = await _store.readErrors(_app.id);
    if (mounted && errors.isNotEmpty) setState(() => _errors = errors.length);
    await _controller.loadFile(_app.entryPath);
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
        OptionSheetItem(
          value: 'versions',
          icon: Lucide.History,
          label: l10n.miniAppsVersions,
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
      case 'versions':
        final restored = await showMiniAppVersions(
          context,
          store: _store,
          app: _app,
        );
        if (restored == null || !mounted) return;
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
        await _controller.loadFile(restored.entryPath);
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
    MiniAppDisplay.apply(_app, null);
    unawaited(_server.release());
    _controlsTimer?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _answer(String message) async {
    final script = await _bridge.handle(message);
    if (script == null || !mounted) return;
    await _controller.runJavaScript(script);
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
