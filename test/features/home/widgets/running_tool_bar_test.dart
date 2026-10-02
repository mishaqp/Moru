import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
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
            generating: false,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows only this conversation\'s running command', (
    tester,
  ) async {
    final registry = ToolRunRegistry();
    final runtime = WorkspaceRuntimeProvider()..register(_RecordingRuntime());
    registry.start('other', 'shell', command: 'sleep 9', conversationId: 'c2');

    await tester.pumpWidget(_host(registry: registry, runtime: runtime));
    expect(find.byKey(ComputerStatusPanel.stopKey), findsNothing);

    final run = registry.start(
      'call-1',
      'shell',
      command: 'npm install\necho done',
      conversationId: 'c1',
      runtimeRunId: 'run-1',
    );
    // The live dot pulses forever, so frames are stepped explicitly.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('npm install'), findsOneWidget);
    expect(find.text('sleep 9'), findsNothing);

    run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('npm install'), findsNothing);
  });

  testWidgets('stop cancels every owned runtime once with reused call IDs', (
    tester,
  ) async {
    final registry = ToolRunRegistry();
    final fake = _RecordingRuntime();
    final runtime = WorkspaceRuntimeProvider()..register(fake);
    registry.start(
      'call-1',
      'shell',
      command: 'make',
      conversationId: 'c1',
      runtimeRunId: 'run-1',
    );
    registry.start(
      'call-1',
      'shell',
      command: 'second command',
      conversationId: 'c1',
      runtimeRunId: 'run-2',
    );
    registry.start(
      'call-1',
      'shell',
      command: 'another chat',
      conversationId: 'c2',
      runtimeRunId: 'other-run',
    );

    await tester.pumpWidget(_host(registry: registry, runtime: runtime));
    expect(find.text('second command'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
    await tester.pump();
    await tester.tap(find.byKey(ComputerStatusPanel.stopKey));
    await tester.pump();

    expect(fake.cancelled, ['run-1', 'run-2']);
  });

  testWidgets('counts other runs of the same conversation', (tester) async {
    final registry = ToolRunRegistry();
    final runtime = WorkspaceRuntimeProvider()..register(_RecordingRuntime());
    registry.start('a', 'shell', command: 'first', conversationId: 'c1');
    registry.start('b', 'shell', command: 'second', conversationId: 'c1');

    await tester.pumpWidget(_host(registry: registry, runtime: runtime));
    expect(find.text('second'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('shows the latest output line live', (tester) async {
    final registry = ToolRunRegistry();
    final runtime = WorkspaceRuntimeProvider()..register(_RecordingRuntime());
    final run = registry.start(
      'call-1',
      'shell',
      command: 'npm install',
      conversationId: 'c1',
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
    expect(tail(), isEmpty);

    run.appendStdout(Uint8List.fromList(utf8.encode('step 16\nstep 17\n\n')));
    await tester.pump(ToolRun.notifyInterval);
    expect(tail(), contains('step 17'));

    run.appendStderr(Uint8List.fromList(utf8.encode('warn: slow')));
    await tester.pump(ToolRun.notifyInterval);
    expect(tail(), contains('warn: slow'));

    run.complete(status: ToolRunStatus.succeeded, exitCode: 0);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
