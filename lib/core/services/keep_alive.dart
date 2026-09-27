import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps Moru's process alive with its foreground service while something
/// long-running needs it, e.g. the mini app web server. Its notification
/// shows the holder's text; stopping it there releases every holder.
class ProcessKeepAlive {
  ProcessKeepAlive({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.keep_alive') {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'released') return;
      for (final id in (call.arguments as List).cast<String>()) {
        _released.add(id);
      }
    });
  }

  static final ProcessKeepAlive instance = ProcessKeepAlive();

  final MethodChannel _channel;
  final StreamController<String> _released = StreamController.broadcast();

  /// Holders the user stopped from the notification.
  Stream<String> get released => _released.stream;

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  Future<void> hold(String id, String text) async {
    if (!_android) return;
    await _channel.invokeMethod<void>('hold', {'id': id, 'text': text});
  }

  Future<void> release(String id) async {
    if (!_android) return;
    await _channel.invokeMethod<void>('release', {'id': id});
  }

  /// Wi-Fi multicast, needed to answer mDNS (`moru.local`).
  Future<void> multicast(bool enabled) async {
    if (!_android) return;
    await _channel.invokeMethod<void>('multicast', {'enabled': enabled});
  }
}
