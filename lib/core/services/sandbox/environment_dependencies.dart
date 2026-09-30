import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:Kelivo/core/services/sandbox/mirror_service.dart';

import 'package:Kelivo/core/models/environment_state.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

/// Packages the Linux environment offers, in the order shown, grouped by
/// [EnvironmentDependencyCommands.group]. The set follows what coding agents
/// need on Android (as OmniBot prepares it): a shell, search, build tools
/// and, on musl, the glibc compatibility layer.
enum EnvironmentDependency {
  node,
  python,
  git,
  bash,
  ripgrep,
  build,
  network,
  archive,
  processes,
  compat,
  ssh,
  sshpass,
  sshd,
}

enum DependencyGroup { development, ssh }

enum DependencyStatus { unknown, missing, installed }

enum DependencyFailure { check, install, cancelled }

extension EnvironmentDependencyCommands on EnvironmentDependency {
  DependencyGroup get group => switch (this) {
    EnvironmentDependency.ssh ||
    EnvironmentDependency.sshpass ||
    EnvironmentDependency.sshd => DependencyGroup.ssh,
    _ => DependencyGroup.development,
  };

  /// Whether the distribution has it at all: the glibc layer is for musl.
  bool available({required bool alpine}) =>
      this != EnvironmentDependency.compat || alpine;

  String packages({required bool alpine}) => switch (this) {
    EnvironmentDependency.python =>
      alpine
          ? 'python3 py3-pip py3-virtualenv'
          : 'python3 python3-pip python3-venv',
    EnvironmentDependency.node => 'nodejs npm',
    EnvironmentDependency.git => 'git',
    EnvironmentDependency.bash => 'bash',
    EnvironmentDependency.ripgrep => 'ripgrep',
    EnvironmentDependency.build =>
      alpine ? 'build-base linux-headers' : 'build-essential',
    EnvironmentDependency.network => 'curl wget',
    EnvironmentDependency.archive => 'zip unzip',
    EnvironmentDependency.processes => 'procps psmisc tmux',
    EnvironmentDependency.compat => alpine ? 'gcompat glib' : '',
    EnvironmentDependency.ssh =>
      alpine ? 'openssh-client-default' : 'openssh-client',
    EnvironmentDependency.sshpass => 'sshpass',
    EnvironmentDependency.sshd => 'openssh-server',
  };

  /// Succeeds when installed; its first line is shown as the version.
  String probe({required bool alpine}) => switch (this) {
    EnvironmentDependency.python =>
      'python3 --version && python3 -m pip --version && ${alpine ? 'virtualenv --version' : 'python3 -m venv --help'}',
    EnvironmentDependency.node => 'node --version && npm --version',
    EnvironmentDependency.git => 'git --version',
    EnvironmentDependency.bash => 'bash --version',
    EnvironmentDependency.ripgrep => 'rg --version',
    EnvironmentDependency.build => 'cc --version && make --version',
    EnvironmentDependency.ssh =>
      'ssh -V && command -v scp && command -v sftp && command -v ssh-keygen',
    EnvironmentDependency.network => 'curl --version && wget --version',
    // zip -v opens with a copyright line; its second line is the version.
    EnvironmentDependency.archive =>
      'zip -v >/dev/null && unzip -v >/dev/null && '
          'zip -v | sed -n "2s/^This is //p"',
    // procps' ps (BusyBox's has no --version), psmisc's killall, tmux.
    EnvironmentDependency.processes => 'ps --version && killall -V && tmux -V',
    EnvironmentDependency.compat =>
      'apk info -e gcompat && apk info -e glib && echo gcompat glib',
    EnvironmentDependency.sshpass => 'sshpass -V',
    EnvironmentDependency.sshd =>
      'test -x /usr/sbin/sshd && echo OpenSSH server',
  };
}

/// A process-wide installer: leaving the page does not lose progress or start
/// another package transaction. Installed state is probed from the guest.
class EnvironmentDependencies extends ChangeNotifier {
  EnvironmentDependencies({
    required this.runtime,
    required this.env,
    required bool alpine,
    required this.mirrors,
  }) : _defaultAlpine = alpine {
    env.addListener(_environmentChanged);
  }

  final WorkspaceRuntime runtime;
  final EnvironmentProvider env;
  final bool _defaultAlpine;
  bool get alpine =>
      env.state.distro == null ? _defaultAlpine : env.state.distro == 'alpine';
  bool get supportsPackages =>
      env.state.distro == null ||
      {'ubuntu', 'debian', 'alpine'}.contains(env.state.distro);
  final MirrorService mirrors;
  MirrorCancelToken? _mirrorCancel;
  final Map<EnvironmentDependency, DependencyStatus> _statuses = {};
  final Map<EnvironmentDependency, String> _versions = {};
  final List<int> _output = [];
  String? _runId;
  bool _cancelled = false;
  bool busy = false;

