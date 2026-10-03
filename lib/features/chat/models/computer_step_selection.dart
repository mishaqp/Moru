import 'computer_step.dart';

/// Selection follows the newest active step. A manual selection stays pinned
/// across updates only while that same step is still running.
class ComputerStepSelection {
  List<ComputerStep> _steps = const [];
  String? _selectedId;
  String? _pinnedId;
  bool _browsingCompleted = false;
  bool _hadRunning = false;

  int get index => _selectedId == null
      ? -1
      : _steps.indexWhere((step) => step.id == _selectedId);

  ComputerStep? get selected {
    final selectedIndex = index;
    return selectedIndex < 0 ? null : _steps[selectedIndex];
  }

  void update(List<ComputerStep> steps) {
    final sameIds =
        _steps.length == steps.length &&
        Iterable<int>.generate(
          steps.length,
        ).every((i) => _steps[i].id == steps[i].id);
    final hasRunning = steps.any((step) => step.isRunning);
    final keepCompletedSelection =
        _browsingCompleted &&
        !_hadRunning &&
        !hasRunning &&
        sameIds &&
        steps.any((step) => step.id == _selectedId);
    _steps = List.unmodifiable(steps);
    _hadRunning = hasRunning;
    if (keepCompletedSelection) return;
    final pinned = _steps.indexWhere((step) => step.id == _pinnedId);
    if (pinned >= 0 && _steps[pinned].isRunning) {
      _selectedId = _pinnedId;
      return;
    }
    _pinnedId = null;
    _browsingCompleted = false;
    _followLatest();
  }

  void select(int index) {
    if (index < 0 || index >= _steps.length) return;
    final step = _steps[index];
    _selectedId = step.id;
    _pinnedId = step.isRunning ? step.id : null;
    _browsingCompleted = !step.isRunning;
  }

  void latest() {
    _pinnedId = null;
    _browsingCompleted = false;
    _followLatest();
  }

  void _followLatest() {
    if (_steps.isEmpty) {
      _selectedId = null;
      return;
    }
    final runningIndex = _steps.lastIndexWhere((step) => step.isRunning);
    _selectedId =
        _steps[runningIndex < 0 ? _steps.length - 1 : runningIndex].id;
  }
}
