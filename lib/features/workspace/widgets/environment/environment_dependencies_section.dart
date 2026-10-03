import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/environment_state.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/sandbox/environment_dependencies.dart';
import 'package:Kelivo/core/services/acp/acp_agent_manager.dart';
import 'package:Kelivo/core/services/sandbox/mirror_service.dart';
import 'package:Kelivo/features/agents/pages/agent_detail_page.dart';
import 'package:Kelivo/features/agents/widgets/agent_labels.dart';
import 'package:Kelivo/features/workspace/widgets/environment/environment_chrome.dart';
import 'package:Kelivo/features/workspace/widgets/environment/environment_dialogs.dart';
import 'package:Kelivo/features/workspace/widgets/environment/environment_labels.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_checkbox.dart';
import 'package:Kelivo/shared/widgets/ios_settings_rows.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/shared/widgets/ios_tile_button.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';

String _title(AppLocalizations l10n, EnvironmentDependency dependency) =>
    switch (dependency) {
      EnvironmentDependency.python => 'Python',
      EnvironmentDependency.node => 'Node.js',
      EnvironmentDependency.git => 'Git',
      EnvironmentDependency.bash => 'Bash',
      EnvironmentDependency.ripgrep => 'ripgrep',
      EnvironmentDependency.build => l10n.workspaceEnvDependencyBuildTitle,
      EnvironmentDependency.network => l10n.workspaceEnvDependencyNetwork,
      EnvironmentDependency.archive => l10n.workspaceEnvDependencyArchive,
      EnvironmentDependency.processes =>
        l10n.workspaceEnvDependencyProcessesTitle,
      EnvironmentDependency.compat => l10n.workspaceEnvDependencyCompatTitle,
      EnvironmentDependency.ssh => l10n.workspaceEnvDependencySshTitle,
      EnvironmentDependency.sshpass => 'sshpass',
      EnvironmentDependency.sshd => l10n.workspaceEnvDependencySshdTitle,
    };
String _detail(AppLocalizations l10n, EnvironmentDependency dependency) =>
    switch (dependency) {
      EnvironmentDependency.python => l10n.workspaceEnvDependencyPython,
      EnvironmentDependency.node => l10n.workspaceEnvDependencyNode,
      EnvironmentDependency.git => l10n.workspaceEnvDependencyGit,
      EnvironmentDependency.bash => l10n.workspaceEnvDependencyBash,
      EnvironmentDependency.ripgrep => l10n.workspaceEnvDependencyRipgrep,
      EnvironmentDependency.build => l10n.workspaceEnvDependencyBuild,
      EnvironmentDependency.network => 'curl · wget',
      EnvironmentDependency.archive => 'zip · unzip',
      EnvironmentDependency.processes => 'ps · killall · tmux',
      EnvironmentDependency.compat => l10n.workspaceEnvDependencyCompat,
      EnvironmentDependency.ssh => l10n.workspaceEnvDependencySsh,
      EnvironmentDependency.sshpass => l10n.workspaceEnvDependencySshpass,
      EnvironmentDependency.sshd => l10n.workspaceEnvDependencySshd,
    };
IconData _icon(EnvironmentDependency dependency) => switch (dependency) {
  EnvironmentDependency.python => Lucide.Code,
  EnvironmentDependency.node => Lucide.Boxes,
  EnvironmentDependency.git => LucideIcons.gitBranch,
  EnvironmentDependency.bash => LucideIcons.squareTerminal,
  EnvironmentDependency.ripgrep => LucideIcons.fileSearch,
  EnvironmentDependency.build => LucideIcons.hammer,
  EnvironmentDependency.network => Lucide.Globe,
  EnvironmentDependency.archive => LucideIcons.archive,
  EnvironmentDependency.processes => LucideIcons.activity,
  EnvironmentDependency.compat => LucideIcons.layers,
  EnvironmentDependency.ssh => LucideIcons.key,
  EnvironmentDependency.sshpass => LucideIcons.keyRound,
  EnvironmentDependency.sshd => LucideIcons.server,
};

