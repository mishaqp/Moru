import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/mini_apps/mini_app_bridge.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
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
    _bridge = MiniAppBridge(
      store: _store,
      appId: widget.app.id,
      host: MiniAppLauncher.hostFor(
        widget.app,
        context.read<SettingsProvider>(),
        context.read<AssistantProvider>(),
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
    unawaited(_load());
  }

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
        setState(() {
          _app = restored;
          _errors = 0;
          _freshErrors = false;
          _logged = 0;
          _loading = true;
        });
        await _controller.loadFile(restored.entryPath);
      case 'errors':
        await _showErrors();
      case 'pin':
        await _pin();
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Tooltip(
            message: l10n.settingsPageBackButton,
            child: IosIconButton(
              icon: Lucide.ArrowLeft,
              minSize: 44,
              size: 22,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          title: Text(_app.name),
          actions: [
            if (_errors > 0)
              Tooltip(
                message: l10n.miniAppsErrors,
                child: IosIconButton(
                  icon: Lucide.Bug,
                  minSize: 44,
                  size: 20,
                  color: _freshErrors
                      ? Theme.of(context).colorScheme.error
                      : null,
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
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}
