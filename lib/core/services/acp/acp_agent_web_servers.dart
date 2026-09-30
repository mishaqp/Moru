import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../workspace/workspace_runtime.dart';
import 'acp_agent_catalog.dart';

enum AcpWebFailure { start, timeout, exited, stopped }

class AcpWebException implements Exception {
  const AcpWebException(this.failure);
  final AcpWebFailure failure;
  // Never include process output: its address can contain a login token.
  @override
  String toString() => 'Agent web interface: ${failure.name}';
}

typedef AcpWebPrepare =
    Future<(WorkspaceRuntime, AcpLaunch)> Function(
      AcpAgentSpec spec,
      AcpProviderInput provider,
      int port,
      String directory,
    );

/// App-owned Linux processes. Their printed login URLs are kept privately
/// only until opening the browser, never recorded as output or diagnostics.
class AcpAgentWebServers extends ChangeNotifier with WidgetsBindingObserver {
  AcpAgentWebServers({
    required this.prepare,
    Future<int> Function()? freePort,
    this.startTimeout = const Duration(seconds: 120),
  }) : _freePort = freePort ?? _loopbackPort {
    WidgetsBinding.instance.addObserver(this);
  }

  final AcpWebPrepare prepare;
  final Future<int> Function() _freePort;
  final Duration startTimeout;
  final Map<String, _WebRun> _runs = {};
  final Map<String, AcpWebFailure> _failures = {};
  bool _disposed = false;

  bool running(String id) => _runs[id]?.ready == true;
  bool starting(String id) => _runs.containsKey(id) && !running(id);
  AcpWebFailure? failure(String id) => _failures[id];

  Future<void> open(
    AcpAgentSpec spec,
    AcpProviderInput provider, {
    required String cwd,
    List<Mount> mounts = const [],
    required Future<void> Function(String url) openBrowser,
  }) async {
    var run = _runs[spec.id];
    while (run != null && !run.matches(provider, cwd, mounts)) {
      await _stopRun(spec.id, run);
      run = _runs[spec.id];
    }
    if (run == null) {
      run = _WebRun(provider, cwd, mounts);
      _runs[spec.id] = run;
      _failures.remove(spec.id);
      _changed();
      run.started = _start(spec, provider, cwd, mounts, run);
    }
    final String url;
    try {
      url = await run.address.future;
    } catch (_) {
      await run.started;
      rethrow;
    }
    if (run.stopped || _runs[spec.id] != run) {
      throw const AcpWebException(AcpWebFailure.stopped);
    }
    await openBrowser(url);
  }

