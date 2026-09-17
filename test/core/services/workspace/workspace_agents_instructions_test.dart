import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:Kelivo/core/models/workspace.dart';
import 'package:Kelivo/core/models/workspace_binding.dart';
import 'package:Kelivo/core/services/workspace/workspace_agents_instructions.dart';
import 'package:Kelivo/core/services/workspace/workspace_paths.dart';
import 'package:Kelivo/core/services/workspace/workspace_tool_context.dart';

/// Runtime AGENTS.md support for a bound workspace.
///
/// Every case runs against a real temporary directory: the loader only touches
/// the file system, so stubbing it would test nothing.
void main() {
  late Directory temp;
  late Directory workspaceRoot;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('agents-md-test');
    workspaceRoot = Directory(p.join(temp.path, 'workspace'))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  WorkspaceToolContext context({
    required String modelCwd,
    bool sandboxed = true,
    bool skillsOnly = false,
  }) {
    final epoch = DateTime.utc(2026);
    return WorkspaceToolContext(
      workspace: Workspace(
        id: 'workspace-1',
        name: 'Workspace',
        kind: WorkspaceKind.managed,
        createdAt: epoch,
        updatedAt: epoch,
      ),
      binding: const WorkspaceBinding(workspaceId: 'workspace-1'),
      paths: sandboxed
          ? WorkspacePaths.sandboxed(
              workspaceHostRoot: workspaceRoot.path,
              sessionHostDir: p.join(temp.path, 'session'),
              skillsHostDir: p.join(temp.path, 'skills'),
            )
          : WorkspacePaths.native(
              workspaceHostRoot: workspaceRoot.path,
              sessionHostDir: p.join(temp.path, 'session'),
              skillsHostDir: p.join(temp.path, 'skills'),
            ),
      cwd: modelCwd,
      sessionDir: Directory(p.join(temp.path, 'session')),
      outputsDir: Directory(p.join(temp.path, 'session', 'outputs')),
      conversationId: 'conversation-1',
      skillsOnly: skillsOnly,
    );
  }

  void writeRootAgents(String content) {
    File(p.join(workspaceRoot.path, 'AGENTS.md')).writeAsStringSync(content);
  }

  group('workspace AGENTS.md', () {
    test('is injected when it exists', () async {
      writeRootAgents('# Rules\nAlways run the analyzer before pushing.\n');

      final fragment = await WorkspaceAgentsInstructions.build(
        context(modelCwd: '/workspace'),
      );

      expect(fragment, startsWith('<workspace_instructions>'));
      expect(fragment, endsWith('</workspace_instructions>'));
      expect(fragment, contains('AGENTS.md source: /workspace/AGENTS.md'));
      expect(fragment, contains('Always run the analyzer before pushing.'));
      expect(fragment.split('<workspace_instructions>'), hasLength(2));
    });

    test('contributes nothing when it is missing', () async {
      final ctx = context(modelCwd: '/workspace');
      expect(await WorkspaceAgentsInstructions.build(ctx), isEmpty);
      expect(await WorkspaceAgentsInstructions.read(ctx), isEmpty);
    });

    test('ignores an empty or whitespace-only file', () async {
      writeRootAgents('   \n\n\t\n');
      expect(
        await WorkspaceAgentsInstructions.build(
          context(modelCwd: '/workspace'),
        ),
        isEmpty,
      );
    });

    test('skips a file over the size cap but keeps a smaller one', () async {
      writeRootAgents('x' * (WorkspaceAgentsInstructions.maxFileBytes + 1));
      final ctx = context(modelCwd: '/workspace');
      expect(await WorkspaceAgentsInstructions.read(ctx), isEmpty);

      writeRootAgents('y' * WorkspaceAgentsInstructions.maxFileBytes);
      expect(await WorkspaceAgentsInstructions.read(ctx), hasLength(1));
    });

    test('survives an unreadable path and malformed UTF-8', () async {
      // A directory named AGENTS.md cannot be read as a file.
      Directory(p.join(workspaceRoot.path, 'AGENTS.md')).createSync();
      final ctx = context(modelCwd: '/workspace');
      expect(await WorkspaceAgentsInstructions.build(ctx), isEmpty);

      File(p.join(workspaceRoot.path, 'AGENTS.md')).deleteSync(recursive: true);
      File(p.join(workspaceRoot.path, 'AGENTS.md')).writeAsBytesSync(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('# Инструкции\nПроверяй сборку.\n'),
        0xC3,
        0x28,
      ]);
      final files = await WorkspaceAgentsInstructions.read(ctx);
      expect(files, hasLength(1));
      expect(files.single.content, isNot(startsWith('\uFEFF')));
      expect(files.single.content, contains('Проверяй сборку.'));
    });

    test(
      'reads the root file and the working directory file, root first',
      () async {
        writeRootAgents('ROOT-INSTRUCTION\n');
        final nested = Directory(p.join(workspaceRoot.path, 'app', 'ui'))
          ..createSync(recursive: true);
        File(
          p.join(nested.path, 'AGENTS.md'),
        ).writeAsStringSync('NESTED-INSTRUCTION\n');

        final files = await WorkspaceAgentsInstructions.read(
          context(modelCwd: '/workspace/app/ui'),
        );

        expect(files, hasLength(2));
        expect(files.first.content, 'ROOT-INSTRUCTION');
        expect(files.last.content, 'NESTED-INSTRUCTION');
        expect(files.last.modelPath, '/workspace/app/ui/AGENTS.md');
      },
    );

    test('never reads outside the bound workspace', () async {
      final otherRoot = Directory(p.join(temp.path, 'other'))
        ..createSync(recursive: true);
      File(
        p.join(otherRoot.path, 'AGENTS.md'),
      ).writeAsStringSync('OTHER-WORKSPACE\n');
      writeRootAgents('ROOT-INSTRUCTION\n');

      final fragment = await WorkspaceAgentsInstructions.build(
        context(modelCwd: '/workspace'),
      );
      expect(fragment, isNot(contains('OTHER-WORKSPACE')));

      expect(
        await WorkspaceAgentsInstructions.read(
          context(modelCwd: '/workspace/../other'),
        ),
        hasLength(1),
      );
    });

    test('falls back to the root when the cwd is elsewhere', () async {
      writeRootAgents('ROOT-INSTRUCTION\n');
      expect(
        await WorkspaceAgentsInstructions.read(
          context(modelCwd: '/chat/attachments'),
        ),
        hasLength(1),
      );
    });

    test('walks host paths in native (unsandboxed) mode', () async {
      final nested = Directory(p.join(workspaceRoot.path, 'app'))
        ..createSync(recursive: true);
      File(p.join(nested.path, 'AGENTS.md')).writeAsStringSync('NATIVE\n');

      final files = await WorkspaceAgentsInstructions.read(
        context(modelCwd: p.join(workspaceRoot.path, 'app'), sandboxed: false),
      );
      expect(files, hasLength(1));
      expect(
        files.single.hostPath,
        p.join(workspaceRoot.path, 'app', 'AGENTS.md'),
      );
      expect(files.single.modelPath, files.single.hostPath);
    });

    test('is never consulted for a skills-only context', () async {
      writeRootAgents('ROOT-INSTRUCTION\n');
      expect(
        await WorkspaceAgentsInstructions.build(
          context(modelCwd: '/workspace', skillsOnly: true),
        ),
        isEmpty,
      );
    });

    test('caps how many files one request may inject', () async {
      writeRootAgents('ROOT\n');
      expect(
        await WorkspaceAgentsInstructions.read(
          context(modelCwd: '/workspace'),
          maxFileCount: 0,
        ),
        isEmpty,
      );
    });

    test('builds a stable fragment when a file has no trailing newline', () {
      final fragment = WorkspaceAgentsInstructions.buildFragment(const [
        WorkspaceAgentsFile(
          hostPath: '/tmp/AGENTS.md',
          modelPath: '/workspace/AGENTS.md',
          content: 'no trailing newline',
        ),
      ]);
      expect(
        fragment,
        endsWith('no trailing newline\n</workspace_instructions>'),
      );
      expect(WorkspaceAgentsInstructions.buildFragment(const []), isEmpty);
    });
  });
}
