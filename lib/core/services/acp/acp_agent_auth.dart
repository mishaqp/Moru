import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../workspace/workspace_runtime.dart';
import 'acp_agent_catalog.dart';
import 'acp_connection.dart' show AcpError;
import 'acp_error_messages.dart';
import 'acp_launch_directories.dart';

enum AcpAuthStatus { unknown, signedOut, signedIn }

enum AcpAuthFailure { environment, start, network, timeout }

/// Prepared by the manager with the same guest identity, persistent home,
/// compatibility shim and temporary-directory lease as an ACP launch.
class AcpAuthContext {
  const AcpAuthContext({
    required this.runtime,
    required this.launch,
    this.expectedRootChroot,
  });

  final WorkspaceStdioRuntime runtime;
  final AcpLaunch launch;
  final bool? expectedRootChroot;

  String command(String executable, List<String> arguments) {
    final native = AcpLaunch(
      command: executable,
      arguments: arguments,
      temporaryDirectory: launch.temporaryDirectory,
      isolateCodexDaemon: launch.isolateCodexDaemon,
      unsetEnvironment: launch.unsetEnvironment,
    );
    if (native.temporaryDirectory != null) {
      return AcpLaunchDirectories.arguments(native)[1];
    }
    return 'set -e\numask 077\n${native.unsetEnvironmentScript}'
        'exec ${[executable, ...arguments].map(AcpLaunchDirectories.quote).join(' ')}';
  }
}

/// Ephemeral secrets for the dedicated sign-in screen only. Never persist,
/// print, include in diagnostics, or pass this object to chat/tool handlers.
class AcpLoginAttempt {
  factory AcpLoginAttempt({Uri? url, String? deviceCode}) =>
      AcpLoginAttempt._(url, deviceCode);
  AcpLoginAttempt._(this._url, this._deviceCode);

  Uri? _url;
  String? _deviceCode;
  Uri? get url => _url;
  String? get deviceCode => _deviceCode;
  bool get awaitingUser => _url != null || _deviceCode != null;
  bool _cancelled = false;
  final _done = Completer<void>();
  AcpAuthContext? _context;
  String? _runId;

  void _clear() {
    _url = null;
    _deviceCode = null;
  }
}

class _AuthOperation {
  bool cancelled = false;
  final done = Completer<void>();
  AcpAuthContext? context;
  String? runId;
}

/// Official CLI sign-in; Moru never reads, exchanges or refreshes tokens.
/// CLI output stays inside this boundary. Only allowlisted challenges leave
/// it, through [loginFor], while failures and status contain no CLI text.
class AcpAgentAuth extends ChangeNotifier {
  AcpAgentAuth({required this.prepare, required this.stopAgents});

  final Future<AcpAuthContext> Function(AcpAgentSpec spec) prepare;
  final Future<void> Function(String agentId) stopAgents;
  final _statuses = <String, AcpAuthStatus>{};
  final _failures = <String, AcpAuthFailure>{};
  final _logins = <String, AcpLoginAttempt>{};
  final _checking = <String, Future<AcpAuthStatus>>{};
  final _loggingOut = <String>{};
  final _operations = <String, Set<_AuthOperation>>{};
  final _cancelling = <String>{};
  bool _disposed = false;

  AcpAuthStatus status(String id) => _statuses[id] ?? AcpAuthStatus.unknown;
  AcpAuthFailure? failure(String id) => _failures[id];
  bool busy(String id) =>
      _logins.containsKey(id) ||
      _checking.containsKey(id) ||
      changingCredentials(id);
  bool changingCredentials(String id) =>
      _logins.containsKey(id) ||
      _loggingOut.contains(id) ||
      _cancelling.contains(id);
  AcpLoginAttempt? loginFor(String id) => _logins[id];

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// A protocol auth-required response invalidates a previously checked login.
  void requireSignIn(String id) {
    _statuses[id] = AcpAuthStatus.signedOut;
    _failures.remove(id);
    notifyListeners();
  }

  Future<AcpAuthStatus> check(AcpAgentSpec spec) {
    if (_disposed ||
        !spec.supportsSubscription ||
        changingCredentials(spec.id)) {
      return Future.value(AcpAuthStatus.unknown);
    }
    final existing = _checking[spec.id];
    if (existing != null) return existing;
    final checked = _check(spec);
    _checking[spec.id] = checked;
    notifyListeners();
    return checked;
  }

