import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts a process; [Process.start] outside tests.
typedef RootProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// The `root_shell` local tool: runs one command as root with `su -c` on a
/// rooted phone, in Android's own shell (not the workspace Linux). Every
/// call goes through the tool approval prompt.
class RootShellTool {
  const RootShellTool({RootProcessStarter? start})
    : _start = start ?? Process.start;

  static const String toolName = 'root_shell';

  static const int defaultTimeoutSeconds = 30;
  static const int maxTimeoutSeconds = 300;
  static const int maxCommandLength = 8000;

  /// How long output may still arrive after the command ended.
  static const Duration outputGrace = Duration(seconds: 2);

  /// Kept from the end of stdout and of stderr each.
  static const int maxOutputBytes = 16 * 1024;

  final RootProcessStarter _start;

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Run a shell command as root (su -c) on the user\'s rooted Android '
          'phone. It runs in Android\'s /system/bin/sh with toybox, not in the '
          'workspace Linux. Useful: settings get/put, pm list/grant/disable, '
          'am start/force-stop, cmd, dumpsys, getprop/setprop, logcat -d -t '
          '200, input tap/swipe/text/keyevent, screencap -p /sdcard/x.png, '
          'reading app data under /data. The user approves every command, '
          'so say first what it does and what it changes; prefer reading '
          'before writing, and never run commands that could brick the phone '
          '(partitions, dd to block devices, rm -rf /system or /data).',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Shell command, e.g. "dumpsys battery".',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description':
                'Stop the command after this many seconds (default '
                '$defaultTimeoutSeconds, at most $maxTimeoutSeconds).',
          },
        },
        'required': ['command'],
      },
    },
  };

  Future<String> execute(Map<String, dynamic> args) async {
    final command = args['command'];
    if (command is! String || command.trim().isEmpty) {
      return _error('invalid_command', '"command" is required.');
    }
    if (command.length > maxCommandLength || command.contains('\u0000')) {
      return _error(
        'invalid_command',
        'The command is longer than $maxCommandLength characters.',
      );
    }
    final rawTimeout = args['timeout_seconds'];
    final seconds = rawTimeout is num
        ? rawTimeout.toInt().clamp(1, maxTimeoutSeconds)
        : defaultTimeoutSeconds;

    final Process process;
    try {
      process = await _start('su', ['-c', command]);
    } on ProcessException {
      return _error(
        'root_unavailable',
        'su was not found: the phone is not rooted, or root is hidden from '
            'Moru.',
      );
    }
    final stdout = _Tail();
    final stderr = _Tail();
    final out = process.stdout.listen(stdout.add);
    final err = process.stderr.listen(stderr.add);
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      Duration(seconds: seconds),
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return process.exitCode;
      },
    );
    // A child the command left running (e.g. "cmd &", or one su started
    // before it was killed) keeps the pipes open; do not wait for it.
    await Future.wait([
      out.asFuture<void>(),
      err.asFuture<void>(),
    ]).timeout(outputGrace, onTimeout: () => const []);
    await out.cancel();
    await err.cancel();
    final errorText = stderr.text;
    return jsonEncode({
      'ok': exitCode == 0 && !timedOut,
      'exit_code': exitCode,
      if (timedOut) 'timed_out': true,
      'stdout': stdout.text,
      if (errorText.isNotEmpty) 'stderr': errorText,
      if (stdout.truncated || stderr.truncated) 'truncated': true,
      if (_denied(exitCode, errorText))
        'hint':
            'Root was refused: allow Moru in the root manager (Magisk, '
            'KernelSU), then try again.',
    });
  }

  static bool _denied(int exitCode, String stderr) =>
      exitCode != 0 &&
      RegExp(
        'permission denied|not allowed',
        caseSensitive: false,
      ).hasMatch(stderr);

  static String _error(String code, String message) =>
      jsonEncode({'ok': false, 'error': code, 'message': message});
}

/// The last [RootShellTool.maxOutputBytes] of a stream.
class _Tail {
  final List<int> _bytes = [];
  bool truncated = false;

  void add(List<int> chunk) {
    _bytes.addAll(chunk);
    final excess = _bytes.length - RootShellTool.maxOutputBytes;
    if (excess > 0) {
      _bytes.removeRange(0, excess);
      truncated = true;
    }
  }

  String get text => utf8.decode(_bytes, allowMalformed: true);
}
