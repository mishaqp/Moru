import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/workspace/task_plan.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/running_tool_bar.dart';
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
              child: ComposerStatusStrip(conversationId: 'c1'),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(TaskPlanChip.toggleKey), findsNothing);

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

    await tester.tap(find.byKey(TaskPlanChip.toggleKey));
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
    expect(find.byKey(TaskPlanChip.toggleKey), findsNothing);
  });

  testWidgets('plan and running command share one row', (tester) async {
    final plans = TaskPlanRegistry()
      ..set('c1', _plan([('Serve', 'in_progress'), ('Check', 'pending')]));
    final runs = ToolRunRegistry();
    final run = runs.start(
      'call-1',
      'shell',
      command: 'python3 -m http.server',
      conversationId: 'c1',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: plans),
          ChangeNotifierProvider.value(value: runs),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ComposerStatusStrip(conversationId: 'c1'),
            ),
          ),
        ),
      ),
    );
    // The live dot pulses forever, so frames are stepped explicitly.
    await tester.pump(const Duration(milliseconds: 300));

    final planBox = tester.getRect(find.byType(TaskPlanChip));
    final runBox = tester.getRect(find.byType(RunningToolChip));
    expect(planBox.top, runBox.top);
    expect(planBox.right, lessThan(runBox.left));
    expect(planBox.width, closeTo(runBox.width, 1));

    run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RunningToolChip), findsNothing);
    // Alone, the plan takes the whole row.
    expect(
      tester.getRect(find.byType(TaskPlanChip)).width,
      runBox.right - planBox.left,
    );
  });
}
