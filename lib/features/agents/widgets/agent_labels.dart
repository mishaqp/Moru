import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/services/acp/acp_agent_catalog.dart';
import '../../../core/services/acp/acp_agent_manager.dart';
import '../../../l10n/app_localizations.dart';

IconData agentIcon(AcpAgentSpec spec) => switch (spec.id) {
  AcpAgentSpec.claudeCodeId => LucideIcons.sparkles,
  AcpAgentSpec.codexId => LucideIcons.codeXml,
  AcpAgentSpec.openCodeId => LucideIcons.squareTerminal,
  _ => LucideIcons.bot,
};

/// One line on what the agent is, for someone who has not heard of it.
String agentSummary(AppLocalizations l10n, AcpAgentSpec spec) =>
    switch (spec.id) {
      AcpAgentSpec.claudeCodeId => l10n.agentsDescClaudeCode,
      AcpAgentSpec.codexId => l10n.agentsDescCodex,
      AcpAgentSpec.openCodeId => l10n.agentsDescOpenCode,
      AcpAgentSpec.kimiCodeId => l10n.agentsDescKimiCode,
      AcpAgentSpec.deepSeekHarnessId => l10n.agentsDescDeepSeekHarness,
      _ => [spec.command, ...spec.arguments].join(' '),
    };

/// Which providers the agent works with.
String agentModelHint(AppLocalizations l10n, AcpAgentSpec spec) =>
    switch (spec.id) {
      AcpAgentSpec.claudeCodeId => l10n.agentsApiAnthropic,
      AcpAgentSpec.codexId => l10n.agentsApiCodex,
      AcpAgentSpec.openCodeId => l10n.agentsApiOpenai,
      AcpAgentSpec.kimiCodeId ||
      AcpAgentSpec.deepSeekHarnessId => l10n.agentsApiCompatible,
      _ => l10n.agentsApiCustom,
    };

String agentStatusLabel(
  AppLocalizations l10n,
  AcpAgentManager manager,
  AcpAgentSpec spec,
) {
  if (manager.busyAgentId == spec.id) return l10n.agentsStatusWorking;
  if (manager.probing && manager.state(spec.id) == AcpInstallState.unknown) {
    return l10n.agentsStatusChecking;
  }
  return switch (manager.state(spec.id)) {
    AcpInstallState.installed => l10n.agentsStatusInstalled,
    AcpInstallState.missing => l10n.agentsStatusMissing,
    AcpInstallState.unknown => '',
  };
}

String? agentFailureLabel(AppLocalizations l10n, AcpAgentFailure? failure) =>
    switch (failure) {
      AcpAgentFailure.noEnvironment => l10n.agentsNeedEnvironment,
      AcpAgentFailure.node => l10n.agentsFailureNode,
      AcpAgentFailure.nodeVersion => null,
      AcpAgentFailure.install => l10n.agentsFailureInstall,
      AcpAgentFailure.remove => l10n.agentsFailureRemove,
      // The check shows its own error text.
      AcpAgentFailure.check || null => null,
    };
