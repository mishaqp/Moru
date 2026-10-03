import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../database/business_preferences.dart';
import '../../models/agent_auth_mode.dart';
import '../../providers/environment_provider.dart';
import '../mcp/workspace_stdio_transport.dart';
import '../sandbox/environment_dependencies.dart';
import '../workspace/workspace_runtime.dart';
import 'acp_agent.dart';
import 'acp_agent_auth.dart';
import 'acp_agent_catalog.dart';
import 'acp_config_leases.dart';
import 'acp_launch_directories.dart';
import 'acp_mcp_stdio_bridge.dart';
import 'acp_mcp_probe.dart';
import 'acp_stdio_channel.dart';
import 'acp_secret_redactor.dart';
import 'acp_error_messages.dart';
import 'acp_fs_compat.dart';
import 'acp_agent_web_servers.dart';
import '../../../l10n/app_localizations.dart';

enum AcpInstallState { unknown, missing, installed }

/// Why the last install, removal or check did not work.
enum AcpAgentFailure {
  /// The Linux environment is not installed or not running.
  noEnvironment,

  /// Node.js could not be installed.
  node,
  nodeVersion,
  install,
  remove,

  /// The agent started but did not speak ACP, or exited.
  check,
}

/// The result of starting an agent and greeting it.
class AcpCheckResult {
  const AcpCheckResult({
    this.info,
    this.error,
    this.errorDetails,
    this.failureKind,
    this.moruToolsAvailable = false,
    this.nodeIssue,
    this.authStatus,
  });

  final AcpAgentInfo? info;
  final String? error;
  final String? errorDetails;
  final AcpFailureKind? failureKind;
  final bool moruToolsAvailable;
  final AcpNodeIssue? nodeIssue;
  final AcpAuthStatus? authStatus;
  String? errorMessage(AppLocalizations l10n) =>
      nodeIssue?.message(l10n) ?? acpFailureMessage(failureKind, l10n) ?? error;
  bool get ok => info != null && error == null;
}

class AcpNodeIssue {
  const AcpNodeIssue(this.agent, this.requiredVersion, this.actual);
  final String agent;
  final String requiredVersion;
  final String actual;
  String message(AppLocalizations l10n) => l10n.agentsNodeVersionRequired(
    agent,
    requiredVersion,
    actual.isEmpty ? l10n.agentsNodeVersionUnknown : actual,
  );
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
  String _nodeVersion = '';
  bool _nodeProbed = false;
  AcpAgentWebServers? _webServers;
  AcpAgentAuth? _auth;
  final _configLeases = AcpConfigLeases();
  final _launchDirectories = AcpLaunchDirectories();
  final Set<_ManagedAgentRun> _agentRuns = {};
  final Set<String> _removing = {};
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _removeConfigs(
    WorkspaceRuntime runtime,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return;
    await _run(
      runtime,
      'rm -f -- ${paths.map(_quote).join(' ')}',
      capture: true,
      environment: const {'PATH': '/usr/bin:/bin'},
    );
  }

  Future<void> _stopAgentRuns(String specId, {AgentAuthMode? authMode}) async {
    await Future.wait([
      for (final run in _agentRuns.toList())
        if (run.specId == specId &&
            (authMode == null || run.authMode == authMode))
          run.stop(),
    ]);
  }

  static List<String> _ownedConfigPaths(AcpAgentSpec spec) => switch (spec.id) {
    AcpAgentSpec.codexId => ['$acpConfigDir/codex/config.toml'],
    AcpAgentSpec.openCodeId => [
      '$acpConfigDir/opencode.json',
      '$acpConfigDir/web-opencode/opencode.json',
    ],
    AcpAgentSpec.kimiCodeId => [
      '$acpConfigDir/kimi-code/config.toml',
      '$acpConfigDir/web-kimi-code/kimi-code/config.toml',
    ],
    AcpAgentSpec.deepSeekHarnessId => [
      '$acpConfigDir/deepseek-harness/moru.yaml',
      '$acpConfigDir/web-deepseek-harness/deepseek-harness/moru.yaml',
    ],
    _ => [],
  };

  AcpAgentWebServers get webServers =>
      _webServers ??= (AcpAgentWebServers(prepare: _prepareWeb)
        ..addListener(notifyListeners));

