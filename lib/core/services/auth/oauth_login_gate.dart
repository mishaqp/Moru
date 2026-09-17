import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/provider_oauth.dart';
import '../network/request_logger.dart';
import 'oauth_cancellation.dart';
import 'oauth_pkce.dart';

/// Interactive login must not spend its HTTP timeout while Android blocks the
/// background app. This observes the app's default network; it never binds or
/// bypasses the user's VPN, proxy, DNS or certificate checks.
class OAuthLoginGate with WidgetsBindingObserver {
  OAuthLoginGate(this.cancellation, {bool? isAndroid})
    : _android = isAndroid ?? Platform.isAndroid {
    if (_android) {
      _binding = WidgetsBinding.instance;
      _binding!.addObserver(this);
    }
    unawaited(cancellation.whenCancelled.then((_) => close()));
  }

  static const _channel = MethodChannel('app.oauth.network');
  final OAuthCancellation cancellation;
  final bool _android;
  final _stopped = Completer<void>();
  WidgetsBinding? _binding;
  Completer<void>? _resumed;
  String? _waitId;
  Future<void>? _closing;

  void _check() {
    cancellation.check();
    if (_stopped.isCompleted) {
      throw const ProviderOAuthException(ProviderOAuthFailure.cancelled);
    }
  }

  Future<void> _untilStopped(Future<void> operation) async {
    await Future.any([operation, cancellation.whenCancelled, _stopped.future]);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final resumed = _resumed;
      _resumed = null;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
    }
  }

  Future<void> wait() async {
    _check();
    if (!_android) return;
    while (true) {
      while (_binding!.lifecycleState != AppLifecycleState.resumed) {
        RequestLogger.logLine('[OAUTH] login wait-foreground');
        _resumed ??= Completer<void>();
        await _untilStopped(_resumed!.future);
      }
      _check();
      final id = oauthRandomString(18);
      _waitId = id;
      try {
        RequestLogger.logLine('[OAUTH] login wait-network');
        await _untilStopped(
          _channel.invokeMethod<void>('awaitNetwork', {
            'id': id,
            'timeoutMillis': const Duration(minutes: 15).inMilliseconds,
          }),
        );
      } on PlatformException catch (error) {
        _check();
        throw ProviderOAuthException(
          error.code == 'network_timeout'
              ? ProviderOAuthFailure.timeout
              : ProviderOAuthFailure.network,
          code: error.code == 'network_timeout'
              ? 'login/network-timeout'
              : 'login/network-unavailable',
        );
      } on MissingPluginException {
        throw const ProviderOAuthException(
          ProviderOAuthFailure.network,
          code: 'login/network-service-unavailable',
        );
      } finally {
        if (_waitId == id) _waitId = null;
      }
      _check();
      // A browser or another activity could regain focus during the native wait.
      if (_binding!.lifecycleState == AppLifecycleState.resumed) return;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _stopped.complete();
    _binding?.removeObserver(this);
    final id = _waitId;
    _waitId = null;
    if (id != null) {
      try {
        await _channel.invokeMethod<void>('cancelNetworkWait', {'id': id});
      } catch (_) {
        RequestLogger.logLine('[OAUTH] login network-cleanup-failed');
      }
    }
  }
}
