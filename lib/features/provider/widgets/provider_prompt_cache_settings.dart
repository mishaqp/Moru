import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/section_card.dart';
import 'prompt_cache_ttl_control.dart';

class ProviderPromptCacheSettings extends StatelessWidget {
  const ProviderPromptCacheSettings({super.key, required this.config});
  final ProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final ttl = ProviderConfig.resolveClaudePromptCachingTtl(
      config.claudePromptCachingTtl,
    );
    void saveTtl(String value) {
      final current = settings.getProviderConfig(config.id);
      settings.setProviderConfig(
        config.id,
        current.copyWith(claudePromptCachingTtl: value),
      );
    }

    return SectionCard(
      children: [
        IosNavRow(
          label: l.providerDetailPageClaudePromptCachingTitle,
          subtitle: l.oauthPromptCachingHelp,
          subtitleMaxLines: null,
          trailing: IosSwitch(
            value: config.claudePromptCachingEnabled == true,
            semanticLabel: l.providerDetailPageClaudePromptCachingTitle,
            onChanged: (value) {
              final current = settings.getProviderConfig(config.id);
              settings.setProviderConfig(
                config.id,
                current.copyWith(claudePromptCachingEnabled: value),
              );
            },
          ),
        ),
        if (config.claudePromptCachingEnabled == true)
          IosNavRow(
            label: l.providerDetailPageClaudePromptCachingTtlTitle,
            trailing: PromptCachingTtlSegmentedControl(
              value: ttl,
              fiveMinuteLabel: l.providerDetailPageClaudePromptCachingTtl5m,
              oneHourLabel: l.providerDetailPageClaudePromptCachingTtl1h,
              semanticLabel: l.providerDetailPageClaudePromptCachingTtlTitle,
              onChanged: saveTtl,
            ),
          ),
      ],
    );
  }
}
