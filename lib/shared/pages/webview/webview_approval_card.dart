import 'package:flutter/material.dart';

import '../../../features/home/services/browser_agent_actions.dart';
import '../../../features/home/services/tool_approval_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// The `browser_use` approval card. Deliberately offers only Deny and
/// Allow-once -- no "Always allow" here. Flipping the global trust switch
/// stays exclusively in the real settings screen (reached via
/// [onChangeTrustSettings]), so there is exactly one place that can turn it
/// on and exactly one source of truth for its state.
class BrowserApprovalCard extends StatelessWidget {
  const BrowserApprovalCard({
    super.key,
    required this.request,
    required this.siteUrl,
    required this.ru,
    required this.onApprove,
    required this.onDeny,
    required this.onChangeTrustSettings,
  });

  final ToolApprovalRequest request;
  final String? siteUrl;
  final bool ru;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onChangeTrustSettings;

  String? get _site {
    final url = siteUrl;
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url);
    final host = uri?.host;
    return (host == null || host.isEmpty) ? url : host;
  }

  String get _action => (request.arguments['action'] ?? '').toString();

  Object? get _elementId => request.arguments['element_id'];

  String? get _evalJsCode => _action == 'eval_js'
      ? (request.arguments['code'] ?? '').toString().trim()
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final action = BrowserAgentActions.byId(_action);
    final actionLabel = action == null
        ? _action
        : (ru ? action.labelRu : action.labelEn);
    final site = _site;
    final elementId = _elementId;
    final code = _evalJsCode;

    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('browser_approval_card'),
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Lucide.Shield, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      site == null
                          ? l10n.browserApprovalHeadingUnknownSite
                          : l10n.browserApprovalHeading(site),
                      style: TextStyle(
                        fontWeight: AppFontWeights.semibold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.browserApprovalAction(actionLabel),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (elementId != null) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.browserApprovalElement(elementId.toString()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
              if (code != null && code.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.browserApprovalCodeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 4),
                // Fully scrollable and unclipped -- a long script must be
                // readable in full before it is approved, not just its
                // first few lines.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        code,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('browser_approval_change_trust'),
                  onPressed: onChangeTrustSettings,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l10n.browserApprovalChangeTrust,
                    style: TextStyle(fontSize: 12.5, color: cs.primary),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('browser_approval_deny'),
                    onPressed: onDeny,
                    child: Text(l10n.browserApprovalDeny),
                  ),
                  FilledButton(
                    key: const ValueKey('browser_approval_allow'),
                    onPressed: onApprove,
                    child: Text(l10n.browserApprovalAllow),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
