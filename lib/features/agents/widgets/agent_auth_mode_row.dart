import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/agent_auth_mode.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/option_sheet.dart';
import 'agent_labels.dart';

/// An explicit, reversible choice for an assistant's agent authentication.
class AgentAuthModeRow extends StatelessWidget {
  const AgentAuthModeRow({
    super.key,
    required this.mode,
    required this.onSelected,
  });

  final AgentAuthMode mode;
  final Future<void> Function(AgentAuthMode)? onSelected;

  Future<void> _choose(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showOptionSheet<AgentAuthMode>(
      context,
      title: l10n.agentsAuthMode,
      selected: mode,
      items: [
        OptionSheetItem(
          value: AgentAuthMode.provider,
          icon: LucideIcons.keyRound,
          label: l10n.agentsAuthProvider,
          subtitle: l10n.agentsAuthProviderHint,
        ),
        OptionSheetItem(
          value: AgentAuthMode.subscription,
          icon: LucideIcons.userRound,
          label: l10n.agentsAuthSubscription,
          subtitle: l10n.agentsAuthSubscriptionHint,
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    await onSelected?.call(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IosNavRow(
      icon: LucideIcons.keyRound,
      label: l10n.agentsAuthMode,
      detailText: agentAuthModeLabel(l10n, mode),
      onTap: onSelected == null ? null : () => unawaited(_choose(context)),
    );
  }
}