  Future<AcpAuthStatus> _check(AcpAgentSpec spec) async {
    final operation = _beginOperation(spec.id);
    AcpAuthContext? context;
    var next = AcpAuthStatus.unknown;
    _failures.remove(spec.id);
    try {
      context = await prepare(spec);
      operation.context = context;
      if (_disposed || operation.cancelled) return next;
      final (code, stdout, stderr) = await _run(
        operation,
        context,
        spec.id == AcpAgentSpec.claudeCodeId ? 'claude' : 'codex',
        spec.id == AcpAgentSpec.claudeCodeId
            ? const ['auth', 'status', '--json']
            : const ['login', 'status'],
      );
      next = _statusFromOutput(
        spec,
        code,
        spec.id == AcpAgentSpec.claudeCodeId ? stdout : '$stdout\n$stderr',
      );
      if (next == AcpAuthStatus.unknown) {
        _failures[spec.id] = AcpAuthFailure.start;
      }
    } catch (error) {
      if (!operation.cancelled && !_disposed) _recordFailure(spec.id, error);
    } finally {
      await _cleanup(context, spec.id);
      _statuses[spec.id] = next;
      _checking.remove(spec.id);
      _finishOperation(spec.id, operation);
      notifyListeners();
    }
    return next;
  }

  static AcpAuthStatus _statusFromOutput(
    AcpAgentSpec spec,
    int code,
    String output,
  ) {
    if (spec.id == AcpAgentSpec.claudeCodeId) {
      try {
        final data = jsonDecode(output);
        if (data is Map && data['loggedIn'] is bool) {
          if (code == 0 &&
              data['loggedIn'] == true &&
              data['authMethod'] == 'claude.ai') {
            return AcpAuthStatus.signedIn;
          }
          if (code == 0 || (code == 1 && data['loggedIn'] == false)) {
            return AcpAuthStatus.signedOut;
          }
        }
      } on FormatException {
        // Account attributes and all unexpected output are discarded.
      }
    } else {
      if (code == 0 && output.contains('Logged in using ChatGPT')) {
        return AcpAuthStatus.signedIn;
      }
      if ((code == 1 && output.contains('Not logged in')) ||
          (code == 0 && output.contains('Logged in using an API key'))) {
        return AcpAuthStatus.signedOut;
      }
    }
    return AcpAuthStatus.unknown;
  }

  Future<void> signIn(AcpAgentSpec spec) async {
    if (_disposed || !spec.supportsSubscription || busy(spec.id)) return;
    final attempt = AcpLoginAttempt();
    _logins[spec.id] = attempt;
    _statuses[spec.id] = AcpAuthStatus.unknown;
    _failures.remove(spec.id);
    notifyListeners();
    var success = false;
    try {
      // Codex login removes previous auth before starting; don't leave an ACP
      // child alive with cached tokens while another process replaces them.
      await stopAgents(spec.id);
      if (attempt._cancelled || _disposed) return;
      final context = await prepare(spec);
      attempt._context = context;
      if (attempt._cancelled || _disposed) return;
      final runId = 'acp-auth-${const Uuid().v4()}';
      attempt._runId = runId;
      final parser = _LoginOutput(spec.id, attempt);
      notifyListeners();
      var exitCode = -1;
      await for (final event in context.runtime.run(
        CommandRequest(
          runId: runId,
          command: context.command(
            spec.id == AcpAgentSpec.claudeCodeId ? 'claude' : 'codex',
            spec.id == AcpAgentSpec.claudeCodeId
                ? const ['auth', 'login', '--claudeai']
                : const ['login', '--device-auth'],
          ),
          cwd: '/root',
          env: {...context.launch.environment, 'BROWSER': '/bin/true'},
          keepStdinOpen: true,
          emulateHardLinks: false,
          expectedRootChroot: context.expectedRootChroot,
          timeout: const Duration(minutes: 16),
          isCancelled: () => attempt._cancelled || _disposed,
        ),
      )) {
        if (attempt._cancelled || _disposed) continue;
        switch (event) {
          case CommandOutput(:final kind, :final bytes):
            parser.add(kind, bytes);
            notifyListeners();
          case CommandExited(:final timedOut, :final exitCode):
            if (timedOut) _failures[spec.id] = AcpAuthFailure.timeout;
            success = exitCode == 0;
          case CommandStarted():
            notifyListeners();
        }
        if (event is CommandExited) exitCode = event.exitCode;
      }
      if (!success &&
          !attempt._cancelled &&
          !_disposed &&
          !_failures.containsKey(spec.id)) {
        _failures[spec.id] = parser.networkFailure
            ? AcpAuthFailure.network
            : AcpAuthFailure.start;
      }
      // Only the official status command decides whether a successful CLI
      // login actually used a subscription. Exit zero alone is insufficient.
      if (exitCode == 0 && !attempt._cancelled && !_disposed) success = true;
    } catch (error) {
      if (!attempt._cancelled) _recordFailure(spec.id, error);
    } finally {
      attempt._clear();
      await _cleanup(attempt._context, spec.id);
      _logins.remove(spec.id);
      if (!attempt._done.isCompleted) attempt._done.complete();
      notifyListeners();
    }
    if (success && !attempt._cancelled && !_disposed) await check(spec);
  }

