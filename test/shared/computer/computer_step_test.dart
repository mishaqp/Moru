import 'dart:convert';

import 'package:Kelivo/core/services/acp/acp_secret_redactor.dart';
import 'package:Kelivo/core/services/api/tool_display_redaction.dart';
import 'package:Kelivo/core/services/workspace/tool_run_registry.dart';
import 'package:Kelivo/features/chat/models/computer_step.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations_en.dart';
import 'package:Kelivo/l10n/app_localizations_ru.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies browser, foreground and background commands, and files', () {
    for (final name in ['browser_use', 'mcp__moru__browser_use']) {
      expect(
        ComputerStep(id: name, toolName: name).kind,
        ComputerStepKind.browser,
      );
    }
    for (final name in [
      'shell',
      'shell_output',
      'root_shell',
      'exec_command',
      'write_stdin',
      'Bash',
      'bash_code_execution',
    ]) {
      expect(
        ComputerStep(id: name, toolName: name).kind,
        ComputerStepKind.command,
      );
    }
    for (final name in [
      'read_file',
      'write_file',
      'edit_file',
      'list_dir',
      'glob',
      'grep',
      'Read',
      'Write',
      'Edit',
      'apply_patch',
    ]) {
      expect(
        ComputerStep(id: name, toolName: name).kind,
        ComputerStepKind.file,
      );
    }
    expect(
      ComputerStep(id: 'plan', toolName: 'update_plan').kind,
      ComputerStepKind.tool,
    );
    expect(
      ComputerStep(id: 'other', toolName: 'custom_tool').kind,
      ComputerStepKind.tool,
    );
  });

  test('recognizes typed images without inferring attachments inside JSON', () {
    final image = ComputerStep(
      id: 'image',
      toolName: 'custom_tool',
      metadata: {
        kMcpResultMetadataKey: mcpResultMetadata(['/images/chart.png']),
      },
    );
    expect(image.kind, ComputerStepKind.image);
    expect(image.imagePath, '/images/chart.png');
    expect(
      ComputerStep(
        id: 'read',
        toolName: 'read_file',
        arguments: {'path': '/workspace/a.png'},
      ).kind,
      ComputerStepKind.file,
    );
    final text = ComputerStep(
      id: 'text',
      toolName: 'custom_tool',
      content: '{"text":"![](fake.png)"}',
    );
    expect(text.kind, ComputerStepKind.tool);
    expect(text.imagePath, isNull);
  });

  test(
    'file image attachments retain file actions and expose image previews',
    () {
      final step = ComputerStep(
        id: 'read-image',
        toolName: 'read_file',
        arguments: {'path': '/workspace/plot.png'},
        metadata: {
          kMcpResultMetadataKey: mcpResultMetadata([
            'data:image/png;base64,AA==',
          ]),
        },
      );
      expect(step.kind, ComputerStepKind.file);
      expect(step.imagePath, 'data:image/png;base64,AA==');
      expect(step.actionPath, '/workspace/plot.png');
    },
  );

  test('browser screenshot stays browser and exposes its typed image', () {
    final step = ComputerStep(
      id: 'browser',
      toolName: 'browser_use',
      content: '{"ok":true,"screenshot":"attached"}',
      metadata: {
        kMcpResultMetadataKey: mcpResultMetadata([
          '/images/browser/shot-1.jpg',
        ]),
      },
    );
    expect(step.kind, ComputerStepKind.browser);
    expect(step.imagePath, '/images/browser/shot-1.jpg');
  });

  test('live run status and tail take precedence over the stored snapshot', () {
    final run = ToolRun(
      toolCallId: 'job',
      toolName: 'shell',
      command: 'npm test',
    );
    addTearDown(run.dispose);
    final step = ComputerStep(
      id: 'poll',
      toolName: 'shell_output',
      arguments: {'job_id': run.runtimeRunId},
      content: '{"status":"running"}',
      loading: true,
      run: run,
    );
    run.appendStdout(utf8.encode('first\nprogress'));
    expect(step.kind, ComputerStepKind.command);
    expect(step.command, 'npm test');
    expect(step.isRunning, isTrue);
    expect(step.result, 'first\nprogress');
    run.complete(status: ToolRunStatus.failed, exitCode: 1);
    expect(step.isRunning, isFalse);
    expect(step.isError, isTrue);
  });

  test(
    'restored statuses recognize errors and still-running background jobs',
    () {
      expect(
        ComputerStep(
          id: 'background',
          toolName: 'shell',
          content: '{"job_id":"job","status":"running"}',
        ).isRunning,
        isTrue,
      );
      expect(
        ComputerStep(
          id: 'failed',
          toolName: 'browser_use',
          content: '{"ok":false,"error":"navigation_failed"}',
        ).isError,
        isTrue,
      );
      expect(
        ComputerStep(
          id: 'failed',
          toolName: 'shell',
          metadata: {
            'workspace': {'status': 'error', 'exitCode': 2},
          },
        ).isError,
        isTrue,
      );
      expect(
        ComputerStep(
          id: 'ok',
          toolName: 'browser_use',
          content: '{"ok":true,"found":false}',
        ).isError,
        isFalse,
      );
    },
  );

  test(
    'file previews use first content lines and titles use the file name',
    () {
      final step = ComputerStep(
        id: 'write',
        toolName: 'write_file',
        arguments: {
          'path': '/workspace/lib/main.dart',
          'content': 'first\nsecond\nthird',
        },
        content: '{"ok":true}',
      );
      expect(step.path, '/workspace/lib/main.dart');
      expect(step.actionPath, '/workspace/lib/main.dart');
      expect(step.preview, 'first\nsecond\nthird');
      expect(step.title(AppLocalizationsEn()), 'Write · main.dart (+3 lines)');
      expect(step.parameters, contains('"path"'));
    },
  );

  test(
    'command titles show the filtered command rather than the tool name',
    () {
      final step = ComputerStep(
        id: 'shell-title',
        toolName: 'shell',
        arguments: {'command': 'npm run build'},
      );
      expect(step.title(AppLocalizationsEn()), 'npm run build');
    },
  );

  test('background shell previews show output or command without job JSON', () {
    final step = ComputerStep(
      id: 'background-preview',
      toolName: 'shell',
      arguments: {'command': 'npm run dev', 'background': true},
      content: '{"background":true,"job_id":"job","status":"running"}',
    );
    expect(step.preview, r'$ npm run dev');
  });

  test('file previews omit bookkeeping JSON when no content is available', () {
    final step = ComputerStep(
      id: 'file-preview',
      toolName: 'read_file',
      arguments: {'path': '/workspace/file.md'},
      content: '{"ok":true,"size":42}',
    );
    expect(step.preview, isEmpty);
  });

  test('command detail and copy retain the full bounded live output', () {
    final run = ToolRun(toolCallId: 'full-output', toolName: 'shell');
    addTearDown(run.dispose);
    final output = List.generate(
      100,
      (index) => '$index ${'x' * 60}',
    ).join('\n');
    run.appendStdout(utf8.encode(output));
    final step = ComputerStep(id: 'full-output', toolName: 'shell', run: run);
    expect(step.result, output);
    expect(step.preview.split('\n'), hasLength(4));
  });

  test(
    'command detail keeps all retained output beyond the live tail window',
    () {
      final run = ToolRun(toolCallId: 'many-lines', toolName: 'shell');
      addTearDown(run.dispose);
      final output = List.generate(300, (index) => 'line $index').join('\n');
      run.appendStdout(utf8.encode(output));
      run.appendStderr(utf8.encode('stderr retained'));
      final step = ComputerStep(id: 'many-lines', toolName: 'shell', run: run);
      expect(run.stdoutSoFar, output);
      expect(step.result, '$output\nstderr retained');
      expect(step.result, startsWith('line 0\n'));
      expect(step.result, contains('line 299'));
    },
  );

  test('command thumbnail preserves the chronology of stdout and stderr', () {
    final run = ToolRun(toolCallId: 'mixed-tail', toolName: 'shell');
    addTearDown(run.dispose);
    run.appendStderr(utf8.encode('older error\n'));
    run.appendStdout(utf8.encode('newer output\nlatest output'));
    final step = ComputerStep(id: 'mixed-tail', toolName: 'shell', run: run);
    expect(step.preview, 'older error\nnewer output\nlatest output');
  });

  test('plan titles show checklist progress and a checklist icon', () {
    final step = ComputerStep(
      id: 'plan-title',
      toolName: 'update_plan',
      arguments: {
        'plan': [
          {'step': 'Inspect', 'status': 'completed'},
          {'step': 'Build', 'status': 'in_progress'},
        ],
      },
    );
    expect(step.title(AppLocalizationsEn()), 'Plan · 1/2');
    expect(step.icon, Lucide.ListChecks);
  });

  test('browser title includes only the safe domain', () {
    final step = ComputerStep(
      id: 'browser-title',
      toolName: 'browser_use',
      arguments: {'action': 'navigate', 'url': 'https://example.com/docs'},
    );
    expect(step.title(AppLocalizationsEn()), 'Browser · example.com');
  });

  test('failed shell subtitle keeps its exit code and localized duration', () {
    final step = ComputerStep(
      id: 'exit-subtitle',
      toolName: 'shell',
      metadata: {
        'workspace': {'status': 'error', 'exitCode': 2, 'durationMs': 3400},
      },
    );
    expect(step.subtitle(AppLocalizationsRu()), 'Код выхода 2 · 3,4 с');
  });

  test(
    'persisted stopped metadata takes precedence over a pending snapshot',
    () {
      final step = ComputerStep(
        id: 'stopped-plan',
        toolName: 'update_plan',
        loading: true,
        metadata: {
          'computer': {'status': 'stopped'},
        },
      );
      expect(step.isRunning, isFalse);
    },
  );

  test(
    'display copies redact launch secrets and preserve execution inputs',
    () async {
      const secret = 'private-provider-value';
      final args = <String, dynamic>{
        'command': 'echo $secret',
        'extra': {'token': 'sk-test-secret-value'},
      };
      final metadata = <String, dynamic>{
        'workspace': {'command': 'echo $secret', 'stdoutPreview': secret},
      };
      final redactor = AcpSecretRedactor([secret]);
      final step =
          await ToolDisplayRedaction(
            text: redactor.text,
            value: redactor.value,
          ).run(
            () async => ComputerStep(
              id: 'redacted',
              toolName: 'shell',
              arguments: args,
              metadata: metadata,
              content: secret,
            ),
          );
      expect(step.command, isNot(contains(secret)));
      expect(step.parameters, isNot(contains(secret)));
      expect(step.result, isNot(contains(secret)));
      expect(step.parameters, isNot(contains('sk-test-secret-value')));
      expect(args['command'], 'echo $secret');
      expect((metadata['workspace'] as Map)['stdoutPreview'], secret);
      (args['extra'] as Map)['later'] = 'changed';
      expect(step.parameters, isNot(contains('changed')));
    },
  );

  test(
    'live output uses the launch display filter captured by the snapshot',
    () async {
      const secret = 'private-live-secret';
      final run = ToolRun(
        toolCallId: 'live',
        toolName: 'shell',
        command: 'echo $secret',
      );
      addTearDown(run.dispose);
      final redactor = AcpSecretRedactor([secret]);
      final step = await ToolDisplayRedaction(
        text: redactor.text,
        value: redactor.value,
      ).run(() async => ComputerStep(id: 'live', toolName: 'shell', run: run));
      run.appendStdout(utf8.encode('new $secret\n'));
      expect(step.command, isNot(contains(secret)));
      expect(step.result, isNot(contains(secret)));
      expect(run.tailLines.single, contains(secret));
    },
  );

  test('run created in a launch zone filters a later UI snapshot', () async {
    const secret = 'opaque-launch-value-123';
    final redactor = AcpSecretRedactor([secret]);
    final run =
        await ToolDisplayRedaction(
          text: redactor.text,
          value: redactor.value,
        ).run(
          () async => ToolRun(
            toolCallId: 'late-ui',
            toolName: 'shell',
            command: 'echo $secret',
          ),
        );
    addTearDown(run.dispose);
    run.appendStdout(utf8.encode('stdout $secret\n'));
    expect(ToolDisplayRedaction.current, isNull);
    final step = ComputerStep(
      id: 'late-ui',
      toolName: 'shell',
      arguments: {'command': 'echo $secret'},
      content: 'result $secret',
      metadata: {
        'workspace': {'command': 'echo $secret', 'stdoutPreview': secret},
      },
      run: run,
    );
    expect(step.command, isNot(contains(secret)));
    expect(step.parameters, isNot(contains(secret)));
    expect(step.result, isNot(contains(secret)));
    expect(step.content, isNot(contains(secret)));
    expect(jsonEncode(step.metadata), isNot(contains(secret)));
    expect(run.displayText('result $secret'), isNot(contains(secret)));
    expect(
      run.displayValue({'secret': secret}).toString(),
      isNot(contains(secret)),
    );
    expect(run.command, 'echo $secret');
    expect(run.tailLines.single, contains(secret));
  });

  test(
    'withRun filters late display data and retains a blocked file action',
    () async {
      const secret = 'REDACTED';
      final redactor = AcpSecretRedactor([secret]);
      final display = ToolDisplayRedaction(
        text: redactor.text,
        value: redactor.value,
      );
      final original = await display.run(
        () async => ComputerStep(
          id: 'copy',
          toolName: 'read_file',
          arguments: {'path': '/workspace/$secret.txt'},
        ),
      );
      final run = await display.run(
        () async => ToolRun(toolCallId: 'copy', toolName: 'shell'),
      );
      addTearDown(run.dispose);
      run.appendStdout(utf8.encode('new $secret\n'));
      final copy = original.withRun(run);
      expect(copy.actionPath, isNull);
      expect(copy.result, isNot(contains(secret)));
      expect(copy.id, original.id);
      expect(copy.run, same(run));
      expect(original.run, isNull);

      final outsideZone = ComputerStep(
        id: 'late',
        toolName: 'shell',
        arguments: {'command': 'echo $secret'},
        content: 'result $secret',
      );
      final attached = outsideZone.withRun(run);
      expect(attached.parameters, isNot(contains(secret)));
      expect(attached.content, isNot(contains(secret)));
      expect(attached.result, isNot(contains(secret)));
    },
  );

  test(
    'auth URLs and credential fields are removed from display and actions',
    () {
      const auth =
          'https://auth.openai.com/authorize?state=private&code=private-code';
      final step = ComputerStep(
        id: 'auth',
        toolName: 'browser_use',
        arguments: {'url': auth, 'device_code': 'ABCD-EFGH'},
        content: 'Navigate to $auth',
        metadata: {
          kMcpResultMetadataKey: mcpResultMetadata([auth]),
        },
      );
      expect(step.parameters, isNot(contains(auth)));
      expect(step.parameters, isNot(contains('ABCD-EFGH')));
      expect(step.result, isNot(contains('private-code')));
      expect(step.imagePath, isNull);
      expect(step.allowsBrowserPreview, isFalse);
      expect(computerActionUri(auth), isNull);
      expect(computerActionUri('https://user:secret@example.com'), isNull);
      expect(
        computerActionUri('https://example.com/page?q=normal'),
        Uri.parse('https://example.com/page?q=normal'),
      );
      expect(computerActionUri('file:///workspace/a.html'), isNull);
    },
  );

  test('public pages remain eligible for browser fallback thumbnails', () {
    final step = ComputerStep(
      id: 'public',
      toolName: 'browser_use',
      arguments: {'url': 'https://example.com/page?q=normal'},
      content: '{"ok":true,"url":"https://example.com/page?q=normal"}',
    );
    expect(step.allowsBrowserPreview, isTrue);
    final alreadyFiltered = ComputerStep(
      id: 'filtered',
      toolName: 'browser_use',
      arguments: {'url': '[REDACTED]'},
    );
    expect(alreadyFiltered.allowsBrowserPreview, isFalse);
    final opaque = ComputerStep(
      id: 'opaque-filtered',
      toolName: 'browser_use',
      arguments: {'url': '■'},
    );
    expect(opaque.allowsBrowserPreview, isFalse);
  });

  test(
    'legacy and standalone browser image results retain auth exclusions',
    () {
      const auth = 'https://auth.openai.com/authorize?code=private-legacy-code';
      final body = jsonEncode({'ok': true, 'url': auth});
      final envelope = encodeLegacyMcpToolResultEnvelope(
        text: body,
        imageUris: ['/images/browser/shot-legacy.jpg'],
      );
      for (final (content, metadata) in <(String, Map<String, dynamic>?)>[
        (envelope, null),
        ('$body\n![](/images/browser/shot-legacy.jpg)', null),
        (
          envelope,
          {
            kMcpResultMetadataKey: mcpResultMetadata([
              '/images/browser/shot-legacy.jpg',
            ]),
          },
        ),
      ]) {
        final step = ComputerStep(
          id: 'legacy',
          toolName: 'browser_use',
          content: content,
          metadata: metadata,
        );
        expect(step.allowsBrowserPreview, isFalse);
        expect(step.imagePath, isNull);
        expect(step.result, isNot(contains('private-legacy-code')));
      }
    },
  );

  test('redacted paths are not offered as a file open target', () async {
    const secret = 'private-path-secret';
    final redactor = AcpSecretRedactor([secret]);
    final step =
        await ToolDisplayRedaction(
          text: redactor.text,
          value: redactor.value,
        ).run(
          () async => ComputerStep(
            id: 'path',
            toolName: 'read_file',
            arguments: {'path': '/workspace/$secret.txt'},
          ),
        );
    expect(step.path, isNot(contains(secret)));
    expect(step.actionPath, isNull);
  });
}