  /// What the running installation covers; empty when none runs.
  Set<EnvironmentDependency> installingAll = const {};
  EnvironmentDependency? get installing =>
      installingAll.isEmpty ? null : installingAll.first;
  EnvironmentDependency? lastInstalled;
  EnvironmentDependency? lastAttempt;
  DependencyFailure? failure;
  String get log => utf8.decode(_output, allowMalformed: true);
  DependencyStatus status(EnvironmentDependency dependency) =>
      _statuses[dependency] ?? DependencyStatus.unknown;

  /// The installed version's first line, e.g. `v24.1.0` or `ripgrep 14.1.1`.
  String? version(EnvironmentDependency dependency) => _versions[dependency];

  /// What this distribution offers, in display order.
  List<EnvironmentDependency> get offered => [
    for (final dependency in EnvironmentDependency.values)
      if (dependency.available(alpine: alpine)) dependency,
  ];

  void _environmentChanged() {
    if (env.state.phase != EnvironmentPhase.ready) {
      _statuses.clear();
      _versions.clear();
      lastInstalled = null;
      notifyListeners();
    }
  }

  String get probeScript => [
    for (final dependency in offered)
      'if moru_out=\$( ( ${dependency.probe(alpine: alpine)} ) 2>&1 ); then '
          "echo '__kelivo_dep_${dependency.name}=1'; "
          'printf "__kelivo_ver_${dependency.name}=%s\\n" '
          '"\$(printf "%s\\n" "\$moru_out" | head -n 1)"; else '
          "echo '__kelivo_dep_${dependency.name}=0'; fi",
  ].join('\n');

  /// Installs [dependencies]' packages one at a time, so a package the
  /// source lacks does not hold back the rest; fails if any failed. The
  /// probe afterwards shows which ones made it.
  String installScript(Iterable<EnvironmentDependency> dependencies) {
    final packages = [
      for (final dependency in dependencies)
        if (dependency.packages(alpine: alpine).isNotEmpty)
          dependency.packages(alpine: alpine),
    ].join(' ');
    final each = alpine
        ? 'apk --wait 60 add'
        : 'apt-get -o DPkg::Lock::Timeout=60 -o Acquire::Retries=2 '
              'install -y --no-install-recommends';
    final loop =
        'moru_failed=\n'
        'for moru_package in $packages; do\n'
        '  $each "\$moru_package" || '
        'moru_failed="\$moru_failed \$moru_package"\n'
        'done\n'
        '[ -z "\$moru_failed" ] || '
        '{ echo "Not installed:\$moru_failed" >&2; exit 1; }\n';
    if (alpine) return 'set -e\napk --wait 60 update\n$loop';
    return 'set -e\nexport DEBIAN_FRONTEND=noninteractive\n'
        'dpkg --configure -a\n'
        'apt-get -o DPkg::Lock::Timeout=60 -o Acquire::Retries=2 '
        '-o APT::Update::Error-Mode=any update\n'
        'apt-get -o DPkg::Lock::Timeout=60 -f install -y\n'
        '$each ca-certificates\n'
        '$loop';
  }

