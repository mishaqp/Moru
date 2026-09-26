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
import '../../../shared/widgets/snackbar.dart';
import '../mini_app_launcher.dart';

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
    await _store.refreshBridge(widget.app);
    await _controller.loadFile(widget.app.entryPath);
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _answer(String message) async {
    final script = await _bridge.handle(message);
    if (!mounted) return;
    await _controller.runJavaScript(script);
  }

  Future<void> _pin() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await MiniAppLauncher.pinShortcut(widget.app);
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
          title: Text(widget.app.name),
          actions: [
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
              message: l10n.miniAppsAddToHomeScreen,
              child: IosIconButton(
                icon: Lucide.Smartphone,
                minSize: 44,
                size: 20,
                onTap: () => unawaited(_pin()),
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