/// What coding agents need from the system: a shell, git, search, curl,
/// process tools and (on musl) the glibc layer, plus Node itself.
const agentDependencies = {
  EnvironmentDependency.node,
  EnvironmentDependency.git,
  EnvironmentDependency.bash,
  EnvironmentDependency.ripgrep,
  EnvironmentDependency.network,
  EnvironmentDependency.processes,
  EnvironmentDependency.compat,
};

String _status(
  AppLocalizations l10n,
  EnvironmentDependencies service,
  EnvironmentDependency dependency,
) {
  if (service.installingAll.contains(dependency)) {
    return l10n.workspaceEnvDependencyInstalling;
  }
  return switch (service.status(dependency)) {
    DependencyStatus.installed =>
      service.version(dependency) ?? l10n.workspaceEnvDependencyInstalled,
    DependencyStatus.missing => l10n.workspaceEnvPhaseNotInstalled,
    DependencyStatus.unknown => l10n.workspaceEnvDependencyUnknown,
  };
}

String? _failure(AppLocalizations l10n, DependencyFailure? failure) =>
    switch (failure) {
      DependencyFailure.check => l10n.workspaceEnvDependencyCheckFailed,
      DependencyFailure.install => l10n.workspaceEnvDependencyInstallFailed,
      DependencyFailure.cancelled => l10n.workspaceEnvErrorCancelled,
      null => null,
    };

/// The environment's packages, grouped like OmniBot's terminal setup:
/// development tools, the coding agents, SSH. Missing packages can be
/// ticked and installed in one go; a row opens its sources and log.
class EnvironmentDependenciesSection extends StatefulWidget {
  const EnvironmentDependenciesSection({
    super.key,
    required this.service,
    required this.enabled,
  });
  final EnvironmentDependencies service;
  final bool enabled;

  static const installSelectedKey = ValueKey('environment-install-selected');
  static const prepareAgentsKey = ValueKey('environment-prepare-agents');

  @override
  State<EnvironmentDependenciesSection> createState() =>
      _EnvironmentDependenciesSectionState();
}

