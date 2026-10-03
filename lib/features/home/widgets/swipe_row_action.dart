import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/services/haptics.dart';

/// A row that runs [onSwiped] when it is swiped to the right past a third of
/// its width, e.g. to archive a chat. Only a rightward swipe is claimed: a
/// leftward one goes on to the widgets above, so the sidebar still closes
/// with a swipe over its list.
class SwipeRowAction extends StatefulWidget {
  const SwipeRowAction({
    super.key,
    required this.child,
    required this.icon,
    required this.label,
    required this.onSwiped,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final IconData icon;
  final String label;
  final VoidCallback onSwiped;
  final bool enabled;
  final BorderRadius borderRadius;

  /// Part of the width a swipe must cover to count.
  static const double threshold = 0.3;

  @override
  State<SwipeRowAction> createState() => _SwipeRowActionState();
}

class _SwipeRowActionState extends State<SwipeRowAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset;
  double _width = 1;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: double.infinity,
      value: 0,
    );
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    final next = (_offset.value + details.primaryDelta!).clamp(0.0, _width);
    _offset.value = next;
    final armed = next >= _width * SwipeRowAction.threshold;
    if (armed != _armed) {
      _armed = armed;
      if (armed) Haptics.light();
    }
  }

  Future<void> _end(DragEndDetails details) async {
    final fling = (details.primaryVelocity ?? 0) > 700;
    final done = _armed || fling;
    _armed = false;
    if (!done) {
      await _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _offset.animateTo(
      _width,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeIn,
    );
    widget.onSwiped();
    // The row usually leaves the list; if it stays, it slides back.
    if (mounted) _offset.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth : 1;
        return RawGestureDetector(
          gestures: {
            _RightSwipeRecognizer:
                GestureRecognizerFactoryWithHandlers<_RightSwipeRecognizer>(
                  () => _RightSwipeRecognizer(debugOwner: this),
                  (recognizer) => recognizer
                    ..onUpdate = _update
                    ..onEnd = (details) => _end(details),
                ),
          },
          child: AnimatedBuilder(
            animation: _offset,
            child: widget.child,
            builder: (context, child) {
              final dx = _offset.value;
              if (dx == 0) return child!;
              final progress = (dx / (_width * SwipeRowAction.threshold)).clamp(
                0.0,
                1.0,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(
                          alpha: 0.10 + 0.14 * progress,
                        ),
                        borderRadius: widget.borderRadius,
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      child: Opacity(
                        opacity: progress,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.icon, size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              widget.label,
                              style: TextStyle(color: cs.primary, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(offset: Offset(dx, 0), child: child),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// A horizontal drag that bows out as soon as the finger heads left, so a
/// drag recognizer further up (the drawer's) gets leftward swipes.
class _RightSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _RightSwipeRecognizer({super.debugOwner});

  final Map<int, double> _travel = {};
  final Set<int> _accepted = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _travel[event.pointer] = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && !_accepted.contains(event.pointer)) {
      final travel = (_travel[event.pointer] ?? 0) + event.delta.dx;
      _travel[event.pointer] = travel;
      // A couple of pixels of jitter do not count as heading left.
      if (travel < -2) {
        resolvePointer(event.pointer, GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  void acceptGesture(int pointer) {
    _accepted.add(pointer);
    super.acceptGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _travel.clear();
    _accepted.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}
