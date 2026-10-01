import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/acp/acp_agent_catalog.dart';
import 'package:Kelivo/core/services/acp/acp_launch_directories.dart';

import '../../../support/acp_test_process_table.dart';

void main() {
  late Directory fixture;
  late File helper;
  late File processTable;
  final children = <Process>[];
  Map<String, String> processEnvironment() => {
    'MORU_TEST_PROCESS_IDS': jsonEncode(
      children.map((child) => child.pid).toList(),
    ),
    'MORU_TEST_PID_FILES': jsonEncode(['${fixture.path}/successor.pid']),
  };
  const provider = AcpProviderInput(
    baseUrl: 'https://example.test',
    apiKey: 'secret',
    model: 'model',
  );
  AcpLaunch launch() => AcpAgentSpec.byId(
    AcpAgentSpec.claudeCodeId,
  )!.launch(provider, configDirectory: fixture.path);
  Future<void> prepare(
    AcpLaunch launch, [
    List<String> active = const [],
  ]) async {
    final result = await Process.run('node', [
      '--require',
      processTable.path,
      helper.path,
      'prepare',
      launch.temporaryDirectory!,
      '$pid',
      ...active,
    ], environment: processEnvironment());
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }

  Future<ProcessResult> operate(
    String action,
    AcpLaunch launch, {
    Map<String, String> environment = const {},
    String? preload,
  }) => Process.run(
    'node',
    [
      '--require',
      processTable.path,
      if (preload != null) ...['--require', preload],
      helper.path,
      action,
      launch.temporaryDirectory!,
      '$pid',
    ],
    environment: {...processEnvironment(), ...environment},
  );
  Future<Process> running(AcpLaunch launch) async {
    await prepare(launch);
    final wrapper = AcpLaunchDirectories.arguments(
      AcpLaunch(
        command: 'node',
        arguments: [
          '-e',
          "process.stdout.write('ready\\n'); setInterval(() => {}, 1000)",
        ],
        temporaryDirectory: launch.temporaryDirectory,
      ),
    );
    final process = await Process.start(
      '/bin/sh',
      wrapper,
      environment: {
        ...launch.environment,
        'PATH': Platform.environment['PATH']!,
      },
    );
    children.add(process);
    final errors = process.stderr.transform(utf8.decoder).join();
    expect(
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first,
      'ready',
    );
    addTearDown(() async {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      expect(await errors, isEmpty);
    });
    return process;
  }

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('moru_launch_dirs_');
    helper = File('${fixture.path}/helper.cjs')
      ..writeAsStringSync(AcpLaunchDirectories.script);
    processTable = File('${fixture.path}/process-table.cjs')
      ..writeAsStringSync(acpTestProcessTableScript);
  });
  tearDown(() async {
    for (final child in children) {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    children.clear();
    fixture.deleteSync(recursive: true);
  });

  test(
    'recovery removes a killed launch and preserves a live parallel launch',
    () async {
      final first = launch();
      final second = launch();
      final killed = await running(first);
      await running(second);
      killed.kill(ProcessSignal.sigkill);
      await killed.exitCode;
      final unrelated = File(
        '${Directory(first.temporaryDirectory!).parent.path}/user-data',
      )..writeAsStringSync('keep');
      await prepare(launch());
      expect(Directory(first.temporaryDirectory!).existsSync(), isFalse);
      expect(Directory(second.temporaryDirectory!).existsSync(), isTrue);
      expect(unrelated.readAsStringSync(), 'keep');
    },
  );

  test(
    'active preparations survive recovery before the adapter claims its PID',
    () async {
      await prepare(launch());
      final pending = launch();
      final directory = Directory(pending.temporaryDirectory!)
        ..createSync(recursive: true);
      await prepare(launch(), [directory.path]);
      expect(directory.existsSync(), isTrue);
      await prepare(launch());
      expect(directory.existsSync(), isFalse);
    },
  );

  test(
    'an orphan without a marker is removed without following nested symlinks',
    () async {
      await prepare(launch());
      final orphan = launch();
      final directory = Directory(orphan.temporaryDirectory!)
        ..createSync(recursive: true);
      final userFile = File('${fixture.path}/session.json')
        ..writeAsStringSync('saved');
      Link('${directory.path}/sessions').createSync(userFile.parent.path);
      await prepare(launch());
      expect(directory.existsSync(), isFalse);
      expect(userFile.readAsStringSync(), 'saved');
    },
  );

  test(
    'a surviving child with the launch marker protects its directory',
    () async {
      final orphan = launch();
      await prepare(orphan);
      File('${orphan.temporaryDirectory}/.owner').writeAsStringSync(
        jsonEncode({'pid': 999999999, 'start': '1', 'boot': null}),
      );
      final child = await Process.start(
        'node',
        ['-e', "process.stdout.write('ready\\n'); setInterval(() => {}, 1000)"],
        environment: {'MORU_ACP_TEMP_DIR': orphan.temporaryDirectory!},
      );
      children.add(child);
      await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      await prepare(launch());
      expect(Directory(orphan.temporaryDirectory!).existsSync(), isTrue);
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
      await prepare(launch());
      expect(Directory(orphan.temporaryDirectory!).existsSync(), isFalse);
    },
  );

  test(
    'a reused PID with a different start time does not pin old scratch',
    () async {
      final old = launch();
      await prepare(old);
      final owner = File('${old.temporaryDirectory}/.owner');
      final record =
          jsonDecode(owner.readAsStringSync()) as Map<String, dynamic>;
      record['start'] = 'different-start-time';
      owner.writeAsStringSync(jsonEncode(record));
      await prepare(launch());
      expect(Directory(old.temporaryDirectory!).existsSync(), isFalse);
    },
  );

  test(
    'recovery collects unpublished staging from a killed preparation',
    () async {
      final old = launch();
      await prepare(old);
      final root = Directory(old.temporaryDirectory!).parent.path;
      final name = old.temporaryDirectory!.split('/').last;
      final staging = Directory('$root/.preparing-999999999-1-$name')
        ..createSync();
      File('${staging.path}/incomplete').writeAsStringSync('partial');
      await prepare(launch());
      expect(staging.existsSync(), isFalse);
      expect(Directory(old.temporaryDirectory!).existsSync(), isTrue);
    },
  );

  test('a pre-existing unmanaged parent is left intact', () async {
    final next = launch();
    final root = Directory(next.temporaryDirectory!).parent
      ..createSync(recursive: true);
    final saved = File('${root.path}/user-data')..writeAsStringSync('saved');
    final modeBefore = (await Process.run('stat', [
      '-c',
      '%a',
      root.path,
    ])).stdout;
    final result = await operate('prepare', next);
    expect(result.exitCode, isNot(0));
    expect(saved.readAsStringSync(), 'saved');
    expect(
      (await Process.run('stat', ['-c', '%a', root.path])).stdout,
      modeBefore,
    );
    expect(Directory(next.temporaryDirectory!).existsSync(), isFalse);
  });

  test(
    'a killed namespace bootstrap does not poison subsequent launches',
    () async {
      final first = launch();
      final root = Directory(first.temporaryDirectory!).parent.path;
      final preload = File('${fixture.path}/kill-bootstrap.cjs')
        ..writeAsStringSync(r'''
const fs = require('node:fs');
const original = fs.mkdirSync;
fs.mkdirSync = function(p, ...args) {
  const result = original.call(this, p, ...args);
  if (p === process.env.ROOT ||
      (typeof p === 'string' && p.includes('/.moru-root-'))) process.exit(91);
  return result;
};
''');
      expect(
        (await operate(
          'prepare',
          first,
          preload: preload.path,
          environment: {'ROOT': root},
        )).exitCode,
        91,
      );
      final second = launch();
      await prepare(second);
      expect(Directory(second.temporaryDirectory!).existsSync(), isTrue);
      expect(
        Directory(
          root,
        ).parent.listSync().where((file) => file.path.contains('/.moru-root-')),
        isEmpty,
      );
    },
  );

  test(
    'cleanup waits for a running adapter instead of deleting its scratch',
    () async {
      final live = launch();
      final adapter = await running(live);
      final result = await operate('remove', live);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(Directory(live.temporaryDirectory!).existsSync(), isTrue);
      adapter.kill(ProcessSignal.sigkill);
      await adapter.exitCode;
      expect((await operate('remove', live)).exitCode, 0);
      expect(Directory(live.temporaryDirectory!).existsSync(), isFalse);
    },
  );

  test(
    'a replaced parent never changes or deletes files in the replacement',
    () async {
      final previous = launch();
      await prepare(previous);
      final owner = File('${previous.temporaryDirectory}/.owner');
      owner.writeAsStringSync(jsonEncode({'pid': 999999999, 'start': '1'}));
      final next = launch();
      final root = Directory(previous.temporaryDirectory!).parent.path;
      final victim = Directory('${fixture.path}/user-folder')..createSync();
      final victimRun = Directory(
        '${victim.path}/${Directory(previous.temporaryDirectory!).uri.pathSegments.where((s) => s.isNotEmpty).last}',
      )..createSync();
      final saved = File('${victimRun.path}/session.json')
        ..writeAsStringSync('saved');
      final modeBefore = (await Process.run('stat', [
        '-c',
        '%a',
        victim.path,
      ])).stdout;
      final preload = File('${fixture.path}/replace-parent.cjs')
        ..writeAsStringSync(r'''
const fs = require('node:fs');
let swapped = false;
function swap(p) {
  if (p !== process.env.SWAP_ROOT || swapped) return;
  swapped = true;
  fs.renameSync(p, p + '-saved');
  fs.symlinkSync(process.env.VICTIM_ROOT, p);
}
for (const method of ['lstatSync', 'openSync']) {
  const original = fs[method];
  fs[method] = function(p, ...args) {
    const result = original.call(this, p, ...args);
    swap(p);
    return result;
  };
}
''');
      final result = await operate(
        'prepare',
        next,
        preload: preload.path,
        environment: {'SWAP_ROOT': root, 'VICTIM_ROOT': victim.path},
      );
      expect(result.exitCode, isNot(0));
      expect(saved.readAsStringSync(), 'saved');
      expect(
        (await Process.run('stat', ['-c', '%a', victim.path])).stdout,
        modeBefore,
      );
      expect(
        Directory(
          '${victim.path}/${next.temporaryDirectory!.split('/').last}',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('an uninspectable registered process defers collection', () async {
    final old = launch();
    await prepare(old);
    File('${old.temporaryDirectory}/.owner').writeAsStringSync(
      jsonEncode({'pid': 999999999, 'start': '1', 'boot': null}),
    );
    final child = await Process.start('node', [
      '-e',
      "process.stdout.write('ready\\n'); setInterval(() => {}, 1000)",
    ]);
    children.add(child);
    await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final preload = File('${fixture.path}/process-unreadable.cjs')
      ..writeAsStringSync(r'''
const fs = require('node:fs');
const original = fs.readFileSync;
fs.readFileSync = function(p, ...args) {
  if (p === `/proc/${process.env.UNREADABLE_PROCESS}/environ`) {
    throw Object.assign(new Error('denied'), { code: 'EACCES' });
  }
  return original.call(this, p, ...args);
};
''');
    final result = await operate(
      'prepare',
      launch(),
      preload: preload.path,
      environment: {'UNREADABLE_PROCESS': '${child.pid}'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(Directory(old.temporaryDirectory!).existsSync(), isTrue);
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    await prepare(launch());
    expect(Directory(old.temporaryDirectory!).existsSync(), isFalse);
  });

  test('unreadable owner records defer collection', () async {
    final old = launch();
    await prepare(old);
    final preload = File('${fixture.path}/owner-unreadable.cjs')
      ..writeAsStringSync(r'''
const fs = require('node:fs');
for (const method of ['readFileSync', 'openSync', 'lstatSync']) {
  const original = fs[method];
  fs[method] = function(p, ...args) {
    if (typeof p === 'string' && p.endsWith('/.owner') &&
        fs.realpathSync(p.slice(0, -7)) === process.env.OWNER_DIRECTORY) {
      throw Object.assign(new Error('denied'), { code: 'EACCES' });
    }
    return original.call(this, p, ...args);
  };
}
''');
    final result = await operate(
      'prepare',
      launch(),
      preload: preload.path,
      environment: {'OWNER_DIRECTORY': old.temporaryDirectory!},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(Directory(old.temporaryDirectory!).existsSync(), isTrue);
  });

  test(
    'claim cannot overwrite a user owner file through a substituted run',
    () async {
      final old = launch();
      await prepare(old);
      final victim = Directory('${fixture.path}/user-owned')..createSync();
      final saved = File('${victim.path}/.owner')
        ..writeAsStringSync('user data');
      final preload = File('${fixture.path}/replace-run.cjs')
        ..writeAsStringSync(r'''
const fs = require('node:fs');
let swapped = false;
for (const method of ['lstatSync', 'openSync']) {
  const original = fs[method];
  fs[method] = function(p, ...args) {
    const result = original.call(this, p, ...args);
    if (!swapped && typeof p === 'string' && p.endsWith('/' + process.env.RUN_NAME)) {
      swapped = true;
      fs.renameSync(p, p + '-saved');
      fs.symlinkSync(process.env.VICTIM, p);
    }
    return result;
  };
}
''');
      final result = await operate(
        'claim',
        old,
        preload: preload.path,
        environment: {
          'RUN_NAME': old.temporaryDirectory!.split('/').last,
          'VICTIM': victim.path,
        },
      );
      expect(result.exitCode, isNot(0));
      expect(saved.readAsStringSync(), 'user data');
      expect(victim.listSync(), hasLength(1));
    },
  );

  test(
    'a fork after the process snapshot protects the surviving SDK',
    () async {
      final old = launch();
      await prepare(old);
      File(
        '${old.temporaryDirectory}/.owner',
      ).writeAsStringSync(jsonEncode({'pid': 999999999, 'start': '1'}));
      final successorFile = File('${fixture.path}/successor.pid');
      final adapter = await Process.start(
        'node',
        [
          '-e',
          r'''
const { spawn } = require('node:child_process');
const fs = require('node:fs');
process.on('SIGUSR1', () => {
  const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
    detached: true, stdio: 'ignore', env: process.env,
  });
  fs.writeFileSync(process.env.SUCCESSOR_PID_FILE, String(child.pid));
  child.unref();
  process.exit(0);
});
process.stdout.write('ready\n');
setInterval(() => {}, 1000);
''',
        ],
        environment: {
          'MORU_ACP_TEMP_DIR': old.temporaryDirectory!,
          'SUCCESSOR_PID_FILE': successorFile.path,
        },
      );
      children.add(adapter);
      await adapter.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      addTearDown(() {
        if (successorFile.existsSync()) {
          Process.killPid(
            int.parse(successorFile.readAsStringSync()),
            ProcessSignal.sigkill,
          );
        }
      });
      final preload = File('${fixture.path}/snapshot-fork.cjs')
        ..writeAsStringSync(r'''
const fs = require('node:fs');
const original = fs.readdirSync;
let intercepted = false;
fs.readdirSync = function(p, ...args) {
  const result = original.call(this, p, ...args);
  if (p === '/proc' && !intercepted) {
    intercepted = true;
    process.kill(Number(process.env.SDK_PARENT_PID), 'SIGUSR1');
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      try {
        const childPid = fs.readFileSync(process.env.SUCCESSOR_PID_FILE, 'utf8');
        fs.readFileSync('/proc/' + childPid + '/environ');
        const stat = fs.readFileSync('/proc/' + process.env.SDK_PARENT_PID + '/stat', 'utf8');
        if (stat.includes(') Z ')) break;
      } catch (error) {
        if (error.code === 'ENOENT' && fs.existsSync(process.env.SUCCESSOR_PID_FILE)) break;
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1);
    }
  }
  return result;
};
''');
      final result = await operate(
        'prepare',
        launch(),
        preload: preload.path,
        environment: {
          'SDK_PARENT_PID': '${adapter.pid}',
          'SUCCESSOR_PID_FILE': successorFile.path,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(Directory(old.temporaryDirectory!).existsSync(), isTrue);
    },
  );
}
