import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../database/business_preferences.dart';
import '../../providers/environment_provider.dart';
import '../mcp/workspace_stdio_transport.dart';
import '../sandbox/environment_dependencies.dart';
import '../workspace/workspace_runtime.dart';
import 'acp_agent.dart';
import 'acp_agent_catalog.dart';
import 'acp_stdio_channel.dart';
import 'acp_error_messages.dart';
import '../../../l10n/app_localizations.dart';

enum AcpInstallState { unknown, missing, installed }

/// Why the last install, removal or check did not work.
enum AcpAgentFailure {
  /// The Linux environment is not installed or not running.
  noEnvironment,

  /// Node.js could not be installed.
  node,
  install,
  remove,

  /// The agent started but did not speak ACP, or exited.
  check,
}

/// The result of starting an agent and greeting it.
class AcpCheckResult {
  const AcpCheckResult({this.info, this.error, this.failureKind});

  final AcpAgentInfo? info;
  final String? error;
  final AcpFailureKind? failureKind;
  String? errorMessage(AppLocalizations l10n) =>
      acpFailureMessage(failureKind, l10n) ?? error;
  bool get ok => info != null;
}

/// Installs, removes and checks agents in the Linux environment, and starts
/// them for chats. One instance for the app; leaving the screen keeps an
/// install running.
class AcpAgentManager extends ChangeNotifier {
  AcpAgentManager({
    required this.preferences,
    required this.runtimeProvider,
    required this.environment,
    this.dependencies,
    this.clientVersion = '0',
  }) {
    loaded = _load();
  }

  static const String customAgentsKey = 'acp_custom_agents_v1';

  final BusinessPreferences preferences;
  final WorkspaceRuntimeProvider runtimeProvider;
  final EnvironmentProvider environment;
  EnvironmentDependencies? dependencies;
  final String clientVersion;
  late final Future<void> loaded;

  final Map<String, AcpInstallState> _states = {};
  final Map<String, AcpCheckResult> _checks = {};
  List<AcpAgentSpec> _custom = const [];
  final List<int> _log = [];
  String? _runId;
  String? busyAgentId;
  bool probing = false;
  AcpAgentFailure? failure;
  AcpFailureKind? failureKind;
  String? failedAgentId;

  List<AcpAgentSpec> get agents => [...AcpAgentSpec.builtIn, ..._custom];
  List<AcpAgentSpec> get customAgents => _custom;

