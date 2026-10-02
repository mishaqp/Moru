import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/features/chat/widgets/computer_sheet.dart';
import 'package:Kelivo/features/home/widgets/composer_status_strip.dart';
import 'package:Kelivo/features/home/widgets/computer_status_panel.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/fake_workspace_runtime.dart';

class _RecordingRuntime extends FakeWorkspaceRuntime {
  final List<String> cancelled = <String>[];

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    await super.cancel(runId);
  }
}

Widget _host({
  required ToolRunRegistry registry,
  required WorkspaceRuntimeProvider runtime,
  String? conversationId = 'c1',
  String? responseId = 'reply',
  bool generating = true,
  List<ComputerStep>? steps,
  VoidCallback? onStop,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ToolRunRegistry>.value(value: registry),
      ChangeNotifierProvider<WorkspaceRuntimeProvider>.value(value: runtime),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComposerStatusStrip(
            conversationId: conversationId,
            responseId: responseId,
            generating: generating,
            steps: steps,
            onStop: onStop,
          ),
        ),
      ),
    ),
  );
}

void _disposeAfterTest(
  WidgetTester tester,
  ToolRunRegistry registry,
  WorkspaceRuntimeProvider runtime,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final run in registry.all) {
      run.dispose();
    }
    registry.dispose();
    runtime.dispose();
  });
}

void main() {
  testWidgets('shows only this conversation\'s running command', (
    tester,
  ) async {
    final registry = ToolRunRegistry();
    final runtime = WorkspaceRuntimeProvider()..register(_RecordingRuntime());
    _disposeAfterTest(tester, registry, runtime);
    registry.start(
      'other',
      'shell',
      command: 'sleep 9',
      conversationId: 'c2',
      responseId: 'reply',
    );

    await tester.pumpWidget(_host(registry: registry, runtime: runtime));
    expect(find.byKey(ComputerStatusPanel.stopKey), findsNothing);

    final run = registry.start(
      'call-1',
      'shell',
      command: 'npm install\necho done',
      conversationId: 'c1',
      responseId: 'reply',
      runtimeRunId: 'run-1',
    );
    // The live dot pulses forever, so frames are stepped explicitly.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('npm install'), findsOneWidget);
    expect(find.text('sleep 9'), findsNothing);

    run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    await tester.pumpWidget(
      _host(
        registry: registry,
        runtime: runtime,
        generating: false,
        steps: [
          ComputerStep(
            id: 'call-1',
            toolName: 'shell',
            arguments: {'command': 'npm install\necho done'},
            content: 'finished',
            run: run,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('npm install'), findsNothing);
    expect(find.text('Done · 1 action'), findsOneWidget);
    expect(tester.getSize(find.byKey(ComputerStatusPanel.panelKey)).height, 48);
    expect(find.byKey(ComputerStatusPanel.stopKey), findsNothing);
  });

  testWidgets(
    'generation Stop delegates once without cancelling runtime jobs',
    (tester) async {
      final registry = ToolRunRegistry();
      final fake = _RecordingRuntime();
      final runtime = WorkspaceRuntimeProvider()..register(fake);
      _disposeAfterTest(tester, registry, runtime);
      final background = registry.start(
        'call-1',
        'shell',
        command: 'background server',
        conversationId: 'c1',
        responseId: 'previous-reply',
        background: true,
        runtimeRunId: 'background-run',
      );
      final first = registry.start(
        'call-1',
        'shell',
        command: 'make',
        conversationId: 'c1',
        responseId: 'reply',
        runtimeRunId: 'run-1',
      );
      final second = registry.start(
        'call-1',
        'shell',
        command: 'second command',
        conversationId: 'c1',
        responseId: 'reply',
        runtimeRunId: 'run-2',
      );
      final other = registry.start(
        'call-1',
        'shell',
        command: 'another chat',
        conversationId: 'c2',
        responseId: 'reply',
        runtimeRunId: 'other-run',
      );

      var stopped = 0;
      await tester.pumpWidget(
        _host(registry: registry, runtime: runtime, onStop: () => stopped++),
      );
      expect(find.text('second command'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
      await tester.pump();
      await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
      await tester.pump();

      expect(stopped, 1);
      expect(fake.cancelled, isEmpty);
      expect(
        tester
            .widget<IconButton>(find.byKey(ComputerStatusPanel.stopKey))
            .onPressed,
        isNull,
      );
      // Runtime cancellation belongs to generation/job control, rather than the
      // compositor enumerating every process sharing a conversation.
      expect(first.status, ToolRunStatus.running);
      expect(second.status, ToolRunStatus.running);
      expect(other.status, ToolRunStatus.running);
      expect(background.status, ToolRunStatus.running);
    },
  );

  testWidgets('counts other runs of the same conversation', (tester) async {
    final registry = ToolRunRegistry();
    final runtime = WorkspaceRuntimeProvider()..register(_RecordingRuntime());
    _disposeAfterTest(tester, registry, runtime);
    registry.start(
      'a',
      'shell',
      command: 'first',
      conversationId: 'c1',
      responseId: 'reply',
    );
    registry.start(
      'b',
      'shell',
      command: 'second',
      conversationId: 'c1',
      responseId: 'reply',
    );
    registry.start(
      'c',
      'shell',
      command: 'another response',
      conversationId: 'c1',
      responseId: 'later-reply',
    );

    await tester.pumpWidget(_host(registry: registry, runtime: runtime));
    expect(find.text('second'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('another response'), findsNothing);
  });

  testWidgets('shows the latest output line live', (tester) async {
    final registry = ToolRunRegistry();
    final runtime = WorkspaceRuntimeProvider()..register(_RecordingRuntime());
    _disposeAfterTest(tester, registry, runtime);
    final run = registry.start(
      'call-1',
      'shell',
      command: 'npm install',
      conversationId: 'c1',
      responseId: 'reply',
    );

    await tester.pumpWidget(_host(registry: registry, runtime: runtime));
    final thumbnail = find.byKey(
      ValueKey('computer-step-thumbnail:${run.runtimeRunId}'),
    );
    expect(thumbnail, findsOneWidget);
    String tail() => tester
        .widgetList<Text>(
          find.descendant(of: thumbnail, matching: find.byType(Text)),
        )
        .map((text) => text.data ?? '')
        .join('\n');
    expect(tail(), r'$ npm install');

    run.appendStdout(Uint8List.fromList(utf8.encode('step 16\nstep 17\n\n')));
    await tester.pump(ToolRun.notifyInterval);
    expect(tail(), contains('step 17'));

    run.appendStderr(Uint8List.fromList(utf8.encode('warn: slow')));
    await tester.pump(ToolRun.notifyInterval);
    expect(tail(), contains('warn: slow'));
    expect(tail(), contains('step 17'));

    run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    await tester.pumpWidget(
      _host(
        registry: registry,
        runtime: runtime,
        generating: false,
        steps: [
          ComputerStep(
            id: 'call-1',
            toolName: 'shell',
            arguments: {'command': 'npm install'},
            run: run,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Done · 1 action'), findsOneWidget);
    expect(thumbnail, findsNothing);
    expect(find.byKey(ComputerStatusPanel.stopKey), findsNothing);
    await tester.tap(find.byKey(ComputerStatusPanel.panelKey));
    await tester.pumpAndSettle();
    final result = find.descendant(
      of: find.byType(ComputerSheet),
      matching: find.byKey(const ValueKey('computer-step-result')),
    );
    expect(tester.widget<Text>(result).data, contains('step 17'));
    expect(tester.widget<Text>(result).data, contains('warn: slow'));
    expect(find.text('AI is working…'), findsNothing);
  });
}
