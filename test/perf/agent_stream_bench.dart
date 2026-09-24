import "../support/business_test_harness.dart";

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

const _tools = ['shell', 'read_file', 'write_file', 'edit_file', 'list_dir'];

ToolUIPart _tool(int i) {
  final name = _tools[i % _tools.length];
  final out = List.generate(
    12,
    (l) => 'line $l of output for step $i',
  ).join('\n');
  return ToolUIPart(
    id: 't$i',
    toolName: name,
    arguments: {
      'command': 'cd app && ./gradlew test --info $i',
      'path': 'lib/src/module_$i/file_$i.dart',
      'content': 'void main() {}\n' * 20,
    },
    content: out,
    metadata: WorkspaceToolMetadata(
      tool: name,
      status: 'ok',
      path: 'lib/src/module_$i/file_$i.dart',
      command: name == 'shell' ? 'cd app && ./gradlew test --info $i' : null,
      exitCode: name == 'shell' ? 0 : null,
      durationMs: 1200,
      stdoutPreview: name == 'shell' ? out : null,
      diff: name == 'edit_file'
          ? List.generate(
              30,
              (l) => l.isEven ? '+ added $l' : '- gone $l',
            ).join('\n')
          : null,
      added: name == 'edit_file' ? 15 : null,
      removed: name == 'edit_file' ? 15 : null,
      files: name == 'write_file'
          ? [
              WorkspaceToolFile(
                path: '/workspace/lib/src/module_$i/file_$i.dart',
                link: 'kelivo://workspace/lib/src/module_$i/file_$i.dart',
                role: WorkspaceFileRole.created,
              ),
            ]
          : const [],
    ).toJson(),
  );
}

// Explicit benchmark; timings are observations, not regression assertions.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final steps in const [10, 40, 80]) {
    testWidgets('agent stream $steps steps', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final tools = [for (var i = 0; i < steps; i++) _tool(i)];
      // Text between every step, then the answer that keeps growing.
      final segments = [
        for (var i = 0; i < steps; i++)
          'Шаг $i: проверяю **модуль** `module_$i` и запускаю тесты.\n\n',
      ];
      final prefix = segments.join();
      final splits = <int>[];
      var offset = 0;
      for (final s in segments) {
        offset += s.length;
        splits.add(offset);
      }
      final toolCounts = [for (var i = 0; i < steps; i++) i + 1];
      final reasoningCounts = [for (var i = 0; i < steps; i++) 0];

      final content = ValueNotifier(prefix);
      final scroll = ScrollController();
      await tester.pumpWidget(
        _Host(
          content: content,
          scroll: scroll,
          tools: tools,
          splits: splits,
          toolCounts: toolCounts,
          reasoningCounts: reasoningCounts,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();

      final vm = const bool.fromEnvironment('CPU_PROFILE')
          ? await tester.runAsync(() async {
              final info = await developer.Service.getInfo();
              final uri = info.serverUri!;
              final vm = await vmServiceConnectUri(
                uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
              );
              await vm.setFlag('profiler', 'true');
              await vm.clearCpuSamples(
                developer.Service.getIsolateId(Isolate.current)!,
              );
              return vm;
            })
          : null;

      final samples = <int>[];
      for (var i = 0; i < 60; i++) {
        final sw = Stopwatch()..start();
        content.value += i % 10 == 0
            ? '\n\nИтог **раздел** $i: '
            : 'ещё немного текста ответа. ';
        await tester.pump(const Duration(milliseconds: 50));
        sw.stop();
        if (i >= 10) samples.add(sw.elapsedMicroseconds);
      }
      if (vm != null) {
        await tester.runAsync(() async {
          final cpu = await vm.getCpuSamples(
            developer.Service.getIsolateId(Isolate.current)!,
            0,
            1 << 60,
          );
          await File(
            '/tmp/agent-cpu-$steps.json',
          ).writeAsString(jsonEncode(cpu.toJson()));
          await vm.dispose();
        });
      }
      samples.sort();
      var elements = 0;
      void visit(Element e) {
        elements++;
        e.visitChildren(visit);
      }

      tester.element(find.byType(ChatMessageWidget)).visitChildren(visit);
      // ignore: avoid_print
      print(
        'AGENT_STREAM steps=$steps elements=$elements '
        'medianUs=${samples[samples.length ~/ 2]} '
        'p95Us=${samples[(samples.length * .95).floor()]}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      content.dispose();
      scroll.dispose();
    });
  }
}

class _Host extends StatelessWidget {
  const _Host({
    required this.content,
    required this.scroll,
    required this.tools,
    required this.splits,
    required this.toolCounts,
    required this.reasoningCounts,
  });

  final ValueNotifier<String> content;
  final ScrollController scroll;
  final List<ToolUIPart> tools;
  final List<int> splits;
  final List<int> toolCounts;
  final List<int> reasoningCounts;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: ValueListenableBuilder<String>(
              valueListenable: content,
              builder: (_, text, _) => ChatMessageWidget(
                message: ChatMessage(
                  id: 'm1',
                  role: 'assistant',
                  content: text,
                  conversationId: 'c1',
                  isStreaming: true,
                ),
                toolParts: tools,
                contentSplitOffsets: splits,
                toolCountAtSplit: toolCounts,
                reasoningCountAtSplit: reasoningCounts,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
