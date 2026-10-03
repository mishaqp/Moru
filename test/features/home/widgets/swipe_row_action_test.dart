import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/widgets/swipe_row_action.dart';

void main() {
  late int swiped;
  late double outerDrag;

  Future<void> pump(WidgetTester tester) async {
    swiped = 0;
    outerDrag = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Stands in for the drawer, which closes on a leftward drag.
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => outerDrag += d.primaryDelta!,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 48,
                child: SwipeRowAction(
                  icon: Icons.archive,
                  label: 'Archive',
                  onSwiped: () => swiped++,
                  child: const ColoredBox(
                    color: Colors.white,
                    child: Center(child: Text('Row')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a rightward swipe past the threshold runs the action', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(find.text('Row'), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(swiped, 1);
    expect(outerDrag, 0);
  });

  testWidgets('a short rightward swipe springs back', (tester) async {
    await pump(tester);
    await tester.timedDrag(
      find.text('Row'),
      const Offset(50, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(swiped, 0);
    expect(tester.getTopLeft(find.text('Row')).dx, lessThan(150));
  });

  testWidgets('a leftward swipe goes to the widget above', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Row'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(swiped, 0);
    expect(outerDrag, lessThan(-50));
  });
}