  Future<void> refresh() async {
    if (busy ||
        !supportsPackages ||
        env.state.phase != EnvironmentPhase.ready) {
      return;
    }
    busy = true;
    _cancelled = false;
    failure = null;
    notifyListeners();
    try {
      await _probe();
    } catch (_) {
      failure = _cancelled
          ? DependencyFailure.cancelled
          : DependencyFailure.check;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> install(EnvironmentDependency dependency) =>
      installAll({dependency});

  /// One transaction for several packages, as picked with the checkboxes.
  Future<void> installAll(Set<EnvironmentDependency> dependencies) async {
    final picked = dependencies.where(offered.contains).toSet();
    if (picked.isEmpty ||
        busy ||
        !supportsPackages ||
        env.state.phase != EnvironmentPhase.ready) {
      return;
    }
    busy = true;
    _cancelled = false;
    installingAll = picked;
    lastAttempt = picked.first;
    lastInstalled = null;
    failure = null;
    _output.clear();
    for (final dependency in picked) {
      _statuses[dependency] = DependencyStatus.unknown;
    }
    notifyListeners();
    try {
      _mirrorCancel = MirrorCancelToken();
      final categories = {
        alpine ? MirrorCategory.apk : MirrorCategory.apt,
        if (picked.contains(EnvironmentDependency.python)) MirrorCategory.pip,
        if (picked.contains(EnvironmentDependency.node)) MirrorCategory.npm,
      };
      for (final category in categories) {
        final selection = env.mirrors[category];
        if (selection == null) continue;
        final entry = selection.useMirror
            ? MirrorService.findEntry(
                category,
                id: selection.mirrorId,
                url: selection.selectedBaseUrl,
                arch: env.state.arch ?? 'arm64',
                distro: env.state.distro ?? 'ubuntu',
              )
            : MirrorService.officialEntry(
                category,
                arch: env.state.arch ?? 'arm64',
                distro: env.state.distro ?? 'ubuntu',
              );
        if (entry == null) throw StateError('Unknown package source');
        await mirrors.applyEntry(
          category,
          entry,
          manual: selection.manual,
          cancelToken: _mirrorCancel,
        );
      }
      if (_cancelled) throw StateError('Cancelled');
      Object? installError;
      try {
        await _run(
          installScript(picked),
          timeout: const Duration(minutes: 30),
          showOutput: true,
        );
      } catch (error) {
        installError = error;
      }
      if (_cancelled) throw StateError('Cancelled');
      // Probe even after a partial failure, so what did install shows so.
      await _probe();
      if (installError != null ||
          picked.any((d) => status(d) != DependencyStatus.installed)) {
        throw StateError('Installed commands failed verification');
      }
      lastInstalled = picked.first;
      await env.clearCachedDiskUsage();
    } catch (_) {
      failure = _cancelled
          ? DependencyFailure.cancelled
          : DependencyFailure.install;
    } finally {
      _mirrorCancel = null;
      installingAll = const {};
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!busy) return;
    _cancelled = true;
    _mirrorCancel?.cancel();
    final id = _runId;
    if (id != null) await runtime.cancel(id);
  }

  Future<void> _probe() async {
    final output = await _run(
      probeScript,
      timeout: const Duration(seconds: 90),
    );
    final lines = const LineSplitter().convert(output).toSet();
    final statuses = <EnvironmentDependency, DependencyStatus>{};
    final versions = <EnvironmentDependency, String>{};
    for (final dependency in offered) {
      final prefix = '__kelivo_dep_${dependency.name}=';
      final version = lines
          .where((line) => line.startsWith('__kelivo_ver_${dependency.name}='))
          .map((line) => line.substring(line.indexOf('=') + 1).trim())
          .where((text) => text.isNotEmpty)
          .firstOrNull;
      if (version != null) {
        versions[dependency] = version.length > 48
            ? '${version.substring(0, 47)}…'
            : version;
      }
      final installed = lines.contains('${prefix}1');
      final missing = lines.contains('${prefix}0');
      if (installed == missing) {
        throw const FormatException('Incomplete dependency probe');
      }
      statuses[dependency] = installed
          ? DependencyStatus.installed
          : DependencyStatus.missing;
    }
    _statuses.addAll(statuses);
    _versions
      ..removeWhere((dependency, _) => statuses.containsKey(dependency))
      ..addAll(versions);
  }

  Future<String> _run(
    String script, {
    required Duration timeout,
    bool showOutput = false,
  }) async {
    if (_cancelled) throw StateError('Cancelled');
    final id = _runId = 'dependency-${const Uuid().v4()}';
    final output = <int>[];
    CommandExited? exit;
    try {
      await for (final event in runtime.run(
        CommandRequest(runId: id, command: script, cwd: '/', timeout: timeout),
      )) {
        if (event is CommandOutput) {
          output.addAll(event.bytes);
          if (output.length > 65536) {
            output.removeRange(0, output.length - 65536);
          }
          if (showOutput) {
            _output.addAll(event.bytes);
            if (_output.length > 65536) {
              _output.removeRange(0, _output.length - 65536);
            }
            notifyListeners();
          }
        } else if (event is CommandExited) {
          exit = event;
          _cancelled = _cancelled || event.cancelled;
        }
      }
      if (exit == null ||
          exit.exitCode != 0 ||
          exit.timedOut ||
          exit.cancelled ||
          exit.interrupted ||
          _cancelled) {
        throw StateError('Dependency command failed');
      }
      return utf8.decode(output, allowMalformed: true);
    } finally {
      _runId = null;
    }
  }

  @override
  void dispose() {
    env.removeListener(_environmentChanged);
    super.dispose();
  }
}
