import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/home/services/root_shell_tool.dart';

void main() {
  // `sh` takes the same `-c command` as `su`, so the real process path runs.
  final calls = <List<String>>[];
  RootShellTool tool() => RootShellTool(
    start: (executable, arguments) {
      calls.add([executable, ...arguments]);
      return Process.start('sh', arguments);
    },
  );

  setUp(calls.clear);

  Future<Map<String, dynamic>> run(
    Map<String, dynamic> args, {
    RootShellTool? with_,
  }) async =>
      jsonDecode(await (with_ ?? tool()).execute(args)) as Map<String, dynamic>;

  test('runs the command with su -c and returns its output', () async {
    final result = await run({'command': 'echo hi; echo oops >&2; exit 3'});
    expect(calls, [
      ['su', '-c', 'echo hi; echo oops >&2; exit 3'],
    ]);
    expect(result, {
      'ok': false,
      'exit_code': 3,
      'stdout': 'hi\n',
      'stderr': 'oops\n',
    });
    expect(await run({'command': 'printf ok'}), {
      'ok': true,
      'exit_code': 0,
      'stdout': 'ok',
    });
  });

  test('long output keeps its end and says it was cut', () async {
    final result = await run({
      'command': 'head -c 40000 /dev/zero | tr "\\0" a; echo END',
    });
    expect(result['truncated'], isTrue);
    final out = result['stdout'] as String;
    expect(out.length, RootShellTool.maxOutputBytes);
    expect(out, endsWith('aEND\n'));
  });

  test('a command past its timeout is killed', () async {
    final watch = Stopwatch()..start();
    final result = await run({'command': 'sleep 20', 'timeout_seconds': 1});
    expect(result['timed_out'], isTrue);
    expect(result['ok'], isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('a command that leaves a process running still returns', () async {
    final watch = Stopwatch()..start();
    final result = await run({'command': 'sleep 20 & echo started'});
    expect(result['ok'], isTrue);
    expect(result['stdout'], 'started\n');
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test(
    'a refused su gets a hint; a missing su says the phone is not rooted',
    () async {
      final refused = await run({
        'command': 'echo "Permission denied" >&2; exit 1',
      });
      expect(refused['hint'], contains('root manager'));

      final missing = await run(
        {'command': 'id'},
        with_: RootShellTool(
          start: (executable, arguments) =>
              Process.start('/nonexistent/su', arguments),
        ),
      );
      expect(missing['error'], 'root_unavailable');
    },
  );

  test('bad arguments run nothing', () async {
    for (final args in [
      <String, dynamic>{},
      {'command': '   '},
      {'command': 'x' * (RootShellTool.maxCommandLength + 1)},
    ]) {
      expect((await run(args))['error'], 'invalid_command');
    }
    expect(calls, isEmpty);
  });

  test('reading commands run at once, anything else is approved', () {
    bool approval(String command) => LocalToolNames.requiresApprovalFor(
      LocalToolNames.rootShell,
      {'command': command},
    );
    for (final command in [
      'dumpsys battery',
      'dumpsys battery | grep -E "level|temperature|status"',
      'getprop ro.build.version.release',
      'settings get system screen_brightness',
      'pm list packages -3',
      'logcat -d -t 200',
      'ls -la /sdcard/*.png',
      'cat /proc/meminfo | head -n 5',
    ]) {
      expect(approval(command), isFalse, reason: command);
      expect(RootShellTool.isReadOnly(command), isTrue, reason: command);
    }
    for (final command in [
      'settings put system screen_brightness 50',
      'pm uninstall com.example',
      'logcat',
      'input tap 100 200',
      'reboot',
      'rm -rf /sdcard/x',
      'dumpsys battery > /sdcard/b.txt',
      'dumpsys battery; reboot',
      'dumpsys battery && reboot',
      'dumpsys battery & reboot',
      r'cat $(which su)',
      'cat `which su`',
      'echo "\$(reboot)"',
      'getprop | sh',
      'find /sdcard -delete',
      'tail -f /data/log',
      'date -s 20260101',
      'sort -o /system/x in',
      'FOO=1 dumpsys',
      'wm size 1080x1920',
      'dumpsys battery ||',
      'cat "unclosed',
      '',
      '   ',
    ]) {
      expect(approval(command), isTrue, reason: command);
    }
    expect(approval(''), isTrue);
    expect(
      LocalToolNames.requiresApprovalFor(LocalToolNames.rootShell, {}),
      isTrue,
    );
    expect(
      LocalToolsService.definitionFor(
        LocalToolNames.rootShell,
      )['function']['name'],
      'root_shell',
    );
  });
}
