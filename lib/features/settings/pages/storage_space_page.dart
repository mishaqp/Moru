import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/native_file_save.dart';
import '../../../core/services/storage/storage_usage_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../backup/pages/local_snapshots_page.dart';
import '../../chat/pages/image_viewer_page.dart';
import '../../workspace/pages/environment_page.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/pages/workspaces_page.dart';
import 'log_viewer_page.dart';
import '../widgets/storage_contents_list.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';

part 'storage_category_page.dart';
part 'storage_space_widgets.dart';
part 'storage_upload_manager.dart';

Set<String>? _conversationIdsOrNull(BuildContext context) {
  try {
    return context
        .read<ChatService>()
        .getAllConversations()
        .map((conversation) => conversation.id)
        .toSet();
  } catch (_) {
    return null;
  }
}

class StorageSpacePage extends StatefulWidget {
  const StorageSpacePage({super.key});

  @override
  State<StorageSpacePage> createState() => _StorageSpacePageState();
}

class _StorageSpacePageState extends State<StorageSpacePage> {
  StorageUsageReport? _report;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshReport();
  }

  Future<StorageUsageReport?> _refreshReport() async {
    if (_loading) return _report;
    setState(() => _loading = true);
    try {
      final rep = await StorageUsageService.computeReport();
      if (!mounted) return rep;
      setState(() {
        _report = rep;
        _loading = false;
      });
      return rep;
    } catch (_) {
      if (!mounted) return null;
      setState(() => _loading = false);
      return null;
    }
  }

  String _fmtBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  Color _barColorFor(
    StorageUsageCategoryKey key,
    ColorScheme cs,
    AppSemanticColors appColors,
  ) {
    if (key == StorageUsageCategoryKey.other) {
      return cs.onSurface.withValues(alpha: 0.22);
    }
    const order = [
      StorageUsageCategoryKey.images,
      StorageUsageCategoryKey.files,
      StorageUsageCategoryKey.chatData,
      StorageUsageCategoryKey.legacyChatData,
      StorageUsageCategoryKey.restoreTraces,
      StorageUsageCategoryKey.displacedDatabases,
      StorageUsageCategoryKey.localSnapshots,
      StorageUsageCategoryKey.assistantData,
      StorageUsageCategoryKey.cache,
      StorageUsageCategoryKey.logs,
      StorageUsageCategoryKey.workspaceFiles,
      StorageUsageCategoryKey.sandboxEnvironment,
      StorageUsageCategoryKey.skills,
      StorageUsageCategoryKey.sessionFiles,
    ];
    final series = appColors.chartSeries;
    return series[order.indexOf(key) % series.length];
  }

  IconData _iconFor(StorageUsageCategoryKey key) {
    switch (key) {
      case StorageUsageCategoryKey.images:
        return Lucide.Image;
      case StorageUsageCategoryKey.files:
        return Lucide.Paperclip;
      case StorageUsageCategoryKey.chatData:
        return Lucide.MessagesSquare;
      case StorageUsageCategoryKey.legacyChatData:
        return Lucide.History;
      case StorageUsageCategoryKey.restoreTraces:
        return Lucide.RotateCcw;
      case StorageUsageCategoryKey.displacedDatabases:
        return Lucide.Database;
      case StorageUsageCategoryKey.localSnapshots:
        return Lucide.Shield;
      case StorageUsageCategoryKey.assistantData:
        return Lucide.Bot;
      case StorageUsageCategoryKey.cache:
        return Lucide.Boxes;
      case StorageUsageCategoryKey.logs:
        return Lucide.FileText;
      case StorageUsageCategoryKey.other:
        return Lucide.Box;
      case StorageUsageCategoryKey.workspaceFiles:
        return Lucide.FolderCode;
      case StorageUsageCategoryKey.sandboxEnvironment:
        return Lucide.Box;
      case StorageUsageCategoryKey.skills:
        return Lucide.WandSparkles;
      case StorageUsageCategoryKey.sessionFiles:
        return Lucide.Paperclip;
    }
  }

  String _titleFor(StorageUsageCategoryKey key, AppLocalizations l10n) {
    switch (key) {
      case StorageUsageCategoryKey.images:
        return l10n.storageSpaceCategoryImages;
      case StorageUsageCategoryKey.files:
        return l10n.storageSpaceCategoryFiles;
      case StorageUsageCategoryKey.chatData:
        return l10n.storageSpaceCategoryChatData;
      case StorageUsageCategoryKey.legacyChatData:
        return l10n.storageSpaceCategoryLegacyChatData;
      case StorageUsageCategoryKey.restoreTraces:
        return l10n.storageSpaceCategoryRestoreTraces;
      case StorageUsageCategoryKey.displacedDatabases:
        return l10n.storageSpaceCategoryDisplacedDatabases;
      case StorageUsageCategoryKey.localSnapshots:
        return l10n.localSnapshotSectionTitle;
      case StorageUsageCategoryKey.assistantData:
        return l10n.storageSpaceCategoryAssistantData;
      case StorageUsageCategoryKey.cache:
        return l10n.storageSpaceCategoryCache;
      case StorageUsageCategoryKey.logs:
        return l10n.storageSpaceCategoryLogs;
      case StorageUsageCategoryKey.other:
        return l10n.storageSpaceCategoryOther;
      case StorageUsageCategoryKey.workspaceFiles:
        return l10n.storageSpaceCategoryWorkspaceFiles;
      case StorageUsageCategoryKey.sandboxEnvironment:
        return l10n.storageSpaceCategorySandboxEnvironment;
      case StorageUsageCategoryKey.skills:
        return l10n.storageSpaceCategorySkills;
      case StorageUsageCategoryKey.sessionFiles:
        return l10n.storageSpaceCategorySessionFiles;
    }
  }

  String _subTitleFor(String id, AppLocalizations l10n) {
    switch (id) {
      case 'messages':
        return l10n.storageSpaceSubChatMessages;
      case 'conversations':
        return l10n.storageSpaceSubChatConversations;
      case 'tool_events_v1':
        return l10n.storageSpaceSubChatToolEvents;
      case 'sqlite_database':
        return l10n.storageSpaceSubChatDatabase;
      case 'sqlite_wal':
        return l10n.storageSpaceSubChatWriteAheadLog;
      case 'sqlite_shm':
        return l10n.storageSpaceSubChatSharedMemory;
      case 'completed_restore_runs':
        return l10n.storageSpaceSubCompletedRestoreRuns;
      case 'displaced_databases':
        return l10n.storageSpaceSubDisplacedDatabases;
      case 'local_snapshots':
        return l10n.localSnapshotEnabledSubtitle;
      case 'fonts':
        return l10n.storageSpaceCategoryFonts;
      case 'local_models':
        return l10n.storageSpaceCategoryLocalModels;
      case 'app':
        return l10n.storageSpaceSubOtherApp;
      case 'avatars':
        return l10n.storageSpaceSubAssistantAvatars;
      case 'images':
        return l10n.storageSpaceSubAssistantImages;
      case 'avatar_cache':
        return l10n.storageSpaceSubCacheAvatars;
      case 'other_cache':
        return l10n.storageSpaceSubCacheOther;
      case 'system_cache':
        return l10n.storageSpaceSubCacheSystem;
      case 'context_logs':
        return l10n.storageSpaceSubLogsContext;
      case 'flutter_logs':
        return l10n.storageSpaceSubLogsFlutter;
      case 'request_logs':
        return l10n.storageSpaceSubLogsRequests;
      case 'other_logs':
        return l10n.storageSpaceSubLogsOther;
      default:
        return id;
    }
  }

  Future<void> _openCategoryDetail(StorageUsageCategoryKey key) async {
    final report = _report;
    if (report == null) return;
    final l10n = AppLocalizations.of(context)!;
    final title = _titleFor(key, l10n);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StorageCategoryPage(
          title: title,
          categoryKey: key,
          initialReport: report,
          fmtBytes: _fmtBytes,
          subTitleFor: (id) => _subTitleFor(id, l10n),
          refreshReport: _refreshReport,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final body = _loading && _report == null
        ? const Center(child: CircularProgressIndicator())
        : _report == null
        ? Center(
            child: Text(
              l10n.storageSpaceLoadFailed,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
            ),
          )
        : _buildMobile(context, _report!);

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.storageSpacePageTitle),
        actions: [
          IosIconButton(
            icon: Lucide.RefreshCw,
            size: 20,
            minSize: 44,
            enabled: !_loading,
            onTap: _loading ? null : _refreshReport,
            semanticLabel: l10n.storageSpaceRefreshTooltip,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildMobile(BuildContext context, StorageUsageReport report) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final total = report.totalBytes;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.storageSpaceTotalLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _fmtBytes(total),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _UsageBar(
                  categories: report.categories,
                  totalBytes: total,
                  colorFor: (k) => _barColorFor(k, cs, context.appColors),
                ),
                const SizedBox(height: 10),
                _UsageLegend(
                  categories: report.categories,
                  colorFor: (k) => _barColorFor(k, cs, context.appColors),
                  titleFor: (k) => _titleFor(k, l10n),
                ),
                if (report.clearable.bytes > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.storageSpaceClearableHint(
                      _fmtBytes(report.clearable.bytes),
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            children: [
              for (int i = 0; i < report.categories.length; i++) ...[
                _iosNavRow(
                  context,
                  icon: _iconFor(report.categories[i].key),
                  label: _titleFor(report.categories[i].key, l10n),
                  detailText: _fmtBytes(report.categories[i].stats.bytes),
                  onTap: () => _openCategoryDetail(report.categories[i].key),
                ),
                if (i != report.categories.length - 1) _iosDivider(context),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
