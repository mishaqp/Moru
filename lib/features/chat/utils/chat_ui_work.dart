import 'dart:developer' as developer;

/// Optional synchronous-work observations for explicit benchmarks and tests.
/// The observer and timing are disabled in release builds.
abstract final class ChatUiWork {
  static void Function(String name, String? messageId, int microseconds)?
  debugObserver;

  static T measure<T>(String name, T Function() work, {String? messageId}) {
    void Function(String, String?, int)? observer;
    assert(() {
      observer = debugObserver;
      return true;
    }());
    if (observer == null) return work();
    final watch = Stopwatch()..start();
    developer.Timeline.startSync(name);
    try {
      return work();
    } finally {
      developer.Timeline.finishSync();
      observer!(name, messageId, watch.elapsedMicroseconds);
    }
  }
}
