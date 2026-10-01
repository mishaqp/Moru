import 'dart:async';

import 'package:Kelivo/core/services/keep_alive.dart';

/// A native-resource boundary for tests that do not load Android channels.
/// Process lifetime and cancellation remain driven by the real Dart owners.
class FakeProcessKeepAlive implements ProcessKeepAlive {
  final holds = <String>[];
  final releases = <String>[];
  final held = <String>{};
  final _released = StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get released => _released.stream;

  @override
  Future<void> hold(String id, String text) async {
    holds.add(id);
    held.add(id);
  }

  @override
  Future<void> release(String id) async {
    releases.add(id);
    held.remove(id);
  }

  void stop(String id) {
    held.remove(id);
    _released.add(id);
  }

  @override
  Future<void> multicast(bool enabled) async {}

  Future<void> dispose() => _released.close();
}
