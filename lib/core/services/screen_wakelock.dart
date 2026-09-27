import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the mobile screen awake while conversation generation is in flight.
///
/// Reference-counted: [acquire]/[release] track concurrent conversations.
/// The last release starts a 10s debounce before the platform lock is dropped.
/// [hold]/[unhold] keep the screen on regardless of the setting, e.g. while a
/// mini app that asked for it is open.
/// Calls are fire-and-forget; platform errors are swallowed.
class ScreenWakelock {
  ScreenWakelock._();

  static bool _enabled = false;
  static int _holders = 0;
  static int _forced = 0;
  static bool _held = false;
  static Timer? _releaseTimer;
  static const Duration _releaseDelay = Duration(seconds: 10);

  /// Test hook. When set, [WakelockPlus] is never touched.
  ///
  /// May be sync or return a [Future]; async errors roll back [_held].
  @visibleForTesting
  static FutureOr<void> Function(bool enable)? debugPlatformApply;

  static void setEnabled(bool v) {
    _enabled = v;
    if (!v) {
      _applyRelease();
    } else {
      _apply();
    }
  }

  static void acquire() {
    _holders++;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _apply();
  }

  static void release() {
    if (_holders > 0) {
      _holders--;
    }
    if (_holders == 0) {
      _scheduleRelease();
    }
  }

  /// Keeps the screen on until the matching [unhold], whatever the setting.
  static void hold() {
    _forced++;
    _setPlatformHeld(true);
  }

  static void unhold() {
    if (_forced > 0) _forced--;
    if (_forced == 0 && !(_enabled && _holders > 0)) {
      // A pending generation release keeps its own timer.
      if (_releaseTimer == null) _setPlatformHeld(false);
    }
  }

  static void releaseNow() {
    _holders = 0;
    _applyRelease();
  }

  /// Re-apply the platform lock after resume (window flags can be lost).
  static void reassert() {
    if (_forced == 0 && (!_enabled || _holders <= 0)) return;
    _applyPlatformHeld(true);
  }

  static void _apply() {
    if (_enabled && _holders > 0) {
      _setPlatformHeld(true);
    }
  }

  static void _applyRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (_forced == 0) _setPlatformHeld(false);
  }

  static void _scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_releaseDelay, _applyRelease);
  }

  static void _setPlatformHeld(bool held) {
    if (_held == held) return;
    _applyPlatformHeld(held);
  }

  /// Optimistically updates [_held], then reverts it if the platform Future
  /// fails so a later [_setPlatformHeld] / [reassert] can retry.
  static void _applyPlatformHeld(bool held) {
    final previous = _held;
    _held = held;
    _invokePlatform(
      held,
      onError: () {
        if (_held == held) {
          _held = previous;
        }
      },
    );
  }

  static void _invokePlatform(bool enable, {void Function()? onError}) {
    final hook = debugPlatformApply;
    if (hook != null) {
      try {
        final result = hook(enable);
        if (result is Future<void>) {
          _safe(() => result, onError: onError);
        }
      } catch (_) {
        onError?.call();
      }
      return;
    }
    if (!_isMobile) return;
    _safe(
      () => enable ? WakelockPlus.enable() : WakelockPlus.disable(),
      onError: onError,
    );
  }

  static void _safe(
    Future<void> Function() action, {
    void Function()? onError,
  }) {
    try {
      unawaited(
        action().catchError((Object _) {
          onError?.call();
        }),
      );
    } catch (_) {
      onError?.call();
    }
  }

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get _isMobile => _isAndroid;

  @visibleForTesting
  static bool get debugEnabled => _enabled;

  @visibleForTesting
  static int get debugHolders => _holders;

  @visibleForTesting
  static int get debugForced => _forced;

  @visibleForTesting
  static bool get debugHeld => _held;

  @visibleForTesting
  static void debugReset({void Function(bool enable)? platformApply}) {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _enabled = false;
    _holders = 0;
    _forced = 0;
    _held = false;
    debugPlatformApply = platformApply;
  }
}