  AcpAgentSpec? agent(String id) {
    for (final spec in agents) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  AcpInstallState state(String id) => _states[id] ?? AcpInstallState.unknown;
  AcpCheckResult? lastCheck(String id) => _checks[id];
  String get log => utf8.decode(_log, allowMalformed: true);
  bool get busy => busyAgentId != null || probing;

  WorkspaceStdioRuntime? get _runtime {
    final runtime = runtimeProvider.runtime;
    return runtime is WorkspaceStdioRuntime ? runtime : null;
  }

  bool get environmentAvailable => _runtime != null;

  Future<void> _load() async {
    final raw = preferences.getString(customAgentsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _custom = List.unmodifiable([
        for (final item in list)
          if (item is Map &&
              item['id'] is String &&
              item['name'] is String &&
              item['command'] is String)
            AcpAgentSpec.custom(
              id: item['id'] as String,
              name: item['name'] as String,
              command: item['command'] as String,
              arguments: [
                for (final arg in item['arguments'] as List? ?? const [])
                  arg.toString(),
              ],
            ),
      ]);
      notifyListeners();
    } on FormatException {
      // A damaged list starts empty; the agents themselves stay installed.
    }
  }

  Future<void> _saveCustom() => preferences.setString(
    customAgentsKey,
    jsonEncode([
      for (final spec in _custom)
        {
          'id': spec.id,
          'name': spec.name,
          'command': spec.command,
          'arguments': spec.arguments,
        },
    ]),
  );

  /// Adds (or replaces, with the same [id]) an agent started by [command].
  Future<AcpAgentSpec> saveCustomAgent({
    String? id,
    required String name,
    required String command,
    List<String> arguments = const [],
  }) async {
    await loaded;
    final spec = AcpAgentSpec.custom(
      id: id ?? const Uuid().v4(),
      name: name.trim(),
      command: command.trim(),
      arguments: arguments,
    );
    _custom = List.unmodifiable([
      for (final existing in _custom)
        if (existing.id != spec.id) existing,
      spec,
    ]);
    _states.remove(spec.id);
    _checks.remove(spec.id);
    await _saveCustom();
    notifyListeners();
    unawaited(refresh());
    return spec;
  }

  Future<void> deleteCustomAgent(String id) async {
    await loaded;
    _custom = List.unmodifiable([
      for (final existing in _custom)
        if (existing.id != id) existing,
    ]);
    _states.remove(id);
    _checks.remove(id);
    await _saveCustom();
    notifyListeners();
  }

  /// Looks up which agents are installed.
  Future<void> refresh() async {
    final runtime = _runtime;
    if (runtime == null || busy) return;
    probing = true;
    notifyListeners();
    try {
      final specs = agents;
      final script = [
        for (final spec in specs)
          'if command -v ${_quote(spec.command)} >/dev/null 2>&1; then '
              "echo '__acp_${spec.id}=1'; else echo '__acp_${spec.id}=0'; fi",
      ].join('\n');
      final (code, output) = await _run(runtime, script, capture: true);
      if (code == 0) {
        for (final spec in specs) {
          if (output.contains('__acp_${spec.id}=1')) {
            _states[spec.id] = AcpInstallState.installed;
          } else if (output.contains('__acp_${spec.id}=0')) {
            _states[spec.id] = AcpInstallState.missing;
          }
        }
      }
    } catch (_) {
      // The next refresh tries again; states stay unknown meanwhile.
    } finally {
      probing = false;
      notifyListeners();
    }
  }

  /// Installs or updates [spec], with Node.js first when it is missing.
  Future<void> install(AcpAgentSpec spec) async {
    if (busy || spec.installScript.isEmpty) return;
    final runtime = _runtime;
    failedAgentId = spec.id;
    if (runtime == null) {
      failure = AcpAgentFailure.noEnvironment;
      failureKind = null;
      notifyListeners();
      return;
    }
    busyAgentId = spec.id;
    failure = null;
    failureKind = null;
    _log.clear();
    notifyListeners();
    try {
      final deps = dependencies;
      if (deps != null) {
        if (deps.status(EnvironmentDependency.node) ==
            DependencyStatus.unknown) {
          await deps.refresh();
        }
        if (deps.status(EnvironmentDependency.node) !=
            DependencyStatus.installed) {
          _append('Node.js…\n');
          await deps.install(EnvironmentDependency.node);
          _append(deps.log);
          if (deps.status(EnvironmentDependency.node) !=
              DependencyStatus.installed) {
            failure = AcpAgentFailure.node;
            failureKind = classifyAcpFailure(deps.log);
            return;
          }
        }
      }
      final (code, _) = await _run(
        runtime,
        spec.installScript,
        timeout: const Duration(minutes: 30),
      );
      if (code != 0) {
        failure = AcpAgentFailure.install;
        failureKind = classifyAcpFailure(log);
        return;
      }
      _states[spec.id] = AcpInstallState.installed;
      _checks.remove(spec.id);
      failedAgentId = null;
    } catch (error) {
      _append('\n$error\n');
      failure = AcpAgentFailure.install;
      failureKind = classifyAcpFailure(error);
    } finally {
      busyAgentId = null;
      _runId = null;
      notifyListeners();
    }
  }

  /// Removes a built-in agent's npm packages.
  Future<void> uninstall(AcpAgentSpec spec) async {
    final runtime = _runtime;
    if (busy || runtime == null || spec.isCustom) return;
    final packages = RegExp(r'(@[\w.-]+/[\w.-]+|opencode-ai)')
        .allMatches(spec.installScript)
        .map((match) => match.group(0)!)
        .toSet()
        .join(' ');
    busyAgentId = spec.id;
    failure = null;
    failureKind = null;
    failedAgentId = spec.id;
    _log.clear();
    notifyListeners();
    try {
      final (code, _) = await _run(
        runtime,
        'npm uninstall -g --prefix $acpNpmPrefix $packages\n'
        'rm -f $acpNpmPrefix/bin/${spec.command}\n',
        timeout: const Duration(minutes: 5),
      );
      if (code != 0) {
        failure = AcpAgentFailure.remove;
        failureKind = classifyAcpFailure(log);
        return;
      }
      _states[spec.id] = AcpInstallState.missing;
      _checks.remove(spec.id);
      failedAgentId = null;
    } finally {
      busyAgentId = null;
      _runId = null;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    final runtime = _runtime;
    final id = _runId;
    if (runtime != null && id != null) await runtime.cancel(id);
    await dependencies?.cancel();
  }

  /// Starts [spec] for [provider], greets it and stops it again.
  Future<AcpCheckResult> check(
    AcpAgentSpec spec,
    AcpProviderInput provider,
  ) async {
    if (busy) return const AcpCheckResult(error: 'busy');
    busyAgentId = spec.id;
    failure = null;
    failureKind = null;
    failedAgentId = null;
    notifyListeners();
    AcpAgent? agent;
    AcpCheckResult result;
    try {
      agent = await start(spec, provider);
      result = AcpCheckResult(info: agent.info);
      _states[spec.id] = AcpInstallState.installed;
    } catch (error) {
      result = AcpCheckResult(
        error: error is AcpError ? error.message : error.toString(),
        failureKind: classifyAcpFailure(error),
      );
      failure = AcpAgentFailure.check;
      failureKind = result.failureKind;
      failedAgentId = spec.id;
    } finally {
      agent?.close();
      busyAgentId = null;
    }
    _checks[spec.id] = result;
    notifyListeners();
    return result;
  }

  /// Starts [spec] for [provider] in [cwd] and greets it. The caller owns the
  /// agent and closes it.
  Future<AcpAgent> start(
    AcpAgentSpec spec,
    AcpProviderInput provider, {
    String cwd = '/root',
    List<Mount> mounts = const [],
    bool Function()? isCancelled,
  }) async {
    final runtime = _runtime;
    if (runtime == null) {
      throw const AcpError(
        AcpError.disconnected,
        'The Linux environment is not ready',
      );
    }
    final launch = spec.launch(provider);
    final variables = (await environment.loadExecutionConfig()).variables;
    final env = {...variables, ...launch.environment};
    if (launch.files.isNotEmpty) {
      final (code, output) = await _run(
        runtime,
        writeFilesScript(launch.files),
        capture: true,
        environment: env,
      );
      if (code != 0) {
        throw AcpError(
          AcpError.internalError,
          'Could not write the agent settings: $output',
        );
      }
    }
    final transport = await WorkspaceStdioTransport.start(
      runtime: runtime,
      command: launch.command,
      arguments: launch.arguments,
      cwd: cwd,
      mounts: mounts,
      environment: env,
      isCancelled: isCancelled,
    );
    return AcpAgent.start(
      AcpStdioChannel(transport),
      clientVersion: clientVersion,
    );
  }

  /// Writes [files] through base64, so no content can break the script.
  @visibleForTesting
  static String writeFilesScript(List<AcpConfigFile> files) => [
    'set -e',
    'umask 077',
    for (final file in files) ...[
      'mkdir -p ${_quote(_dirname(file.path))}',
      "printf '%s' '${base64.encode(utf8.encode(file.content))}' | "
          'base64 -d > ${_quote(file.path)}',
    ],
  ].join('\n');

  static String _dirname(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  void _append(String text) {
    _log.addAll(utf8.encode(text));
    notifyListeners();
  }

  Future<(int, String)> _run(
    WorkspaceRuntime runtime,
    String script, {
    Duration timeout = const Duration(minutes: 1),
    bool capture = false,
    Map<String, String>? environment,
  }) async {
    final id = 'acp-${const Uuid().v4()}';
    if (!capture) _runId = id;
    final env =
        environment ??
        {
          ...(await this.environment.loadExecutionConfig()).variables,
          'PATH':
              '$acpNpmPrefix/bin:/usr/local/sbin:/usr/local/bin:'
              '/usr/sbin:/usr/bin:/sbin:/bin',
        };
    final output = <int>[];
    var code = -1;
    await for (final event in runtime.run(
      CommandRequest(
        runId: id,
        command: script,
        cwd: '/root',
        timeout: timeout,
        env: env,
      ),
    )) {
      switch (event) {
        case CommandOutput(:final bytes):
          if (capture) {
            output.addAll(bytes);
          } else {
            _log.addAll(bytes);
            notifyListeners();
          }
        case CommandExited(:final exitCode):
          code = exitCode;
        case CommandStarted():
          break;
      }
    }
    return (code, utf8.decode(output, allowMalformed: true));
  }
}