  Future<void> submitCode(String id, String code) async {
    final attempt = _logins[id];
    if (id != AcpAgentSpec.claudeCodeId ||
        attempt == null ||
        attempt._cancelled ||
        attempt._context == null ||
        attempt._runId == null) {
      return;
    }
    final line = code.trim();
    if (line.isEmpty ||
        line.length > 8192 ||
        line.contains(RegExp(r'[\r\n\x00]'))) {
      return;
    }
    try {
      await attempt._context!.runtime.writeStdin(
        attempt._runId!,
        Uint8List.fromList(utf8.encode('$line\n')),
      );
    } catch (error) {
      _recordFailure(id, error);
      await cancel(id);
    }
  }

  Future<void> cancel(String id) async {
    final attempt = _logins[id];
    if (attempt == null) return;
    attempt._cancelled = true;
    attempt._clear();
    notifyListeners();
    final context = attempt._context;
    final runId = attempt._runId;
    if (context != null && runId != null) {
      try {
        await context.runtime.cancel(runId);
      } catch (_) {
        // Cancellation errors must not disclose native output.
      }
    }
    await attempt._done.future;
  }

  Future<void> signOut(AcpAgentSpec spec) async {
    if (_disposed ||
        !spec.supportsSubscription ||
        _loggingOut.contains(spec.id) ||
        _cancelling.contains(spec.id)) {
      return;
    }
    _loggingOut.add(spec.id);
    final operation = _beginOperation(spec.id);
    _failures.remove(spec.id);
    notifyListeners();
    AcpAuthContext? context;
    try {
      await cancel(spec.id);
      await _checking[spec.id];
      await stopAgents(spec.id);
      if (_disposed || operation.cancelled) return;
      context = await prepare(spec);
      operation.context = context;
      if (_disposed || operation.cancelled) return;
      final (code, _, _) = await _run(
        operation,
        context,
        spec.id == AcpAgentSpec.claudeCodeId ? 'claude' : 'codex',
        spec.id == AcpAgentSpec.claudeCodeId
            ? const ['auth', 'logout']
            : const ['logout'],
      );
      if (code == 0) {
        _statuses[spec.id] = AcpAuthStatus.signedOut;
      } else {
        _failures[spec.id] = AcpAuthFailure.start;
      }
    } catch (error) {
      if (!operation.cancelled && !_disposed) _recordFailure(spec.id, error);
    } finally {
      await _cleanup(context, spec.id);
      _loggingOut.remove(spec.id);
      _finishOperation(spec.id, operation);
      notifyListeners();
    }
  }

  _AuthOperation _beginOperation(String id) {
    final operation = _AuthOperation();
    (_operations[id] ??= {}).add(operation);
    return operation;
  }

  void _finishOperation(String id, _AuthOperation operation) {
    _operations[id]?.remove(operation);
    if (_operations[id]?.isEmpty == true) _operations.remove(id);
    if (!operation.done.isCompleted) operation.done.complete();
  }

  /// Uninstall/disposal cancels every native command, including commands still
  /// waiting for environment preparation. Cleanup finishes before returning.
  Future<void> cancelOperations(String id) async {
    _cancelling.add(id);
    final operations = _operations[id]?.toList() ?? const <_AuthOperation>[];
    for (final operation in operations) {
      operation.cancelled = true;
    }
    try {
      await Future.wait([
        cancel(id),
        for (final operation in operations) _cancelOperation(operation),
      ]);
    } finally {
      _cancelling.remove(id);
      notifyListeners();
    }
  }

  Future<void> _cancelOperation(_AuthOperation operation) async {
    final context = operation.context;
    final runId = operation.runId;
    if (context != null && runId != null) {
      try {
        await context.runtime.cancel(runId);
      } catch (_) {
        // Native cancellation failures must not become diagnostics.
      }
    }
    await operation.done.future;
  }

  void _recordFailure(String id, Object error) {
    _failures[id] = error is TimeoutException
        ? AcpAuthFailure.timeout
        : error is AcpError && error.code == AcpError.disconnected
        ? AcpAuthFailure.environment
        : classifyAcpFailure(error) == AcpFailureKind.network
        ? AcpAuthFailure.network
        : AcpAuthFailure.start;
  }

