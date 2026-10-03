import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef RootShellResult = ({
  int exitCode,
  bool timedOut,
  String stdout,
  String stderr,
  bool truncated,
});

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
          'reading app data under /data. Commands that only read (dumpsys, '
          'getprop, settings get, pm list, logcat -d, ls, cat, grep, ps... '
          'and pipes of them, without redirects, ";" or "&") run at once; the '
          'user approves every other command, so say first what it does and '
          'what it changes. Never run commands that could brick the phone '
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
    final result = await run(command, timeoutSeconds: seconds);
    if (result == null) {
      return _error(
        'root_unavailable',
        'su was not found: the phone is not rooted, or root is hidden from '
            'Moru.',
      );
    }
    return jsonEncode({
      'ok': result.exitCode == 0 && !result.timedOut,
      'exit_code': result.exitCode,
      if (result.timedOut) 'timed_out': true,
      'stdout': result.stdout,
      if (result.stderr.isNotEmpty) 'stderr': result.stderr,
      if (result.truncated) 'truncated': true,
      if (_denied(result.exitCode, result.stderr))
        'hint':
            'Root was refused: allow Moru in the root manager (Magisk, '
            'KernelSU), then try again.',
    });
  }

  /// Runs [command] with `su -c`; null when su is missing.
  Future<RootShellResult?> run(
    String command, {
    int timeoutSeconds = defaultTimeoutSeconds,
  }) async {
    final Process process;
    try {
      process = await _start('su', ['-c', command]);
    } on ProcessException {
      return null;
    }
    final stdout = _Tail();
    final stderr = _Tail();
    final out = process.stdout.listen(stdout.add);
    final err = process.stderr.listen(stderr.add);
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      Duration(seconds: timeoutSeconds),
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
    return (
      exitCode: exitCode,
      timedOut: timedOut,
      stdout: stdout.text,
      stderr: stderr.text,
      truncated: stdout.truncated || stderr.truncated,
    );
  }

  static bool _denied(int exitCode, String stderr) =>
      exitCode != 0 &&
      RegExp(
        'permission denied|not allowed',
        caseSensitive: false,
      ).hasMatch(stderr);

  /// Commands that only read and may run without approval.
  static const Set<String> _readers = {
    'basename', 'cat', 'cut', 'date', 'df', 'dirname', 'du', 'dumpsys',
    'echo', 'egrep', 'env', 'fgrep', 'file', 'free', 'getenforce', 'getprop',
    'grep', 'head', 'id', 'ls', 'lsof', 'md5sum', 'netstat', 'nproc',
    'pidof', 'printenv', 'printf', 'ps', 'pwd', 'readlink', 'realpath',
    'sha256sum', 'sort', 'stat', 'tail', 'tr', 'uname', 'uniq', 'uptime',
    'wc', 'which', 'whoami',
    // Checked by their arguments below.
    'find', 'logcat', 'pm', 'settings', 'top', 'wm',
  };

  /// Whether [command] only reads: every piped command is a known reader
  /// used in a reading way, with no redirects, sequencing, background jobs
  /// or command substitution. Anything unclear needs approval.
  static bool isReadOnly(String command) {
    final commands = _split(command);
    if (commands == null || commands.isEmpty) return false;
    return commands.every(_readsOnly);
  }

  static bool _readsOnly(List<String> words) {
    if (words.isEmpty) return false;
    final name = words.first.split('/').last;
    final rest = words.skip(1).toList();
    if (!_readers.contains(name)) return false;
    switch (name) {
      case 'settings':
        return rest.isNotEmpty && {'get', 'list'}.contains(rest.first);
      case 'pm':
        return rest.isNotEmpty &&
            {'list', 'path', 'dump', 'resolve-activity'}.contains(rest.first);
      case 'logcat':
        return rest.contains('-d');
      case 'top':
        return rest.contains('-n');
      case 'wm':
        return rest.length == 1 && {'size', 'density'}.contains(rest.first);
      case 'find':
        return !rest.any(
          (w) => {
            '-delete',
            '-exec',
            '-execdir',
            '-ok',
            '-okdir',
            '-fprint',
            '-fprintf',
            '-fls',
          }.contains(w),
        );
      case 'tail':
        return !rest.any((w) => w.startsWith('-f') || w == '-F');
      case 'date':
        return !rest.any((w) => w.startsWith('-s') || w.startsWith('--set'));
      case 'sort':
        return !rest.any((w) => w.startsWith('-o') || w == '--output');
      default:
        return true;
    }
  }

  /// Words of each piped command, honouring quotes; null for anything but
  /// plain words and pipes.
  static List<List<String>>? _split(String command) {
    final commands = <List<String>>[];
    var words = <String>[];
    final word = StringBuffer();
    var hasWord = false;
    String? quote;
    void endWord() {
      if (hasWord) words.add(word.toString());
      word.clear();
      hasWord = false;
    }

    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (quote == "'") {
        if (c == "'") {
          quote = null;
        } else {
          word.write(c);
        }
        continue;
      }
      if (quote == '"') {
        if (c == '"') {
          quote = null;
        } else if (c == '`' || c == r'$' || c == '\\') {
          return null;
        } else {
          word.write(c);
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        hasWord = true;
      } else if (c == ' ' || c == '\t') {
        endWord();
      } else if (c == '|') {
        endWord();
        if (words.isEmpty) return null;
        commands.add(words);
        words = <String>[];
      } else if (';&<>`\$\\\n\r(){}!#='.contains(c)) {
        return null;
      } else {
        word.write(c);
        hasWord = true;
      }
    }
    if (quote != null) return null;
    endWord();
    if (words.isEmpty) return null;
    commands.add(words);
    return commands;
  }

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
