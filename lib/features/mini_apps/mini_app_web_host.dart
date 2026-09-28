import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/providers/assistant_provider.dart';
import '../../core/providers/environment_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/keep_alive.dart';
import '../../core/services/mdns_responder.dart';
import '../../core/services/mini_apps/mini_app_bridge.dart';
import '../../core/services/mini_apps/mini_app_servers.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../core/services/mini_apps/mini_app_web_server.dart';
import '../../core/services/workspace/workspace_runtime.dart';
import '../../l10n/app_localizations.dart';
import 'mini_app_launcher.dart';

/// The "Web server" of My Apps: serves the mini apps to browsers in the
/// Wi-Fi (or on this phone), answers `moru.local`, and keeps Moru alive
/// while it runs.
class MiniAppWebHost extends ChangeNotifier {
  MiniAppWebHost({
    MiniAppStore? store,
    ProcessKeepAlive? keepAlive,
    Future<List<InternetAddress>> Function()? localAddresses,
    this.mdnsName = 'moru',
  }) : _store = store ?? MiniAppStore.instance,
       _keepAlive = keepAlive ?? ProcessKeepAlive.instance,
       _localAddresses = localAddresses ?? _wifiAddresses {
    _released = _keepAlive.released.listen((id) {
      if (id == keepAliveId) unawaited(stop());
    });
  }

  static final MiniAppWebHost instance = MiniAppWebHost();

  static const String keepAliveId = 'mini-app-web';

  final MiniAppStore _store;
  final ProcessKeepAlive _keepAlive;
  final Future<List<InternetAddress>> Function() _localAddresses;
  final String mdnsName;
  late final StreamSubscription<String> _released;

  MiniAppWebServer? _server;
  MdnsResponder? _mdns;
  final List<MiniAppServerLease> _leases = [];

  bool _busy = false;
  String? _error;
  List<String> _urls = const [];

  bool get running => _server?.running ?? false;
  bool get busy => _busy;

  /// Why the last start failed: [errorNoPassword], [errorPortInUse] or a
  /// system message.
  String? get error => _error;

  static const String errorNoPassword = 'no_password';
  static const String errorPortInUse = 'port_in_use';

  /// Where browsers reach it, the most convenient first.
  List<String> get urls => _urls;

  Future<void> start({
    required SettingsProvider settings,
    required AssistantProvider assistants,
    required MiniAppServerEnvironment environment,
    required String Function(String url) notificationText,
  }) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _stopAll();
      final password = settings.miniAppWebPasswordEnabled
          ? settings.miniAppWebPassword
          : null;
      if (password != null && password.isEmpty) {
        throw const MiniAppException(
          errorNoPassword,
          'Set a password or turn the password off.',
        );
      }
      final port = settings.miniAppWebPort;
      final localhostOnly = settings.miniAppWebLocalhostOnly;
      final server = MiniAppWebServer(
        store: _store,
        bridgeFor: (app) {
          final lease = MiniAppLauncher.servers.lease(app, environment);
          _leases.add(lease);
          return MiniAppBridge(
            store: _store,
            appId: app.id,
            host: MiniAppLauncher.hostFor(
              app,
              settings,
              assistants,
              server: lease.fetch,
            ),
          );
        },
      );
      await server.start(
        port: port,
        localhostOnly: localhostOnly,
        password: password,
      );
      _server = server;
      final urls = <String>[];
      if (!localhostOnly) {
        final addresses = await _localAddresses();
        if (addresses.isNotEmpty) {
          try {
            await _keepAlive.multicast(true);
            final mdns = MdnsResponder(
              MdnsZone(
                hostName: mdnsName,
                address: addresses.first,
                httpPort: port,
              ),
            );
            await mdns.start();
            _mdns = mdns;
            urls.add('http://${mdns.zone.host}:$port');
          } catch (e) {
            // The addresses below still work without the name.
            debugPrint('[MiniAppWeb] mDNS unavailable: $e');
          }
        }
        urls.addAll([for (final a in addresses) 'http://${a.address}:$port']);
      }
      urls.add('http://127.0.0.1:$port');
      _urls = urls;
      await _keepAlive.hold(keepAliveId, notificationText(urls.first));
    } on SocketException catch (e) {
      // EADDRINUSE: 98 on Linux/Android, 48 elsewhere; -1 when this
      // process already listens there.
      final code = e.osError?.errorCode;
      _error = code == 98 || code == 48 || code == -1
          ? errorPortInUse
          : e.message;
      await _stopAll();
    } on MiniAppException catch (e) {
      _error = e.code;
      await _stopAll();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// [start] with the providers and texts of [context].
  Future<void> startFrom(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return start(
      settings: context.read<SettingsProvider>(),
      assistants: context.read<AssistantProvider>(),
      environment: MiniAppLauncher.serverEnvironment(
        context.read<WorkspaceRuntimeProvider>(),
        context.read<EnvironmentProvider>(),
      ),
      notificationText: l10n.miniAppsWebNotification,
    );
  }

  Future<void> stop() async {
    await _stopAll();
    notifyListeners();
  }

  Future<void> _stopAll() async {
    final server = _server;
    _server = null;
    _urls = const [];
    await server?.stop();
    if (_mdns != null) {
      _mdns!.stop();
      _mdns = null;
      await _keepAlive.multicast(false).catchError((_) {});
    }
    for (final lease in List.of(_leases)) {
      await lease.release();
    }
    _leases.clear();
    if (server != null) {
      await _keepAlive.release(keepAliveId).catchError((_) {});
    }
  }

  @override
  void dispose() {
    unawaited(_released.cancel());
    unawaited(_stopAll());
    super.dispose();
  }

  /// IPv4 addresses of this phone in local networks, Wi-Fi first.
  static Future<List<InternetAddress>> _wifiAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    interfaces.sort(
      (a, b) =>
          (b.name.startsWith('wlan') ? 1 : 0) -
          (a.name.startsWith('wlan') ? 1 : 0),
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback) address,
    ];
  }
}