  Future<void> _cleanup(AcpAuthContext? context, String id) async {
    try {
      await context?.launch.cleanup?.call();
    } catch (error) {
      _recordFailure(id, error);
    }
  }

  Future<(int, String, String)> _run(
    _AuthOperation operation,
    AcpAuthContext context,
    String executable,
    List<String> arguments,
  ) async {
    final runId = 'acp-auth-${const Uuid().v4()}';
    operation.runId = runId;
    final stdout = <int>[];
    final stderr = <int>[];
    var code = -1;
    await for (final event in context.runtime.run(
      CommandRequest(
        runId: runId,
        command: context.command(executable, arguments),
        cwd: '/root',
        env: context.launch.environment,
        emulateHardLinks: false,
        expectedRootChroot: context.expectedRootChroot,
        timeout: const Duration(seconds: 45),
        isCancelled: () => _disposed || operation.cancelled,
      ),
    )) {
      switch (event) {
        case CommandOutput(:final kind, :final bytes):
          if (stdout.length + stderr.length + bytes.length > 64 * 1024) {
            await context.runtime.cancel(runId);
            throw const AcpError(
              AcpError.internalError,
              'Invalid authentication status',
            );
          }
          (kind == OutputStreamKind.stdout ? stdout : stderr).addAll(bytes);
        case CommandExited(:final exitCode, :final timedOut):
          if (timedOut) {
            throw TimeoutException('Authentication status timed out');
          }
          code = exitCode;
        case CommandStarted():
          break;
      }
    }
    if (_disposed || operation.cancelled) {
      throw const AcpError(AcpError.disconnected, 'Authentication cancelled');
    }
    return (
      code,
      utf8.decode(stdout, allowMalformed: true),
      utf8.decode(stderr, allowMalformed: true),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in {..._logins.keys, ..._operations.keys}) {
      unawaited(cancelOperations(id));
    }
    super.dispose();
  }
}

/// Bounded, private parser. Raw ANSI/output text is never exposed by the API.
class _LoginOutput {
  _LoginOutput(this.agentId, this.attempt);
  final String agentId;
  final AcpLoginAttempt attempt;
  final _text = <OutputStreamKind, String>{};
  final _decoders = <OutputStreamKind, ByteConversionSink>{};
  bool networkFailure = false;
  static final _ansi = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]');

  void add(OutputStreamKind kind, List<int> bytes) {
    final decoder = _decoders.putIfAbsent(
      kind,
      () => const Utf8Decoder(allowMalformed: true).startChunkedConversion(
        StringConversionSink.from(
          _LoginTextSink((chunk) => _decoded(kind, chunk)),
        ),
      ),
    );
    decoder.add(bytes);
  }

  void _decoded(OutputStreamKind kind, String chunk) {
    var raw = (_text[kind] ?? '') + chunk;
    if (raw.length > 32 * 1024) raw = raw.substring(raw.length - 32 * 1024);
    _text[kind] = raw;
    final text = raw.replaceAll(_ansi, '');
    if (classifyAcpFailure(text) == AcpFailureKind.network) {
      networkFailure = true;
    }
    // Require the trailing delimiter: a partial URL or device code must not
    // become a challenge when a pipe chunk ends in the middle of it.
    for (final match in RegExp(
      r'https://[^\s\x1b<>"\x27]+(?=[\s\x1b<>"\x27])',
    ).allMatches(text)) {
      final uri = Uri.tryParse(match.group(0)!);
      if (uri == null || uri.userInfo.isNotEmpty || uri.hasPort) continue;
      final allowed = agentId == AcpAgentSpec.claudeCodeId
          ? (uri.host == 'claude.com' ||
                    uri.host == 'claude.ai' ||
                    uri.host == 'console.anthropic.com') &&
                uri.path == '/oauth/authorize'
          : uri.host == 'auth.openai.com' && uri.path == '/codex/device';
      if (allowed) attempt._url = uri;
    }
    if (agentId == AcpAgentSpec.codexId) {
      final match = RegExp(
        r'Enter this one-time code[^\n]*\n\s*([A-Z0-9]{4,6}-[A-Z0-9]{4,6})(?=\s)',
        caseSensitive: false,
      ).firstMatch(text);
      if (match != null) attempt._deviceCode = match.group(1);
    }
  }
}

class _LoginTextSink implements Sink<String> {
  _LoginTextSink(this.onText);
  final void Function(String) onText;
  @override
  void add(String text) => onText(text);
  @override
  void close() {}
}
