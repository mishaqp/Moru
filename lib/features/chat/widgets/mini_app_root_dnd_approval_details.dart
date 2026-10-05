import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/services/tool_approval_service.dart';

/// Root DND selected by the host, independent of the model's original inputs.
class MiniAppRootDndApprovalDetails extends StatelessWidget {
  const MiniAppRootDndApprovalDetails({
    super.key,
    required this.modes,
    this.textColor,
  });

  final List<String> modes;
  final Color? textColor;

  static MiniAppRootDndApprovalDetails? fromRequest(
    ToolApprovalRequest? request, {
    Color? textColor,
  }) {
    if (request == null || !request.toolName.startsWith('ma_')) return null;
    final operations = request.arguments['root_dnd_operations'];
    if (operations is! List) return null;
    final modes = <String>[];
    for (final operation in operations) {
      if (operation is! Map || operation['handler'] != 'device.root.dnd.set') {
        continue;
      }
      final arguments = operation['args'];
      if (arguments is! Map) continue;
      final mode = arguments['mode'];
      if (mode is String &&
          const {'all', 'priority', 'alarms', 'none'}.contains(mode)) {
        modes.add(mode);
      }
    }
    return modes.isEmpty
        ? null
        : MiniAppRootDndApprovalDetails(modes: modes, textColor: textColor);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String label(String mode) => switch (mode) {
      'all' => l10n.phonePanelDndAll,
      'priority' => l10n.phonePanelDndPriority,
      'alarms' => l10n.phonePanelDndAlarms,
      _ => l10n.phonePanelDndNone,
    };
    final style = TextStyle(fontSize: 12, height: 1.4, color: textColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.miniAppsNativeRootWarning, style: style),
        const SizedBox(height: 6),
        for (final mode in modes)
          Text('${l10n.phonePanelDnd}: ${label(mode)}', style: style),
      ],
    );
  }
}
