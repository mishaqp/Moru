import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/workspace/task_plan.dart';
import 'package:Kelivo/features/home/widgets/task_plan_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

TaskPlan _plan(List<(String, String)> steps) => TaskPlan.fromArguments({
  'plan': [
    for (final (step, status) in steps) {'step': step, 'status': status},
  ],
})!;

void main() {
  test('parses steps, skips blanks and finds the current one', () {
    final plan = TaskPlan.fromArguments({
      'plan': [
        {'step': 'Read code', 'status': 'completed'},
        {'step': '  ', 'status': 'pending'},
        {'step': 'Fix bug', 'status': 'in_progress'},
        {'step': 'Test', 'status': 'whatever'},
      ],
    })!;
    expect(plan.steps.map((s) => s.text), ['Read code', 'Fix bug', 'Test']);
    expect(plan.steps.last.status, PlanStepStatus.pending);
    expect(plan.completed, 1);
    expect(plan.current?.text, 'Fix bug');
    expect(plan.isDone, isFalse);
    expect(TaskPlan.fromArguments({'plan': []}), isNull);
    expect(TaskPlan.fromArguments({}), isNull);
  });

  testWidgets('shows progress and the current step, expands to the list', (
    tester,
  ) async {
    final plans = TaskPlanRegistry();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: plans,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TaskPlanBar(conversationId: 'c1'),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(TaskPlanBar.toggleKey), findsNothing);

    plans.set(
      'c1',
      _plan([
        ('Read code', 'completed'),
        ('Fix bug', 'in_progress'),
        ('Test', 'pending'),
      ]),
    );
    plans.set('c2', _plan([('Other chat', 'in_progress')]));
    await tester.pumpAndSettle();
    expect(find.text('Plan · 1/3'), findsOneWidget);
    expect(find.text('Fix bug'), findsOneWidget);
    expect(find.text('Test'), findsNothing);
    expect(find.text('Other chat'), findsNothing);

    await tester.tap(find.byKey(TaskPlanBar.toggleKey));
    await tester.pumpAndSettle();
    expect(find.text('Read code'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);

    plans.set(
      'c1',
      _plan([
        ('Read code', 'completed'),
        ('Fix bug', 'completed'),
        ('Test', 'completed'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(TaskPlanBar.toggleKey), findsNothing);
  });
}