  Future<void> _start(
    AcpAgentSpec spec,
    AcpProviderInput provider,
    String cwd,
    List<Mount> mounts,
    _WebRun run,
  ) async {
    Timer? timer;
    try {
      final port = await _freePort();
      if (run.stopped) return;
      final (runtime, launch) = await prepare(
        spec,
        provider,
        port,
        '$acpConfigDir/web-${spec.id}',
      );
      if (run.stopped) return;
      run.runtime = runtime;
      timer = Timer(startTimeout, () {
        if (!run.address.isCompleted) {
          run.address.completeError(
            const AcpWebException(AcpWebFailure.timeout),
          );
        }
      });
      // Decode each pipe independently: stdout/stderr chunks may interleave.
      final lines = {
        for (final kind in OutputStreamKind.values) kind: StringBuffer(),
      };
      final decoders = {
        for (final kind in OutputStreamKind.values)
          kind: const Utf8Decoder(allowMalformed: true).startChunkedConversion(
            StringConversionSink.fromStringSink(lines[kind]!),
          ),
      };
      run.events = runtime
          .run(
            CommandRequest(
              runId: run.runId,
              command: [
                launch.command,
                ...launch.arguments,
              ].map(_quote).join(' '),
              cwd: cwd,
              mounts: mounts,
              env: launch.environment,
              timeout: Duration.zero,
              keepStdinOpen: true,
              emulateHardLinks: false,
              isCancelled: () => run.stopped,
            ),
          )
          .listen(
            (event) {
              switch (event) {
                case CommandOutput(:final kind, :final bytes):
                  if (run.address.isCompleted) return;
                  decoders[kind]!.add(bytes);
                  final text = lines[kind]!.toString();
                  lines[kind]!.clear();
                  final split = text.split('\n');
                  lines[kind]!.write(split.removeLast());
                  // Bound incomplete output in memory, without retaining a log.
                  if (lines[kind]!.length > 8192) lines[kind]!.clear();
                  for (final line in split) {
                    final clean = line.replaceAll(
                      RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'),
                      '',
                    );
                    for (final match in RegExp(
                      r'''http://127\.0\.0\.1:\d+(?:[/#?][^\s<>"']*)?''',
                    ).allMatches(clean)) {
                      final url = match.group(0)!;
                      final uri = Uri.tryParse(url);
                      if (uri == null ||
                          uri.host != '127.0.0.1' ||
                          uri.userInfo.isNotEmpty ||
                          uri.port < 1 ||
                          uri.port > 65535) {
                        continue;
                      }
                      // These agents print authenticated URLs. An earlier bare
                      // listening address must not lose the browser login token.
                      if (spec.id == AcpAgentSpec.kimiCodeId &&
                          Uri.splitQueryString(
                                uri.fragment,
                              )['token']?.isNotEmpty !=
                              true) {
                        continue;
                      }
                      if (spec.id == AcpAgentSpec.deepSeekHarnessId &&
                          uri.queryParameters['token']?.isNotEmpty != true) {
                        continue;
                      }
                      if (!run.address.isCompleted) {
                        run.ready = true;
                        run.address.complete(url);
                        _changed();
                      }
                    }
                  }
                case CommandExited():
                  _exited(spec.id, run);
                case CommandStarted():
              }
            },
            onError: (Object _) => _exited(spec.id, run),
            onDone: () => _exited(spec.id, run),
          );
      await run.address.future;
    } catch (error) {
      final failure = error is AcpWebException
          ? error.failure
          : AcpWebFailure.start;
      if (!run.address.isCompleted) {
        run.address.completeError(AcpWebException(failure));
      }
      if (!run.stopped) _failures[spec.id] = failure;
      await _stopRun(spec.id, run);
    } finally {
      timer?.cancel();
    }
  }

  void _exited(String id, _WebRun run) {
    if (run.stopped || _runs[id] != run) return;
    _failures[id] = AcpWebFailure.exited;
    if (!run.address.isCompleted) {
      run.address.completeError(const AcpWebException(AcpWebFailure.exited));
    }
    _runs.remove(id);
    run.ready = false;
    run.stopped = true;
    unawaited(run.events?.cancel());
    _changed();
  }

  Future<void> stop(String id) async {
    final run = _runs[id];
    if (run != null) await _stopRun(id, run);
  }

  Future<void> _stopRun(String id, _WebRun run) async {
    if (run.stopped) return;
    run.stopped = true;
    if (!run.address.isCompleted) {
      run.address.completeError(const AcpWebException(AcpWebFailure.stopped));
    }
    if (_runs[id] == run) _runs.remove(id);
    _changed();
    try {
      await run.runtime?.cancel(run.runId);
    } finally {
      await run.events?.cancel();
    }
  }

  Future<void> stopAll() async {
    await Future.wait([for (final id in _runs.keys.toList()) stop(id)]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) unawaited(stopAll());
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stopAll());
    super.dispose();
  }

  static Future<int> _loopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

class _WebRun {
  _WebRun(this.provider, this.cwd, List<Mount> mounts)
    : mounts = List.unmodifiable(mounts);
  final AcpProviderInput provider;
  final String cwd;
  final List<Mount> mounts;
  bool matches(
    AcpProviderInput input,
    String directory,
    List<Mount> bindings,
  ) =>
      cwd == directory &&
      listEquals(mounts, bindings) &&
      provider.baseUrl == input.baseUrl &&
      provider.apiKey == input.apiKey &&
      provider.model == input.model &&
      provider.anthropicProvider == input.anthropicProvider &&
      provider.responsesApi == input.responsesApi &&
      provider.imageInput == input.imageInput &&
      provider.contextWindow == input.contextWindow &&
      mapEquals(provider.headers, input.headers);
  final runId = 'acp-web-${const Uuid().v4()}';
  final address = Completer<String>();
  Future<void>? started;
  WorkspaceRuntime? runtime;
  StreamSubscription<CommandEvent>? events;
  bool ready = false;
  bool stopped = false;
}
