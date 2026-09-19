import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/tool_schema_override.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/tools/built_in_tool_catalog.dart';
import '../../../features/home/services/local_tools_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import '../widgets/tool_schema_ui.dart';
import 'tool_schema_editor_page.dart';

class ToolSchemaSettingsPage extends StatefulWidget {
  const ToolSchemaSettingsPage({super.key});

  @override
  State<ToolSchemaSettingsPage> createState() => _ToolSchemaSettingsPageState();
}

class _ToolSchemaSettingsPageState extends State<ToolSchemaSettingsPage> {
  @override
  void initState() {
    super.initState();
    DeviceLocalTools.prefetchIosCapabilities().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _confirmResetAll() async {
    final confirmed = await confirmResetAllToolSchemas(context);
    if (!confirmed || !mounted) return;
    await context.read<SettingsProvider>().resetAllToolSchemaOverrides();
  }

  Future<void> _setFullTrust(bool value) async {
    final settings = context.read<SettingsProvider>();
    if (!value) {
      await settings.setToolAutoApproveAll(false);
      return;
    }
    final confirmed = await confirmFullToolTrust(context);
    if (confirmed && mounted) {
      await settings.setToolAutoApproveAll(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final catalog = BuiltInToolCatalog.entries(
      lang: settings.resolvedMemoryPromptLang,
      legacyMemoryMode: settings.legacyMemoryMode,
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.toolSchemaSettingsPageTitle),
        actions: [
          Tooltip(
            message: l10n.toolSchemaSettingsResetAll,
            child: IosIconButton(
              icon: Lucide.RotateCcw,
              color: cs.onSurface,
              size: 20,
              minSize: 44,
              semanticLabel: l10n.toolSchemaSettingsResetAll,
              onTap: _confirmResetAll,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _approvalSection(context, settings),
          const SizedBox(height: 18),
          for (final group in BuiltInToolGroup.values)
            ..._groupSection(
              context,
              group: group,
              entries: catalog.where((e) => e.group == group).toList(),
              overrides: settings.toolSchemaOverrides,
            ),
        ],
      ),
    );
  }

  Widget _approvalSection(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            ru ? 'Подтверждения инструментов' : 'Tool approvals',
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ru
                            ? 'Я понимаю риск — разрешать всё'
                            : 'Full trust mode (dangerous)',
                        style: TextStyle(fontWeight: AppFontWeights.semibold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ru
                            ? 'Не спрашивать подтверждение перед действиями ИИ. '
                                  'Действует для браузера, MCP, shell, записи файлов и '
                                  'других инструментов, которые обычно требуют подтверждения.'
                            : 'Skip per-action confirmations for browser, MCP, shell, '
                                  'file writes, and other tools that normally require approval.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IosSwitch(
                  value: settings.toolAutoApproveAll,
                  onChanged: _setFullTrust,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _groupSection(
    BuildContext context, {
    required BuiltInToolGroup group,
    required List<BuiltInToolCatalogEntry> entries,
    required Map<String, ToolSchemaOverride> overrides,
  }) {
    if (entries.isEmpty) return const [];
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final title = switch (group) {
      BuiltInToolGroup.search => l10n.toolSchemaSettingsGroupSearch,
      BuiltInToolGroup.memory => l10n.toolSchemaSettingsGroupMemory,
      BuiltInToolGroup.local => l10n.toolSchemaSettingsGroupLocal,
      BuiltInToolGroup.workspace => l10n.workspacesTitle,
    };
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      if (group == BuiltInToolGroup.memory)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            l10n.toolSchemaSettingsMemoryLangNote,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      SectionCard(
        padding: EdgeInsets.zero,
        children: [
          for (final entry in entries)
            ToolSchemaToolRow(
              entry: entry,
              schemaOverride: overrides[entry.name],
              onTap: () => _openEditor(context, entry, overrides[entry.name]),
            ),
        ],
      ),
      const SizedBox(height: 18),
    ];
  }

  Future<void> _openEditor(
    BuildContext context,
    BuiltInToolCatalogEntry entry,
    ToolSchemaOverride? schemaOverride,
  ) async {
    final result = await Navigator.of(context).push<ToolSchemaOverride?>(
      MaterialPageRoute(
        builder: (_) => ToolSchemaEditorPage(
          toolName: entry.name,
          defaultDefinition: entry.defaultDefinition,
          initialOverride: schemaOverride,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await context.read<SettingsProvider>().setToolSchemaOverride(
      entry.name,
      result,
    );
  }
}
