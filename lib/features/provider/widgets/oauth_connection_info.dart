import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/provider_oauth.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import 'oauth_account_card.dart';

/// Read-only account connection details. Credentials are never rendered here.
class OAuthConnectionInfo extends StatelessWidget {
  const OAuthConnectionInfo({super.key, required this.config});

  final ProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final credentials = config.oauthCredentials;
    final fields = <(String, String)>[
      (l.oauthEndpoint, config.oauthProvider!.baseUrl),
      if (config.oauthProvider!.scope.isNotEmpty)
        (l.oauthScope, config.oauthProvider!.scope),
      if (credentials?.accountId case final id?) (l.oauthAccountId, id),
      // OpenRouter's exchanged key has no expiry to show; the row is
      // skipped rather than displaying a placeholder.
      if (credentials?.expiresAt case final expiresAt?)
        (l.oauthTokenExpiry, oauthDisplayTime(context, expiresAt)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in fields)
          IosNavRow(
            label: label,
            subtitle: value,
            subtitleMaxLines: null,
            trailing: const Icon(LucideIcons.copy, size: 14),
            onTap: () => Clipboard.setData(ClipboardData(text: value)),
          ),
      ],
    );
  }
}
