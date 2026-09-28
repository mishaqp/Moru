/// Which composer placeholder to show: the plain one until the field is
/// focused again, then the next tip on each focus, so the empty field tells
/// what Moru can do. Focus, not a timer, drives it: that is when the user
/// looks at the field.
class ComposerHintRotation {
  ComposerHintRotation(this.count) : assert(count > 0);

  final int count;
  int _index = 0;
  bool _focusedOnce = false;

  /// Index into the hints; 0 is the plain placeholder.
  int get index => _index;

  /// The field gained focus. With a screen reader the hint stays put, since
  /// a changing label is announced again. Returns whether it changed.
  bool focused({required bool screenReader}) {
    if (!_focusedOnce) {
      // The first focus keeps the plain line that says what the field is.
      _focusedOnce = true;
      return false;
    }
    if (screenReader || count < 2) return false;
    _index = (_index + 1) % count;
    return true;
  }

  /// Another chat opened: start over from the plain placeholder.
  void reset() {
    _index = 0;
    _focusedOnce = false;
  }
}
