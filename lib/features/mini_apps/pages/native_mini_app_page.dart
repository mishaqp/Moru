import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/mini_apps/mini_app_manifest.dart';
import '../../../core/services/mini_apps/mini_app_runtime.dart';
import '../../../core/services/mini_apps/mini_app_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../home/services/tool_approval_service.dart';
import '../mini_app_launcher.dart';
import '../mini_app_permissions_sheet.dart';
import '../widgets/native_mini_app_panel.dart';

/// Native declarative apps have no WebView, server lease or background process.
class NativeMiniAppPage extends StatefulWidget {
  const NativeMiniAppPage({
    super.key,
    required this.app,
    this.store,
    this.runtime,
  });

  final MiniApp app;
  final MiniAppStore? store;
  final MiniAppRuntime? runtime;

  @override
  State<NativeMiniAppPage> createState() => _NativeMiniAppPageState();
}

class _NativeMiniAppPageState extends State<NativeMiniAppPage>
    with WidgetsBindingObserver {
  late final MiniAppRuntime _runtime =
      widget.runtime ?? MiniAppLauncher.runtime;
  late final MiniAppStore _store = widget.store ?? _runtime.store;
  late MiniApp _app = widget.app;
  late final String _scope =
      'mini-app-page:${_app.id}:${identityHashCode(this)}';
  ToolApprovalService? _approvals;
  StreamSubscription<Map<String, dynamic>>? _watch;
  Map<String, dynamic>? _screen;
  Map<String, dynamic> _state = const {};
  Map<String, dynamic>? _result;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  int _read = 0;
  bool _background = false;
  bool _detached = false;
  Completer<void> _lifetime = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_storeChanged);
    _startWatch();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _approvals = context.read<ToolApprovalService>();
    } catch (_) {}
  }

  bool _owns(MiniApp app) =>
      mounted &&
      !_detached &&
      !_lifetime.isCompleted &&
      identical(_app, app) &&
      identical(_store.byId(app.id), app);

  bool _fullTrust() {
    if (!mounted) return false;
    try {
      return context.read<SettingsProvider>().toolAutoApproveAll;
    } catch (_) {
      return false;
    }
  }

  MiniAppInvocation _invocation(MiniApp app) => MiniAppInvocation(
    source: MiniAppInvocationSource.button,
    cancelled: _lifetime.future,
    isAllowed: () => _owns(app),
    fullTrust: _fullTrust,
    approve: (app, action, args) async {
      final approvals = _approvals;
      if (approvals == null || !_owns(app)) return false;
      return requestMiniAppActionApproval(
        context,
        app: app,
        action: action,
        arguments: args,
        isActive: () => _owns(app),
        scope: _scope,
        approvals: approvals,
      );
    },
  );

  void _startWatch() {
    if (_watch != null || _background || !_owns(_app)) return;
    _watch = _runtime.watch(_app.id, _acceptState);
  }

  void _acceptState(Map<String, dynamic> state) {
    if (!mounted) return;
    setState(() {
      if (state['status'] != null && state['data'] == null) {
        _result = state;
      } else {
        _state = state;
      }
    });
  }

  Future<void> _load() async {
    final app = _app;
    final read = ++_read;
    if (mounted) setState(() => _loading = true);
    try {
      final entry = File(app.entryPath);
      if (await entry.length() > 256 * 1024) throw const FormatException();
      final screen = jsonDecode(await entry.readAsString());
      MiniAppManifest.validateScreen(screen, app.actions);
      final state = await _runtime.state(app.id, invocation: _invocation(app));
      if (!_owns(app) || read != _read) return;
      setState(() {
        _screen = Map<String, dynamic>.from(screen as Map);
        _loadError = null;
        _loading = false;
      });
      _acceptState(state);
    } catch (_) {
      if (mounted && read == _read) {
        setState(() {
          _loading = false;
          _loadError = _store.byId(app.id) == null ? 'not_found' : 'failed';
        });
      }
    }
  }

  Future<void> _refresh() async {
    final app = _app;
    try {
      final state = await _runtime.state(app.id, invocation: _invocation(app));
      if (_owns(app)) _acceptState(state);
    } catch (_) {
      if (mounted) setState(() => _result = {'status': 'failed'});
    }
  }

  Future<void> _action(String name, Map<String, dynamic> args) async {
    if (_busy) return;
    final app = _app;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await _runtime.execute(
        app.id,
        name,
        args,
        invocation: _invocation(app),
      );
      if (!_owns(app)) return;
      if (result['state'] case final Map state) {
        _acceptState(Map<String, dynamic>.from(state));
      }
      setState(() => _result = result);
    } catch (_) {
      if (_owns(app)) setState(() => _result = {'status': 'failed'});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _storeChanged() {
    final app = _store.byId(_app.id);
    if (identical(app, _app)) return;
    ++_read;
    if (!_lifetime.isCompleted) _lifetime.complete();
    _approvals?.cancelForConversation(_scope);
    if (app == null || app.uiEngine != MiniAppUiEngine.native) {
      final watch = _watch;
      _watch = null;
      unawaited(watch?.cancel());
      if (mounted) {
        setState(() {
          _screen = null;
          _loading = false;
          _loadError = 'not_found';
        });
      }
      return;
    }
    _app = app;
    _lifetime = Completer<void>();
    _state = const {};
    _result = null;
    _startWatch();
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _background = false;
      _detached = false;
      if (_lifetime.isCompleted && identical(_store.byId(_app.id), _app)) {
        _lifetime = Completer<void>();
      }
      _startWatch();
      unawaited(_refresh());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _background = true;
      if (state == AppLifecycleState.detached) {
        _detached = true;
        if (!_lifetime.isCompleted) _lifetime.complete();
        _approvals?.cancelForConversation(_scope);
      }
      final watch = _watch;
      _watch = null;
      unawaited(watch?.cancel());
    }
  }

  String _status(AppLocalizations l10n, Map<String, dynamic> result) {
    if (result['code'] == 'restore_pending') {
      return l10n.miniAppsNativeRestorePending;
    }
    if (result['partial'] == true) return l10n.miniAppsNativePartial;
    if (result['conflicts'] is List &&
        (result['conflicts'] as List).isNotEmpty) {
      return l10n.miniAppsNativeRestoreConflict;
    }
    if (result['steps'] is List && (result['steps'] as List).isEmpty) {
      return l10n.miniAppsNativeNothingToRestore;
    }
    return switch (result['status']) {
      'applied' => l10n.miniAppsNativeApplied,
      'opened_settings' => l10n.miniAppsNativeOpenedSettings,
      'permission_required' => l10n.miniAppsNativePermissionRequired,
      'unsupported' => l10n.miniAppsNativeUnsupported,
      'denied' => l10n.miniAppsNativeDenied,
      'unknown_after_timeout' => l10n.miniAppsNativeTimeout,
      'nothing_to_restore' => l10n.miniAppsNativeNothingToRestore,
      'conflict' => l10n.miniAppsNativeRestoreConflict,
      _ => l10n.miniAppsNativeActionError,
    };
  }

  String _stepLabel(AppLocalizations l10n, Object? handler) =>
      switch (handler) {
        'device.screen.brightness.set' => l10n.miniAppsPermissionScreenWrite,
        'device.screen.timeout.set' => l10n.phonePanelScreenTimeout,
        'device.audio.volume.set' => l10n.phonePanelSound,
        'device.audio.dnd.set' => l10n.phonePanelDnd,
        'device.root.dnd.set' => l10n.miniAppsPermissionRootDnd,
        'device.flashlight.set' => l10n.phonePanelFlashlight,
        'device.root.power_save.set' => l10n.miniAppsPermissionRootPowerSave,
        'device.root.wifi.set' => l10n.miniAppsPermissionRootWifi,
        'device.root.bluetooth.set' => l10n.miniAppsPermissionRootBluetooth,
        'device.root.data.set' => l10n.miniAppsPermissionRootData,
        'device.root.airplane.set' => l10n.miniAppsPermissionRootAirplane,
        _ => l10n.miniAppsNativeActionError,
      };

  Widget _feedback(AppLocalizations l10n, Map<String, dynamic> result) {
    final cs = Theme.of(context).colorScheme;
    final message = result['message'];
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _status(l10n, result),
              style: TextStyle(
                color:
                    result['status'] == 'applied' && result['partial'] != true
                    ? cs.onSurface
                    : cs.error,
              ),
            ),
          ),
          if (result['partial'] == true &&
              result['conflicts'] is List &&
              (result['conflicts'] as List).isNotEmpty)
            Text(l10n.miniAppsNativeRestoreConflict),
          if (result['steps'] case final List steps)
            for (final step in steps)
              if (step is Map)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_stepLabel(l10n, step['handler'])}: ${_status(l10n, Map<String, dynamic>.from(step))}',
                  ),
                ),
          if (message is String && message.isNotEmpty)
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                title: Text(l10n.computerMoreDetails),
                children: [SelectableText(message)],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    ++_read;
    if (!_lifetime.isCompleted) _lifetime.complete();
    _store.removeListener(_storeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _approvals?.cancelForConversation(_scope);
    unawaited(_watch?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localizedTitle = NativeMiniAppPanel.localizedText(
      _screen?['title'],
      Localizations.localeOf(context),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(localizedTitle.isEmpty ? _app.name : localizedTitle),
        actions: [
          IosIconButton(
            icon: LucideIcons.shieldCheck,
            minSize: 48,
            tooltip: l10n.miniAppsPermissionsTitle,
            onTap: () => showMiniAppPermissions(
              context,
              app: _app,
              runtime: _runtime,
              store: _store,
            ),
          ),
          IosIconButton(
            icon: LucideIcons.refreshCw,
            minSize: 48,
            tooltip: l10n.phoneControlRefresh,
            onTap: () => _loadError == null ? _refresh() : _load(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_loadError != null)
                      Text(
                        _loadError == 'not_found'
                            ? l10n.miniAppsNotFound
                            : l10n.miniAppsNativeLoadError,
                      ),
                    if (_result != null) ...[
                      Material(
                        type: MaterialType.transparency,
                        child: _feedback(l10n, _result!),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                    if (_screen != null)
                      NativeMiniAppPanel(
                        screen: _screen!,
                        state: _state,
                        busy: _busy,
                        onAction: _action,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