class _EnvironmentDependenciesSectionState
    extends State<EnvironmentDependenciesSection> {
  final _selected = <EnvironmentDependency>{};

  EnvironmentDependencies get _service => widget.service;

  bool _missing(EnvironmentDependency dependency) =>
      _service.status(dependency) == DependencyStatus.missing;

  void _install(Set<EnvironmentDependency> dependencies) {
    final picked = dependencies.where(_missing).toSet();
    if (picked.isEmpty) return;
    setState(() => _selected.removeAll(picked));
    unawaited(_service.installAll(picked));
  }

  void _open(EnvironmentDependency dependency) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          EnvironmentDependencyPage(service: _service, dependency: dependency),
    ),
  );

  Widget _row(EnvironmentDependency dependency) {
    final l10n = AppLocalizations.of(context)!;
    final service = _service;
    final selectable = widget.enabled && !service.busy && _missing(dependency);
    return IosNavRow(
      key: ValueKey('environment-dependency-${dependency.name}'),
      // Ticked when installed, tickable when missing, like OmniBot's list.
      leading: IosCheckbox(
        key: ValueKey('environment-pick-${dependency.name}'),
        value:
            _selected.contains(dependency) ||
            service.status(dependency) == DependencyStatus.installed,
        size: 20,
        hitTestSize: 36,
        onChanged: selectable
            ? (value) => setState(
                () => value
                    ? _selected.add(dependency)
                    : _selected.remove(dependency),
              )
            : null,
      ),
      label: _title(l10n, dependency),
      subtitle: _detail(l10n, dependency),
      detailText: _status(l10n, service, dependency),
      onTap:
          widget.enabled &&
              (!service.busy || service.installingAll.contains(dependency))
          ? () => _open(dependency)
          : null,
    );
  }

  List<Widget> _group(List<EnvironmentDependency> dependencies) => [
    for (final (index, dependency) in dependencies.indexed) ...[
      if (index > 0) const EnvironmentRowDivider(),
      _row(dependency),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final agents = context.watch<AcpAgentManager?>();
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final service = _service;
        final offered = service.offered;
        _selected.removeWhere((d) => !_missing(d));
        final agentNeeds = agentDependencies
            .where(offered.contains)
            .where(_missing)
            .toSet();
        final checking = service.busy && service.installingAll.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IosSectionHeader(text: l10n.workspaceEnvGroupDevelopment),
            SectionCard(
              children: _group([
                for (final d in offered)
                  if (d.group == DependencyGroup.development) d,
              ]),
            ),
            if (agents != null) ...[
              IosSectionHeader(text: l10n.workspaceEnvGroupAgents),
              SectionCard(
                children: [
                  IosNavRow(
                    key: EnvironmentDependenciesSection.prepareAgentsKey,
                    icon: LucideIcons.wandSparkles,
                    label: l10n.workspaceEnvPrepareAgents,
                    subtitle: agentNeeds.isEmpty
                        ? l10n.workspaceEnvPrepareAgentsDone
                        : agentNeeds.map((d) => _title(l10n, d)).join(' · '),
                    subtitleMaxLines: 2,
                    trailing: const SizedBox.shrink(),
                    onTap:
                        widget.enabled && !service.busy && agentNeeds.isNotEmpty
                        ? () => _install(agentNeeds)
                        : null,
                  ),
                  for (final spec in agents.agents) ...[
                    const EnvironmentRowDivider(),
                    IosNavRow(
                      key: ValueKey('environment-agent-${spec.id}'),
                      icon: agentIcon(spec),
                      label: spec.name,
                      subtitle: agentSummary(l10n, spec),
                      detailText: agentStatusLabel(l10n, agents, spec),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AgentDetailPage(agentId: spec.id),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              IosSectionFooter(text: l10n.workspaceEnvGroupAgentsDetail),
            ],
            IosSectionHeader(text: l10n.workspaceEnvGroupSsh),
            SectionCard(
              children: _group([
                for (final d in offered)
                  if (d.group == DependencyGroup.ssh) d,
              ]),
            ),
            const SizedBox(height: 12),
            SectionCard(
              children: [
                IosNavRow(
                  icon: Lucide.RefreshCw,
                  label: checking
                      ? l10n.workspaceEnvDependencyChecking
                      : l10n.workspaceEnvDependencyRefresh,
                  trailing: checking
                      ? const EnvironmentInlineSpinner(radius: 8)
                      : const SizedBox.shrink(),
                  onTap: widget.enabled && !service.busy
                      ? () {
                          unawaited(service.refresh());
                          unawaited(agents?.refresh());
                        }
                      : null,
                ),
              ],
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              IosTileButton(
                key: EnvironmentDependenciesSection.installSelectedKey,
                icon: Lucide.Download,
                label: l10n.workspaceEnvInstallSelected(_selected.length),
                enabled: widget.enabled && !service.busy,
                backgroundColor: cs.primary,
                onTap: () => _install({..._selected}),
              ),
            ],
            if (service.installingAll.length > 1) ...[
              const SizedBox(height: 12),
              IosNavRow(
                icon: Lucide.Download,
                label: l10n.workspaceEnvDependencyInstalling,
                subtitle: service.installingAll
                    .map((d) => _title(l10n, d))
                    .join(' · '),
                trailing: const EnvironmentInlineSpinner(radius: 8),
                onTap: () => _open(service.installingAll.first),
              ),
            ],
            IosSectionFooter(
              text: widget.enabled
                  ? l10n.workspaceEnvDependenciesDetail
                  : l10n.workspaceEnvDependencyReadyFirst,
            ),
            if (_failure(l10n, service.failure) case final error?)
              IosSectionFooter(text: error),
          ],
        );
      },
    );
  }
}

class EnvironmentDependencyPage extends StatefulWidget {
  const EnvironmentDependencyPage({
    super.key,
    required this.service,
    required this.dependency,
  });
  final EnvironmentDependencies service;
  final EnvironmentDependency dependency;
  @override
  State<EnvironmentDependencyPage> createState() =>
      _EnvironmentDependencyPageState();
}