  AcpAgentAuth get auth => _auth ??= (AcpAgentAuth(
    prepare: _prepareAuth,
    stopAgents: (id) =>
        _stopAgentRuns(id, authMode: AgentAuthMode.subscription),
  )..addListener(notifyListeners));

  AcpNodeIssue? nodeIssueFor(AcpAgentSpec spec) {
    if (!_nodeProbed) return null;
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(_nodeVersion);
    final major = int.tryParse(match?.group(1) ?? '') ?? 0;
    final minor = int.tryParse(match?.group(2) ?? '') ?? 0;
    final compatible =
        (major > spec.nodeMajor ||
            (major == spec.nodeMajor && minor >= spec.nodeMinor)) &&
        (spec.id != AcpAgentSpec.deepSeekHarnessId || major != 23);
    return compatible
        ? null
        : AcpNodeIssue(
            spec.name,
            spec.id == AcpAgentSpec.deepSeekHarnessId
                ? '≥22.19.0 <23.0.0 / ≥24.0.0'
                : '≥${spec.minimumNodeVersion}',
            _nodeVersion,
          );
  }

  String nodeUpdateHint(AppLocalizations l10n) {
    final state = environment.state;
    if ((state.distro == 'ubuntu' &&
            (state.version?.startsWith('24.04') == true ||
                state.version?.startsWith('22.04') == true)) ||
        (state.distro == 'debian' && state.version?.split('.').first == '12')) {
      return l10n.agentsNodeUpdateDebian;
    }
    if (state.distro == 'alpine') return l10n.agentsNodeUpdateAlpine;
    return l10n.agentsNodeUpdateUnknown;
  }

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
        "printf '__moru_node='; node --version 2>/dev/null || true",
        "printf '\\n'",
        for (final spec in specs)
          'if command -v ${_quote(spec.command)} >/dev/null 2>&1; then '
              "echo '__acp_${spec.id}=1'; else echo '__acp_${spec.id}=0'; fi",
      ].join('\n');
      final (code, output) = await _run(runtime, script, capture: true);
      if (code == 0) {
        _recordNode(output);
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
      await _ensureNode(runtime, spec);
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
      failure = nodeIssueFor(spec) != null
          ? AcpAgentFailure.nodeVersion
          : AcpAgentFailure.install;
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
    _removing.add(spec.id);
    final packages = spec.uninstallPackages.join(' ');
    busyAgentId = spec.id;
    failure = null;
    failureKind = null;
    failedAgentId = spec.id;
    _log.clear();
    notifyListeners();
    try {
      final stoppingAgents = _stopAgentRuns(spec.id);
      await _auth?.cancelOperations(spec.id);
      await _webServers?.stop(spec.id);
      await _webServers?.waitForCleanup(spec.id);
      await stoppingAgents;
      final (code, _) = await _run(
        runtime,
        [
          'set -e',
          'npm uninstall -g --prefix $acpNpmPrefix $packages',
          if (_ownedConfigPaths(spec).isNotEmpty)
            'rm -f -- ${_ownedConfigPaths(spec).map(_quote).join(' ')}',
          'rm -f $acpNpmPrefix/bin/${spec.command}',
        ].join('\n'),
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
    } catch (error) {
      _append('\n$error\n');
      failure = AcpAgentFailure.remove;
      failureKind = classifyAcpFailure(error);
    } finally {
      _removing.remove(spec.id);
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
    AcpProviderInput? provider, {
    AgentAuthMode authMode = AgentAuthMode.provider,
  }) async {
    if (busy) return const AcpCheckResult(error: 'busy');
    busyAgentId = spec.id;
    failure = null;
    failureKind = null;
    failedAgentId = null;
    notifyListeners();
    AcpAgent? agent;
    var ownsAgent = false;
    AcpCheckResult result;
    var moruToolsAvailable = false;
    var redactor = AcpSecretRedactor([
      provider?.apiKey ?? '',
      ...?provider?.headers.values,
    ], protectAuthentication: authMode == AgentAuthMode.subscription);
    AcpAuthStatus? authStatus;
    try {
      final variables = (await environment.loadExecutionConfig()).variables;
      redactor = AcpSecretRedactor([
        provider?.apiKey ?? '',
        ...?provider?.headers.values,
        variables['OPENCODE_SERVER_PASSWORD'] ?? '',
      ], protectAuthentication: authMode == AgentAuthMode.subscription);
      final runtime = _runtime;
      if (runtime != null) {
        moruToolsAvailable = await AcpMcpProbe.check(
          runtime,
          environment: {
            ...variables,
            'PATH':
                '$acpNpmPrefix/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
          },
        );
      }
      if (authMode == AgentAuthMode.subscription) {
        authStatus = await auth.check(spec);
      }
      if (spec.id == AcpAgentSpec.codexId &&
          authMode == AgentAuthMode.subscription) {
        for (final run in _agentRuns) {
          if (run.specId == spec.id &&
              run.authMode == authMode &&
              !run.stopped &&
              run.agent?.isAlive == true) {
            agent = run.agent;
            break;
          }
        }
      }
      if (agent == null) {
        agent = await start(spec, provider, authMode: authMode);
        ownsAgent = true;
      }
      if (authStatus == AcpAuthStatus.signedOut) {
        throw const AcpError(AcpError.authRequired, 'Authentication required');
      }
      if (authMode == AgentAuthMode.subscription) {
        if (authStatus != AcpAuthStatus.signedIn) {
          throw const AcpError(
            AcpError.internalError,
            'Could not check authentication',
          );
        }
        if (ownsAgent) await agent.newSession(cwd: '/root');
      }
      result = AcpCheckResult(
        info: agent.info,
        authStatus: authStatus,
        moruToolsAvailable: moruToolsAvailable,
      );
      _states[spec.id] = AcpInstallState.installed;
    } catch (error) {
      final safeError = redactor.error(error);
      final kind = classifyAcpFailure(safeError);
      if (authMode == AgentAuthMode.subscription &&
          kind == AcpFailureKind.authRequired) {
        authStatus = AcpAuthStatus.signedOut;
        auth.requireSignIn(spec.id);
      }
      result = AcpCheckResult(
        authStatus: authStatus,
        moruToolsAvailable: moruToolsAvailable,
        error: safeError.message,
        errorDetails: acpErrorDetails(safeError),
        failureKind: kind,
        nodeIssue: nodeIssueFor(spec),
      );
      failure = AcpAgentFailure.check;
      failureKind = result.failureKind;
      failedAgentId = spec.id;
    } finally {
      if (ownsAgent) agent?.close();
      busyAgentId = null;
    }
    _checks[spec.id] = result;
    notifyListeners();
    // A command that is not there means the installed state is stale.
    if (result.error != null && isAcpCommandMissing(result.error!)) {
      await refresh();
    }
    return result;
  }

  /// Starts [spec] for [provider] in [cwd] and greets it. The caller owns the
  /// agent and closes it.
  Future<AcpAgent> start(
    AcpAgentSpec spec,
    AcpProviderInput? provider, {
    AgentAuthMode authMode = AgentAuthMode.provider,
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
    bool credentialsChanging() =>
        authMode == AgentAuthMode.subscription &&
        _auth?.changingCredentials(spec.id) == true;
    if (_disposed || _removing.contains(spec.id) || credentialsChanging()) {
      throw const AcpError(AcpError.disconnected, 'Agent startup cancelled');
    }
    final previousRuns =
        spec.id == AcpAgentSpec.codexId &&
            authMode == AgentAuthMode.subscription
        ? _agentRuns
              .where((run) => run.specId == spec.id && run.authMode == authMode)
              .toList()
        : const <_ManagedAgentRun>[];
    if (previousRuns.any(
      (run) => !run.stopped && run.agent?.isAlive != false,
    )) {
      throw const AcpError(
        AcpError.internalError,
        'Codex is active in another chat',
        null,
        AcpFailureKind.accountBusy,
      );
    }
    // Reserve before any await. Another startup cannot overtake teardown and
    // refresh the same native auth.json while the old process is still alive.
    final run = _ManagedAgentRun(spec.id, authMode);
    _agentRuns.add(run);
    unawaited(run.closed.future.then((_) => _agentRuns.remove(run)));
    bool cancelled() =>
        run.stopped ||
        _disposed ||
        credentialsChanging() ||
        isCancelled?.call() == true;
    void requireActive() {
      if (cancelled()) {
        throw const AcpError(AcpError.disconnected, 'Agent startup cancelled');
      }
    }

    var redactor = AcpSecretRedactor([
      provider?.apiKey ?? '',
      ...?provider?.headers.values,
    ], protectAuthentication: authMode == AgentAuthMode.subscription);
    AcpStderrBuffer? stderrDiagnostics;
    try {
      await Future.wait(previousRuns.map((run) => run.stop()));
      requireActive();
      final variables = (await environment.loadExecutionConfig()).variables;
      requireActive();
      redactor = AcpSecretRedactor([
        provider?.apiKey ?? '',
        ...?provider?.headers.values,
        variables['OPENCODE_SERVER_PASSWORD'] ?? '',
      ], protectAuthentication: authMode == AgentAuthMode.subscription);
      // Root runs already have their own private mount namespace. Keep
      // Codex's fixed daemon path apart from the Android-owned PRoot copy.
      final expectedRootChroot = spec.id == AcpAgentSpec.codexId
          ? (await runtime.status()).rootChroot
          : null;
      final isolateCodexDaemon = expectedRootChroot == true;
      requireActive();
      final launch = spec.launch(
        provider,
        authMode: authMode,
        isolateCodexDaemon: isolateCodexDaemon,
      );
      await _requireNode(runtime, spec, redactor: redactor);
      requireActive();
      run.cleanup = await _configLeases.acquire(
        runtime,
        launch.files,
        (paths) => _removeConfigs(runtime, paths),
      );
      final directory = launch.temporaryDirectory;
      if (directory != null) {
        final removeConfigs = run.cleanup!;
        final removeDirectory = _launchDirectories.acquire(
          runtime,
          directory,
          () async {
            await _run(
              runtime,
              AcpLaunchDirectories.removeScript(directory),
              capture: true,
              environment: const {'PATH': '$acpNpmPrefix/bin:/usr/bin:/bin'},
            );
          },
        );
        run.cleanup = () async {
          try {
            await removeDirectory();
          } finally {
            await removeConfigs();
            await launch.cleanup?.call();
          }
        };
      }
      requireActive();
      final env = _agentEnvironment(variables, launch);
      {
        final (code, output) = await _run(
          runtime,
          launch.unsetEnvironmentScript +
              writeFilesScript([
                ...launch.files,
                AcpMcpStdioBridge.file,
                AcpFsCompat.file,
              ]) +
              _subscriptionHomeScript(launch) +
              (directory == null
                  ? ''
                  : '\n${_launchDirectories.prepareScript(runtime, directory)}'),
          capture: true,
          environment: env,
          expectedRootChroot: expectedRootChroot,
        );
        if (code != 0) {
          throw AcpError(
            AcpError.internalError,
            'Could not write the agent settings: $output',
          );
        }
      }
      requireActive();
      stderrDiagnostics = redactor.stderrBuffer();
      final transport = await WorkspaceStdioTransport.start(
        runtime: runtime,
        command: directory == null && launch.unsetEnvironment.isEmpty
            ? launch.command
            : '/bin/sh',
        arguments: directory == null && launch.unsetEnvironment.isEmpty
            ? launch.arguments
            : directory != null
            ? AcpLaunchDirectories.arguments(launch)
            : [
                '-c',
                'set -e\numask 077\n${launch.unsetEnvironmentScript}exec ${[launch.command, ...launch.arguments].map(_quote).join(' ')}',
              ],
        cwd: cwd,
        mounts: mounts,
        environment: env,
        isCancelled: cancelled,
        emulateHardLinks: false,
        expectedRootChroot: expectedRootChroot,
        stderrFilter: stderrDiagnostics.addBytes,
      );
      run.transport = transport;
      unawaited(transport.onClose.then((_) => run.stop()));
      requireActive();
      final agent = await AcpAgent.start(
        AcpStdioChannel(transport, diagnostics: stderrDiagnostics),
        clientVersion: clientVersion,
        redactor: redactor,
      );
      run.agent = agent;
      requireActive();
      return agent;
    } catch (error) {
      if (!run.prepared.isCompleted) run.prepared.complete();
      await run.stop();
      throw redactor.error(error, failureKind: stderrDiagnostics?.failureKind);
    } finally {
      if (!run.prepared.isCompleted) run.prepared.complete();
    }
  }

  void _recordNode(String output, {AcpSecretRedactor? redactor}) {
    final marker = RegExp(
      r'^__moru_node=([^\r\n]*)',
      multiLine: true,
    ).firstMatch(output);
    final version = marker?.group(1)?.trim() ?? '';
    // Valid version numbers are control data; unexpected output is diagnostic.
    _nodeVersion = RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(version)
        ? version
        : redactor?.text(version) ?? version;
    _nodeProbed = true;
  }

  Future<void> _requireNode(
    WorkspaceRuntime runtime,
    AcpAgentSpec spec, {
    AcpSecretRedactor? redactor,
  }) async {
    if (spec.nodeMajor < 22) return;
    await _probeNode(runtime, redactor: redactor);
    _throwNodeIssue(spec);
  }

  /// Before an installation: Debian and Ubuntu ship an older Node than
  /// the agents need (12 to 20), so it is replaced with Node 24 from
  /// NodeSource. Alpine's own packages are new enough.
  Future<void> _ensureNode(WorkspaceRuntime runtime, AcpAgentSpec spec) async {
    await _probeNode(runtime);
    if (nodeIssueFor(spec) == null) return;
    _append('Node.js 24 (NodeSource)…\n');
    await _run(
      runtime,
      AcpAgentSpec.nodeUpgradeScript,
      timeout: const Duration(minutes: 15),
    );
    await _probeNode(runtime);
    _throwNodeIssue(spec);
  }

  Future<void> _probeNode(
    WorkspaceRuntime runtime, {
    AcpSecretRedactor? redactor,
  }) async {
    final (_, output) = await _run(
      runtime,
      "printf '__moru_node='; node --version 2>/dev/null || true; printf '\\n'",
      capture: true,
    );
    _recordNode(output, redactor: redactor);
    notifyListeners();
  }

  void _throwNodeIssue(AcpAgentSpec spec) {
    final issue = nodeIssueFor(spec);
    if (issue != null) {
      throw AcpError(
        AcpError.internalError,
        '${issue.agent} requires Node.js ${issue.requiredVersion}; detected ${issue.actual}',
      );
    }
  }

  /// The user's variables, the agent's own, and the hard-link shim that
  /// agents need because they run without PRoot's fake links.
  static Map<String, String> _agentEnvironment(
    Map<String, String> variables,
    AcpLaunch launch,
  ) {
    final env = {
      for (final entry in variables.entries)
        if (launch.unsetEnvironment.isEmpty ||
            !AcpAgentSpec.isSubscriptionEnvironmentVariable(entry.key))
          entry.key: entry.value,
      ...launch.environment,
    };
    env['NODE_OPTIONS'] = AcpFsCompat.nodeOptions(env['NODE_OPTIONS']);
    return env;
  }

  /// Native login and ACP share only persistent credentials. Every native
  /// command still owns its temporary files and the prepared runtime mode.
  Future<AcpAuthContext> _prepareAuth(AcpAgentSpec spec) async {
    final runtime = _runtime;
    if (runtime == null || _disposed || _removing.contains(spec.id)) {
      throw const AcpError(
        AcpError.disconnected,
        'The Linux environment is not ready',
      );
    }
    final variables = (await environment.loadExecutionConfig()).variables;
    final redactor = AcpSecretRedactor(const [], protectAuthentication: true);
    await _requireNode(runtime, spec, redactor: redactor);
    final expectedRootChroot = (await runtime.status()).rootChroot;
    final launch = spec.launch(
      null,
      authMode: AgentAuthMode.subscription,
      isolateCodexDaemon: spec.id == AcpAgentSpec.codexId && expectedRootChroot,
    );
    final directory = launch.temporaryDirectory;
    final env = _agentEnvironment(variables, launch);
    final cleanup = directory == null
        ? () async {}
        : _launchDirectories.acquire(runtime, directory, () async {
            await _run(
              runtime,
              AcpLaunchDirectories.removeScript(directory),
              capture: true,
              environment: const {'PATH': '$acpNpmPrefix/bin:/usr/bin:/bin'},
            );
          });
    try {
      final (code, _) = await _run(
        runtime,
        launch.unsetEnvironmentScript +
            writeFilesScript([AcpFsCompat.file]) +
            _subscriptionHomeScript(launch) +
            (directory == null
                ? ''
                : '\n${_launchDirectories.prepareScript(runtime, directory)}'),
        capture: true,
        environment: env,
        expectedRootChroot: expectedRootChroot,
      );
      if (code != 0) {
        throw const AcpError(
          AcpError.internalError,
          'Could not prepare authentication',
        );
      }
      if (_disposed || _removing.contains(spec.id)) {
        throw const AcpError(AcpError.disconnected, 'Authentication cancelled');
      }
      return AcpAuthContext(
        runtime: runtime,
        expectedRootChroot: expectedRootChroot,
        launch: AcpLaunch(
          command: launch.command,
          arguments: launch.arguments,
          environment: env,
          temporaryDirectory: directory,
          isolateCodexDaemon: launch.isolateCodexDaemon,
          unsetEnvironment: launch.unsetEnvironment,
          cleanup: cleanup,
        ),
      );
    } catch (_) {
      await cleanup();
      rethrow;
    }
  }

  static String _subscriptionHomeScript(AcpLaunch launch) {
    if (launch.unsetEnvironment.isEmpty) return '';
    final home =
        launch.environment['CLAUDE_CONFIG_DIR'] ??
        launch.environment['CODEX_HOME'];
    return home == null
        ? ''
        : '\nmkdir -p -- ${_quote(home)}\nchmod 700 -- ${_quote(home)}';
  }

  Future<(WorkspaceRuntime, AcpLaunch)> _prepareWeb(
    AcpAgentSpec spec,
    AcpProviderInput provider,
    int port,
    String directory,
  ) async {
    final runtime = _runtime;
    if (runtime == null) throw const AcpWebException(AcpWebFailure.start);
    final variables = (await environment.loadExecutionConfig()).variables;
    final redactor = AcpSecretRedactor([
      provider.apiKey,
      ...provider.headers.values,
      variables['OPENCODE_SERVER_PASSWORD'] ?? '',
    ]);
    await _requireNode(runtime, spec, redactor: redactor);
    final launch = spec.webLaunch(
      provider,
      port: port,
      configDirectory: directory,
    );
    if (launch == null) throw const AcpWebException(AcpWebFailure.start);
    if (_disposed || _removing.contains(spec.id)) {
      throw const AcpWebException(AcpWebFailure.stopped);
    }
    final cleanup = await _configLeases.acquire(
      runtime,
      launch.files,
      (paths) => _removeConfigs(runtime, paths),
    );
    try {
      final env = _agentEnvironment(variables, launch);
      final (code, _) = await _run(
        runtime,
        writeFilesScript([...launch.files, AcpFsCompat.file]),
        capture: true,
        environment: env,
      );
      if (code != 0) throw const AcpWebException(AcpWebFailure.start);
      return (
        runtime,
        AcpLaunch(
          command: launch.command,
          arguments: launch.arguments,
          environment: env,
          files: launch.files,
          cleanup: cleanup,
        ),
      );
    } catch (_) {
      await cleanup();
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _webServers?.removeListener(notifyListeners);
    _webServers?.dispose();
    _auth?.removeListener(notifyListeners);
    _auth?.dispose();
    for (final run in _agentRuns.toList()) {
      unawaited(run.stop());
    }
    super.dispose();
  }

  /// Writes [files] through base64, so no content can break the script.
  @visibleForTesting
  static String writeFilesScript(List<AcpConfigFile> files) => [
    'set -e',
    'umask 077',
    for (final file in files) ...[
      'mkdir -p ${_quote(_dirname(file.path))}',
      if (file.temporary) ...[
        'touch -- ${_quote(file.path)}',
        'chmod 600 ${_quote(file.path)}',
      ],
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
    bool? expectedRootChroot,
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
        expectedRootChroot: expectedRootChroot,
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

class _ManagedAgentRun {
  _ManagedAgentRun(this.specId, this.authMode);
  final String specId;
  final AgentAuthMode authMode;
  final prepared = Completer<void>();
  final closed = Completer<void>();
  WorkspaceStdioTransport? transport;
  AcpAgent? agent;
  Future<void> Function()? cleanup;
  bool stopped = false;
  Future<void>? _closing;

  Future<void> stop() {
    stopped = true;
    agent?.close();
    transport?.close();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await prepared.future;
      agent?.close();
      transport?.close();
      await transport?.onClose;
      await cleanup?.call();
    } catch (_) {
      // Closing must not publish guest diagnostics or leave async errors.
    } finally {
      closed.complete();
    }
  }
}
