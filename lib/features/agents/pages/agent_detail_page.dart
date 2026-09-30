import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../core/services/acp/acp_agent_catalog.dart';
import '../../../core/services/acp/acp_agent_web_servers.dart';
import '../../../core/services/acp/acp_error_messages.dart';
import '../../../core/services/acp/acp_provider_input.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../agent_chat_start.dart';
import '../agent_web_start.dart';
import '../widgets/agent_labels.dart';
import '../widgets/agent_log_view.dart';
import 'agents_page.dart';

/// One agent: what it is, install / update / remove, and a connection check
/// with the default chat model.
class AgentDetailPage extends StatelessWidget {
  const AgentDetailPage({super.key, required this.agentId});

  final String agentId;

  static const Key installKey = ValueKey('agent-install');
  static const Key checkKey = ValueKey('agent-check');
  static const Key chatKey = ValueKey('agent-start-chat');
  static const Key removeKey = ValueKey('agent-remove');
  static const Key webOpenKey = ValueKey('agent-web-open');
  static const Key webStopKey = ValueKey('agent-web-stop');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final manager = context.watch<AcpAgentManager>();
    final settings = context.watch<SettingsProvider>();
    final spec = manager.agent(agentId);
    if (spec == null) {
      // A custom agent that was just deleted.
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final state = manager.state(spec.id);
    final busyHere = manager.busyAgentId == spec.id;
    final idle = !manager.busy && manager.environmentAvailable;
    final providerKey = settings.currentModelProvider;
    final modelId = settings.currentModelId;
    final provider = providerKey == null || modelId == null
        ? null
        : acpProviderInputFor(settings, providerKey, modelId);
    final check = manager.lastCheck(spec.id);
    final failure = manager.failedAgentId == spec.id ? manager.failure : null;
    final nodeIssue = manager.nodeIssueFor(spec);
    final hasWeb = [
      AcpAgentSpec.kimiCodeId,
      AcpAgentSpec.deepSeekHarnessId,
      AcpAgentSpec.openCodeId,
    ].contains(spec.id);
    final web = hasWeb ? manager.webServers : null;
    final webBusy =
        web?.starting(spec.id) == true || web?.running(spec.id) == true;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(spec.name),
        actions: [
          if (spec.isCustom)
            IosIconButton(
              icon: Lucide.Edit,
              onTap: () =>
                  unawaited(showCustomAgentDialog(context, existing: spec)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            children: [
              IosNavRow(
                icon: agentIcon(spec),
                label: spec.name,
                subtitle: agentSummary(l10n, spec),
                subtitleMaxLines: 4,
                trailing: Text(
                  agentStatusLabel(l10n, manager, spec),
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ),
            ],
          ),
          IosSectionFooter(text: agentModelHint(l10n, spec)),
          if (!manager.environmentAvailable)
            _Notice(text: l10n.agentsNeedEnvironment, error: true),
          if (nodeIssue != null) ...[
            _Notice(text: nodeIssue.message(l10n), error: true),
            IosSectionFooter(text: manager.nodeUpdateHint(l10n)),
          ],
          if (web?.failure(spec.id) case final error?)
            _Notice(
              text: switch (error) {
                AcpWebFailure.start => l10n.agentsWebStartFailed,
                AcpWebFailure.timeout => l10n.agentsWebTimeout,
                AcpWebFailure.exited => l10n.agentsWebExited,
                AcpWebFailure.stopped => l10n.agentsWebStopped,
              },
              error: true,
            ),
          if (hasWeb && (state == AcpInstallState.installed || webBusy)) ...[
            IosTileButton(
              key: webOpenKey,
              icon: LucideIcons.globe,
              label: l10n.agentsWebOpen,
              enabled: provider != null && !web!.starting(spec.id) && idle,
              onTap: () async {
                try {
                  await openAgentWeb(context, spec, provider!);
                } catch (_) {
                  if (context.mounted) {
                    AppSnackBarManager().show(
                      context,
                      AppNotification(
                        message: l10n.agentsWebStartFailed,
                        type: NotificationType.error,
                      ),
                    );
                  }
                }
              },
            ),
            if (webBusy) ...[
              IosSectionFooter(
                text: web!.starting(spec.id)
                    ? l10n.agentsWebStarting
                    : l10n.agentsWebRunning,
              ),
              IosTileButton(
                key: webStopKey,
                icon: LucideIcons.square,
                label: l10n.agentsWebStop,
                onTap: () => unawaited(web.stop(spec.id)),
              ),
            ],
            if (spec.id == AcpAgentSpec.deepSeekHarnessId)
              IosSectionFooter(text: l10n.agentsWebDeepSeekWorkspace),
            const SizedBox(height: 12),
          ],
          if ((failure == null || failure == AcpAgentFailure.check
                  ? null
                  : acpFailureMessage(manager.failureKind, l10n) ??
                        agentFailureLabel(l10n, failure))
              case final text?)
            _Notice(text: text, error: true),
          if (check != null) ...[
            _Notice(
              text: check.ok
                  ? l10n.agentsCheckOk(
                      check.info!.name ?? spec.name,
                      check.info!.version ?? '',
                    )
                  : l10n.agentsCheckFailed(check.errorMessage(l10n) ?? ''),
              error: !check.ok,
            ),
            _Notice(
              text: check.moruToolsAvailable
                  ? l10n.agentsMoruToolsAvailable
                  : l10n.agentsMoruToolsUnavailable,
              error: !check.moruToolsAvailable,
            ),
          ],
          const SizedBox(height: 4),
          if (busyHere) ...[
            const Center(child: CircularProgressIndicator.adaptive()),
            const SizedBox(height: 12),
            IosTileButton(
              icon: Lucide.X,
              label: l10n.agentsCancel,
              onTap: () => unawaited(manager.cancel()),
            ),
          ] else ...[
            if (!spec.isCustom)
              IosTileButton(
                key: installKey,
                icon: state == AcpInstallState.installed
                    ? LucideIcons.refreshCw
                    : LucideIcons.download,
                label: state == AcpInstallState.installed
                    ? l10n.agentsUpdate
                    : l10n.agentsInstall,
                enabled: idle,
                backgroundColor: state == AcpInstallState.installed
                    ? null
                    : cs.primary,
                onTap: () => unawaited(manager.install(spec)),
              ),
            if (state == AcpInstallState.installed || spec.isCustom) ...[
              const SizedBox(height: 10),
              IosTileButton(
                key: chatKey,
                icon: LucideIcons.messageCirclePlus,
                label: l10n.agentsStartChat,
                enabled: provider != null,
                backgroundColor: cs.primary,
                onTap: () => unawaited(startAgentChat(context, spec)),
              ),
              const SizedBox(height: 10),
              IosTileButton(
                key: checkKey,
                icon: LucideIcons.plugZap,
                label: l10n.agentsCheck,
                enabled: idle && provider != null,
                onTap: () => unawaited(manager.check(spec, provider!)),
              ),
              IosSectionFooter(
                text: provider == null
                    ? l10n.agentsNoModel
                    : l10n.agentsCheckModel(modelId!),
              ),
            ],
            if (state == AcpInstallState.installed && !spec.isCustom) ...[
              const SizedBox(height: 4),
              IosTileButton(
                key: removeKey,
                icon: LucideIcons.trash2,
                label: l10n.agentsRemove,
                enabled: idle,
                foregroundColor: cs.error,
                onTap: () => unawaited(manager.uninstall(spec)),
              ),
            ],
            if (spec.isCustom) ...[
              const SizedBox(height: 4),
              IosTileButton(
                icon: LucideIcons.trash2,
                label: l10n.agentsCustomDelete,
                enabled: !manager.busy,
                foregroundColor: cs.error,
                onTap: () async {
                  await manager.deleteCustomAgent(spec.id);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
            ],
          ],
          if (manager.log.isNotEmpty &&
              (busyHere || manager.failedAgentId == spec.id)) ...[
            IosSectionHeader(text: l10n.agentsLog),
            AgentLogView(text: manager.log),
          ],
          if (spec.homepage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                spec.homepage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: error ? cs.error : cs.primary,
        ),
      ),
    );
  }
}