class _EnvironmentDependencyPageState extends State<EnvironmentDependencyPage> {
  bool _detecting = false;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final env = context.watch<EnvironmentProvider>();
    final mirrors = context.watch<MirrorService?>();
    final service = widget.service;
    final dependency = widget.dependency;
    final categories = <MirrorCategory>{
      service.alpine ? MirrorCategory.apk : MirrorCategory.apt,
      if (dependency == EnvironmentDependency.python) MirrorCategory.pip,
      if (dependency == EnvironmentDependency.node) MirrorCategory.npm,
    };
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final enabled =
            env.state.phase == EnvironmentPhase.ready &&
            !service.busy &&
            !_detecting;
        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            leading: IosIconButton(
              icon: Lucide.ArrowLeft,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            title: Text(_title(l10n, dependency)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              SectionCard(
                children: [
                  IosNavRow(
                    icon: _icon(dependency),
                    label: _title(l10n, dependency),
                    subtitle: _detail(l10n, dependency),
                    trailing: Text(
                      _status(l10n, service, dependency),
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    ),
                  ),
                ],
              ),
              IosSectionHeader(text: l10n.workspaceEnvDependencySources),
              SectionCard(
                children: [
                  for (final category in categories) ...[
                    if (category != categories.first)
                      const EnvironmentRowDivider(),
                    IosNavRow(
                      icon: Lucide.Package,
                      label: workspaceEnvCategoryLabel(l10n, category),
                      detailText: workspaceEnvSelectionLabel(
                        l10n,
                        env.mirrors[category],
                        category: category,
                      ),
                      onTap: enabled && mirrors != null
                          ? () => unawaited(
                              openMirrorPage(context, category: category),
                            )
                          : null,
                    ),
                  ],
                  const EnvironmentRowDivider(),
                  IosNavRow(
                    icon: Lucide.Gauge,
                    label: l10n.workspaceEnvDetectFastMirrors,
                    trailing: const SizedBox.shrink(),
                    onTap: enabled && mirrors != null
                        ? () async {
                            setState(() => _detecting = true);
                            try {
                              await runDetectFastMirrors(
                                context: context,
                                mirrors: mirrors,
                                categories: categories,
                              );
                            } finally {
                              if (mounted) setState(() => _detecting = false);
                            }
                          }
                        : null,
                  ),
                ],
              ),
              IosSectionFooter(text: l10n.workspaceEnvDependencySourcesDetail),
              if (_failure(
                    l10n,
                    service.lastAttempt == dependency ? service.failure : null,
                  )
                  case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
              if (service.busy) ...[
                const EnvironmentInlineSpinner(radius: 10),
                const SizedBox(height: 12),
                IosTileButton(
                  icon: Lucide.X,
                  label: l10n.workspaceEnvCancel,
                  onTap: () => unawaited(service.cancel()),
                ),
              ] else if (service.status(dependency) !=
                  DependencyStatus.installed)
                IosTileButton(
                  key: const ValueKey('environment-dependency-install'),
                  icon: Lucide.Download,
                  label: service.failure == DependencyFailure.install
                      ? l10n.workspaceEnvRetry
                      : l10n.workspaceEnvInstall,
                  enabled: enabled,
                  backgroundColor: cs.primary,
                  onTap: () => unawaited(service.install(dependency)),
                ),
              if (service.log.isNotEmpty &&
                  service.lastAttempt == dependency) ...[
                IosSectionHeader(text: l10n.workspaceEnvDependencyLog),
                _InstallationLog(text: service.log),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InstallationLog extends StatefulWidget {
  const _InstallationLog({required this.text});

  final String text;

  @override
  State<_InstallationLog> createState() => _InstallationLogState();
}

class _InstallationLogState extends State<_InstallationLog> {
  final _scrollController = ScrollController();
  bool _followTail = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_trackPosition);
    _scrollToTail();
  }

  @override
  void didUpdateWidget(covariant _InstallationLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _scrollToTail();
  }

  void _trackPosition() {
    _followTail = _scrollController.position.extentAfter <= 24;
  }

  void _scrollToTail() {
    if (!_followTail || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_followTail || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      child: SizedBox(
        key: const ValueKey('environment-dependency-log'),
        height: 240,
        width: double.infinity,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            primary: false,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.text,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
