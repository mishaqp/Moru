import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/models/computer_step_selection.dart';
import 'package:flutter_test/flutter_test.dart';

ComputerStep step(String id, {bool running = false}) =>
    ComputerStep(id: id, toolName: 'shell', loading: running);

void main() {
  test('empty and new replies select the newest running step', () {
    final selection = ComputerStepSelection();
    selection.update([]);
    expect(selection.index, -1);
    expect(selection.selected, isNull);
    selection.update([
      step('first', running: true),
      step('second', running: true),
      step('done'),
    ]);
    expect(selection.selected!.id, 'second');
    selection.update([
      step('first', running: true),
      step('second', running: true),
      step('third', running: true),
    ]);
    expect(selection.selected!.id, 'third');
  });

  test('manual running selection stays pinned by id across reordering', () {
    final selection = ComputerStepSelection();
    selection.update([step('a', running: true), step('b', running: true)]);
    selection.select(0);
    selection.update([
      step('inserted'),
      step('a', running: true),
      step('b', running: true),
      step('c', running: true),
    ]);
    expect(selection.index, 1);
    expect(selection.selected!.id, 'a');
    selection.update([
      step('inserted'),
      step('a'),
      step('b', running: true),
      step('c', running: true),
    ]);
    expect(selection.selected!.id, 'c');
  });

  test('latest clears the pin and resumes following work', () {
    final selection = ComputerStepSelection();
    selection.update([step('a', running: true), step('b', running: true)]);
    selection.select(0);
    selection.latest();
    expect(selection.selected!.id, 'b');
    selection.update([
      step('a', running: true),
      step('b', running: true),
      step('c', running: true),
    ]);
    expect(selection.selected!.id, 'c');
  });

  test('reply finishing selects the newest result and releases manual pin', () {
    final selection = ComputerStepSelection();
    selection.update([step('a', running: true), step('b', running: true)]);
    selection.select(0);
    selection.update([step('a'), step('b'), step('final')]);
    expect(selection.selected!.id, 'final');
    selection.select(0);
    expect(selection.selected!.id, 'a');
    selection.update([step('a'), step('b'), step('new', running: true)]);
    expect(selection.selected!.id, 'new');
  });

  test(
    'browsing a completed response stays selected through unchanged refreshes',
    () {
      final selection = ComputerStepSelection();
      selection.update([step('a'), step('b')]);
      selection.select(0);
      selection.update([step('a'), step('b')]);
      expect(selection.selected!.id, 'a');
      selection.update([step('a'), step('b'), step('new')]);
      expect(selection.selected!.id, 'new');
    },
  );

  test(
    'removing the selected step falls back safely and invalid selections do nothing',
    () {
      final selection = ComputerStepSelection();
      selection.update([step('a', running: true), step('b', running: true)]);
      selection.select(0);
      selection.update([step('b', running: true)]);
      expect(selection.selected!.id, 'b');
      selection.select(-1);
      selection.select(2);
      expect(selection.index, 0);
      selection.update([]);
      expect(selection.index, -1);
      expect(selection.selected, isNull);
    },
  );
}
