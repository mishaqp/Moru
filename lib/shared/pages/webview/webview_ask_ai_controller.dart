import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../features/home/services/browser_ask_ai_bridge.dart';

/// Visible states of the merged bottom panel's Ask-AI composer (see
/// AGENTS.md section 3). [idle] is the default/rest state (ready for a
/// question) and is not itself one of the seven task-visible states below,
/// which this controller must make each individually reachable and
/// distinguishable:
///  - [starting]: submitted, no sign of work yet.
///  - [running]: the agent has started acting in the browser.
///  - [awaitingApproval]: a `browser_use` approval is pending for this
///    session -- the approval card (section 4) takes over display.
///  - [stopping]: the user tapped Stop; cancellation requested, no outcome
///    yet. Must never look like [stopped] or [completed] -- nothing is
///    actually done until the matching outcome arrives.
///  - [completed]: an `ok: true` outcome arrived; hands off to the result
///    card, then returns to [idle].
///  - [stopped]: a `cancelled: true` outcome arrived.
///  - [error]: an `ok: false, cancelled: false` outcome arrived.
enum AskAiPanelState {
  idle,
  starting,
  running,
  awaitingApproval,
  stopping,
  completed,
  stopped,
  error,
}

/// Drives the bottom panel's Ask-AI state machine, decoupled from
/// `BuildContext` so it is unit-testable on its own. One instance per
/// browser page: the shell creates it, forwards session activity and
/// approval-pending signals into it, watches it for the widget tree, and
/// disposes it (which also cancels its single `bridge.outcomes`
/// subscription -- there is exactly one, so closing the page never leaves a
/// dangling listener).
///
/// This is the single source of truth for "does this browser page have an
/// active Ask-AI request of its own" ([activeRequestId]), which is what
/// section 7's close-time cancellation and the stale-callback audit key
/// off of.
class AskAiPanelController extends ChangeNotifier {
  AskAiPanelController({
    required this.bridge,
    this.completedHoldDuration = const Duration(milliseconds: 900),
  }) {
    _outcomeSub = bridge.outcomes.listen(_onOutcome);
  }

  final BrowserAskAiBridge bridge;
  final Duration completedHoldDuration;

  StreamSubscription<BrowserAskAiOutcome>? _outcomeSub;
  Timer? _completedTimer;
  bool _disposed = false;

  AskAiPanelState _state = AskAiPanelState.idle;
  AskAiPanelState get state => _state;

  String? _activeRequestId;
  String? get activeRequestId => _activeRequestId;

  bool _pendingApproval = false;
  bool get pendingApproval => _pendingApproval;

  /// The most recent outcome this controller has seen for its own request,
  /// kept until the next [submit] or [dismiss]. The shell reads this once
  /// (e.g. to build a result card or read an error message) -- it is not
  /// cleared by the controller's own transient "completed" -> "idle" timer,
  /// only by starting a new request or an explicit [dismiss].
  BrowserAskAiOutcome? lastOutcome;

  bool get isBusy =>
      _activeRequestId != null &&
      _state != AskAiPanelState.error &&
      _state != AskAiPanelState.stopped;

  /// Submits [text]. Returns the new request id, or null when [text] is
  /// blank or a request is already in flight -- the same guard the send
  /// button's disabled state reflects, so a double tap (even one that beats
  /// the next frame) can never submit twice.
  String? submit(String text, {String? pageUrl}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isBusy) return null;
    _completedTimer?.cancel();
    lastOutcome = null;
    final id = bridge.submit(trimmed, pageUrl: pageUrl);
    _activeRequestId = id;
    _setState(AskAiPanelState.starting);
    return id;
  }

  /// Call whenever the shared browser session records a new `browser_use`
  /// activity, so [AskAiPanelState.starting] can advance to
  /// [AskAiPanelState.running] once there is a real sign of work rather than
  /// guessing from a timer.
  void noteActivity() {
    if (_activeRequestId != null && _state == AskAiPanelState.starting) {
      _setState(AskAiPanelState.running);
    }
  }

  /// Reflects whether a `browser_use` approval is currently pending for
  /// this session. While true, the approval card takes over the panel's
  /// display slot (section 4); this only tracks the state so the panel
  /// never also renders itself as "running" underneath it.
  void setPendingApproval(bool pending) {
    if (_pendingApproval == pending) return;
    _pendingApproval = pending;
    if (_activeRequestId == null) return;
    if (pending) {
      if (_state == AskAiPanelState.starting ||
          _state == AskAiPanelState.running) {
        _setState(AskAiPanelState.awaitingApproval);
      }
    } else if (_state == AskAiPanelState.awaitingApproval) {
      _setState(AskAiPanelState.running);
    }
  }

  /// Requests cancellation of the in-flight request. Idempotent: calling
  /// this again while already [AskAiPanelState.stopping] does nothing, so a
  /// double stop-tap issues at most one `bridge.cancel`. Never touches
  /// navigation or the browser session -- Stop only ever cancels this
  /// page's own Ask-AI request.
  void stop() {
    final id = _activeRequestId;
    if (id == null || _state == AskAiPanelState.stopping) return;
    bridge.cancel(id);
    _setState(AskAiPanelState.stopping);
  }

  /// Cancels the active request, if any, with no state transition -- used
  /// when the browser page itself is closing for an unrelated reason (a
  /// manual close or `browser_use: close`), so nothing keeps running
  /// invisibly after the UI is gone. A safe no-op when there is no active
  /// request (e.g. `browser_use: close` while no Ask-AI task is running).
  void cancelForClose() {
    final id = _activeRequestId;
    if (id == null) return;
    bridge.cancel(id);
  }

  /// Dismisses a terminal ([AskAiPanelState.error] or
  /// [AskAiPanelState.stopped]) state, returning to [AskAiPanelState.idle]
  /// so the composer is ready for a new question. A no-op in any other
  /// state.
  void dismiss() {
    if (_state != AskAiPanelState.error && _state != AskAiPanelState.stopped) {
      return;
    }
    _activeRequestId = null;
    lastOutcome = null;
    _setState(AskAiPanelState.idle);
  }

  void _onOutcome(BrowserAskAiOutcome outcome) {
    if (outcome.requestId != _activeRequestId) return;
    lastOutcome = outcome;
    _activeRequestId = null;
    if (outcome.cancelled) {
      _setState(AskAiPanelState.stopped);
    } else if (outcome.ok) {
      _setState(AskAiPanelState.completed);
      _completedTimer?.cancel();
      _completedTimer = Timer(completedHoldDuration, () {
        if (_disposed) return;
        if (_state == AskAiPanelState.completed) {
          _setState(AskAiPanelState.idle);
        }
      });
    } else {
      _setState(AskAiPanelState.error);
    }
  }

  void _setState(AskAiPanelState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _completedTimer?.cancel();
    _outcomeSub?.cancel();
    super.dispose();
  }
}
