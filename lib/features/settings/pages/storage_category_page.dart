part of 'storage_space_page.dart';

class _StorageCategoryPage extends StatefulWidget {
  const _StorageCategoryPage({
    required this.title,
    required this.categoryKey,
    required this.initialReport,
    required this.fmtBytes,
    required this.subTitleFor,
    required this.refreshReport,
  });

  final String title;
  final StorageUsageCategoryKey categoryKey;
  final StorageUsageReport initialReport;
  final String Function(int) fmtBytes;
  final String Function(String) subTitleFor;
  final Future<StorageUsageReport?> Function() refreshReport;

  @override
  State<_StorageCategoryPage> createState() => _StorageCategoryPageState();
}

class _StorageCategoryPageState extends State<_StorageCategoryPage> {
  late StorageUsageReport _report = widget.initialReport;
  bool _refreshing = false;
  bool _clearing = false;

  StorageUsageCategory _cat(StorageUsageCategoryKey k) =>
      _report.categories.firstWhere((c) => c.key == k);

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final next = await widget.refreshReport();
      if (!mounted) return;
      if (next != null) setState(() => _report = next);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.homePageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  Future<void> _clearCache({required bool avatarsOnly}) async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = avatarsOnly
        ? l10n.storageSpaceSubCacheAvatars
        : l10n.storageSpaceCategoryCache;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearCache(avatarsOnly: avatarsOnly);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearOtherCache() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceSubCacheOther;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearOtherCache();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearSystemCache() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceSubCacheSystem;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearSystemCache();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearLogs() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryLogs;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearLogs();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearLegacyChatData() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryLegacyChatData;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearLegacyChatDataConfirmMessage,
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearLegacyChatData();
      final next = await widget.refreshReport();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      if (next != null &&
          !next.categories.any(
            (category) =>
                category.key == StorageUsageCategoryKey.legacyChatData,
          )) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearDisplacedDatabases() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryDisplacedDatabases;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearDisplacedDatabasesConfirmMessage,
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearDisplacedDatabases();
      final next = await widget.refreshReport();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      if (next != null &&
          !next.categories.any(
            (category) =>
                category.key == StorageUsageCategoryKey.displacedDatabases,
          )) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearRestoreTraces() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryRestoreTraces;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearRestoreTracesConfirmMessage,
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearRestoreTraces();
      final next = await widget.refreshReport();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      if (next != null &&
          !next.categories.any(
            (category) => category.key == StorageUsageCategoryKey.restoreTraces,
          )) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearFonts() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryFonts;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearFonts();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearLocalModels() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryLocalModels;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearLocalModels();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearOrphanSessionFiles() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final conversationIds = _conversationIdsOrNull(context);
    final reclaimable = await StorageUsageService.measureOrphanSessionFiles(
      conversationIds: conversationIds,
    );
    if (!mounted) return;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSessionFilesCleanOrphansHint(
        widget.fmtBytes(reclaimable.bytes),
      ),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearOrphanSessionFiles(
        conversationIds: conversationIds,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(
          l10n.storageSpaceCategorySessionFiles,
        ),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final category = _cat(widget.categoryKey);

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: Theme.of(context).colorScheme.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(widget.title),
        actions: [
          IosIconButton(
            icon: Lucide.RefreshCw,
            size: 20,
            minSize: 44,
            enabled: !_refreshing,
            onTap: _refreshing ? null : _refresh,
            semanticLabel: l10n.storageSpaceRefreshTooltip,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _CategoryDetail(
          category: category,
          title: widget.title,
          fmtBytes: widget.fmtBytes,
          subTitleFor: widget.subTitleFor,
          clearing: _clearing,
          onClearCache: (category.key == StorageUsageCategoryKey.cache)
              ? _clearCache
              : null,
          onClearOtherCache: (category.key == StorageUsageCategoryKey.cache)
              ? _clearOtherCache
              : null,
          onClearSystemCache: (category.key == StorageUsageCategoryKey.cache)
              ? _clearSystemCache
              : null,
          onClearLogs: (category.key == StorageUsageCategoryKey.logs)
              ? _clearLogs
              : null,
          onClearLegacyChatData:
              (category.key == StorageUsageCategoryKey.legacyChatData)
              ? _clearLegacyChatData
              : null,
          onClearRestoreTraces:
              (category.key == StorageUsageCategoryKey.restoreTraces)
              ? _clearRestoreTraces
              : null,
          onClearDisplacedDatabases:
              (category.key == StorageUsageCategoryKey.displacedDatabases)
              ? _clearDisplacedDatabases
              : null,
          onClearFonts: (category.key == StorageUsageCategoryKey.other)
              ? _clearFonts
              : null,
          onClearLocalModels: (category.key == StorageUsageCategoryKey.other)
              ? _clearLocalModels
              : null,
          onCleanOrphanSessionFiles:
              (category.key == StorageUsageCategoryKey.sessionFiles)
              ? _clearOrphanSessionFiles
              : null,
          refreshReport: _refresh,
        ),
      ),
    );
  }
}

class _CategoryDetail extends StatelessWidget {
  const _CategoryDetail({
    required this.category,
    required this.title,
    required this.fmtBytes,
    required this.subTitleFor,
    required this.clearing,
    required this.onClearCache,
    required this.onClearOtherCache,
    required this.onClearSystemCache,
    required this.onClearLogs,
    required this.onClearLegacyChatData,
    required this.onClearRestoreTraces,
    required this.onClearDisplacedDatabases,
    required this.onClearFonts,
    required this.onClearLocalModels,
    required this.onCleanOrphanSessionFiles,
    required this.refreshReport,
  });

  final StorageUsageCategory category;
  final String title;
  final String Function(int) fmtBytes;
  final String Function(String) subTitleFor;
  final bool clearing;
  final Future<void> Function({required bool avatarsOnly})? onClearCache;
  final Future<void> Function()? onClearOtherCache;
  final Future<void> Function()? onClearSystemCache;
  final Future<void> Function()? onClearLogs;
  final Future<void> Function()? onClearLegacyChatData;
  final Future<void> Function()? onClearRestoreTraces;
  final Future<void> Function()? onClearDisplacedDatabases;
  final Future<void> Function()? onClearFonts;
  final Future<void> Function()? onClearLocalModels;
  final Future<void> Function()? onCleanOrphanSessionFiles;
  final Future<void> Function() refreshReport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final subtitle = fmtBytes(category.stats.bytes);
    final bool safeToClear =
        category.key == StorageUsageCategoryKey.cache ||
        category.key == StorageUsageCategoryKey.logs ||
        category.key == StorageUsageCategoryKey.legacyChatData ||
        category.key == StorageUsageCategoryKey.restoreTraces;
    final String hint = switch (category.key) {
      StorageUsageCategoryKey.legacyChatData =>
        l10n.storageSpaceLegacyChatDataHint,
      StorageUsageCategoryKey.restoreTraces =>
        l10n.storageSpaceRestoreTracesHint,
      StorageUsageCategoryKey.other => l10n.storageSpaceOtherHint,
      StorageUsageCategoryKey.workspaceFiles =>
        l10n.storageSpaceCategoryWorkspaceFilesHint,
      StorageUsageCategoryKey.sandboxEnvironment =>
        l10n.storageSpaceCategorySandboxEnvironmentHint,
      StorageUsageCategoryKey.skills => l10n.storageSpaceCategorySkillsHint,
      StorageUsageCategoryKey.sessionFiles =>
        l10n.storageSpaceCategorySessionFilesHint,
      _ =>
        safeToClear
            ? l10n.storageSpaceSafeToClearHint
            : l10n.storageSpaceNotSafeToClearHint,
    };

    Future<void> openManager(Widget page) async {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => page));
      await refreshReport();
    }

    Widget? actions;
    if (category.key == StorageUsageCategoryKey.cache) {
      actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          IosTileButton(
            label: l10n.storageSpaceClearAvatarCacheButton,
            icon: Lucide.User,
            backgroundColor: cs.primary,
            enabled: !clearing && onClearCache != null,
            onTap: () => onClearCache?.call(avatarsOnly: true),
          ),
          IosTileButton(
            label: l10n.storageSpaceClearCacheButton,
            icon: Lucide.Trash2,
            backgroundColor: cs.primary,
            enabled: !clearing && onClearCache != null,
            onTap: () => onClearCache?.call(avatarsOnly: false),
          ),
        ],
      );
    } else if (category.key == StorageUsageCategoryKey.logs) {
      actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          IosTileButton(
            label: l10n.storageSpaceViewLogsButton,
            icon: Lucide.Eye,
            backgroundColor: cs.primary,
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LogViewerPage()));
            },
          ),
          IosTileButton(
            label: l10n.storageSpaceClearLogsButton,
            icon: Lucide.Trash2,
            backgroundColor: cs.primary,
            enabled: !clearing && onClearLogs != null,
            onTap: () => onClearLogs?.call(),
          ),
        ],
      );
    } else if (category.key == StorageUsageCategoryKey.legacyChatData) {
      actions = IosTileButton(
        label: l10n.storageSpaceClearLegacyChatDataButton,
        icon: Lucide.Trash2,
        backgroundColor: cs.primary,
        enabled: !clearing && onClearLegacyChatData != null,
        onTap: () => onClearLegacyChatData?.call(),
      );
    } else if (category.key == StorageUsageCategoryKey.restoreTraces) {
      actions = IosTileButton(
        label: l10n.storageSpaceClearRestoreTracesButton,
        icon: Lucide.Trash2,
        backgroundColor: cs.primary,
        enabled: !clearing && onClearRestoreTraces != null,
        onTap: () => onClearRestoreTraces?.call(),
      );
    } else if (category.key == StorageUsageCategoryKey.displacedDatabases) {
      actions = IosTileButton(
        label: l10n.storageSpaceClearDisplacedDatabasesButton,
        icon: Lucide.Trash2,
        backgroundColor: cs.error,
        enabled: !clearing && onClearDisplacedDatabases != null,
        onTap: () => onClearDisplacedDatabases?.call(),
      );
    } else if (category.key == StorageUsageCategoryKey.localSnapshots) {
      // Managed rather than cleared: each of these is a restorable copy, and
      // the screen that lists them can say what every one of them holds.
      actions = IosTileButton(
        label: l10n.localSnapshotManageCopies,
        icon: Lucide.ChevronRight,
        enabled: !clearing,
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const LocalSnapshotsPage()),
        ),
      );
    } else if (category.key == StorageUsageCategoryKey.workspaceFiles) {
      actions = IosTileButton(
        label: l10n.workspaceEntryManage,
        icon: Lucide.ChevronRight,
        enabled: !clearing,
        onTap: () => openManager(const WorkspacesPage()),
      );
    } else if (category.key == StorageUsageCategoryKey.sandboxEnvironment) {
      actions = IosTileButton(
        label: l10n.workspaceEnvTitle,
        icon: Lucide.ChevronRight,
        enabled: !clearing,
        onTap: () => openManager(const EnvironmentPage()),
      );
    } else if (category.key == StorageUsageCategoryKey.skills) {
      actions = IosTileButton(
        label: l10n.storageSpaceManageSkills,
        icon: Lucide.ChevronRight,
        enabled: !clearing,
        onTap: () => openManager(const SkillsPage()),
      );
    } else if (category.key == StorageUsageCategoryKey.sessionFiles) {
      actions = IosTileButton(
        label: l10n.storageSessionFilesCleanOrphans,
        icon: Lucide.Trash2,
        backgroundColor: cs.primary,
        enabled: !clearing && onCleanOrphanSessionFiles != null,
        onTap: () => onCleanOrphanSessionFiles?.call(),
      );
    }

    if (category.key == StorageUsageCategoryKey.images ||
        category.key == StorageUsageCategoryKey.files) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: AppFontWeights.emphasis),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _UploadManager(
              key: ValueKey(category.key),
              images: category.key == StorageUsageCategoryKey.images,
              refreshReport: refreshReport,
              fmtBytes: fmtBytes,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: AppFontWeights.emphasis),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 14),
        if (actions != null) actions,
        if (actions != null) const SizedBox(height: 14),
        if (StorageContentsList.supports(category.key))
          Expanded(
            child: StorageContentsList(category: category, fmtBytes: fmtBytes),
          ),
        if (!StorageContentsList.supports(category.key))
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.subcategories.isNotEmpty) ...[
                    Text(
                      l10n.storageSpaceBreakdownTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in category.subcategories)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.onSurface.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subTitleFor(s.id),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: AppFontWeights.semibold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        fmtBytes(s.stats.bytes),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.65,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (category.key ==
                                        StorageUsageCategoryKey.cache &&
                                    s.id == 'avatar_cache')
                                  _MiniActionButton(
                                    label: l10n.storageSpaceClearButton,
                                    enabled: !clearing,
                                    onTap: () =>
                                        onClearCache?.call(avatarsOnly: true),
                                  ),
                                if (category.key ==
                                        StorageUsageCategoryKey.cache &&
                                    s.id == 'other_cache')
                                  _MiniActionButton(
                                    label: l10n.storageSpaceClearButton,
                                    enabled: !clearing,
                                    onTap: () => onClearOtherCache?.call(),
                                  ),
                                if (category.key ==
                                        StorageUsageCategoryKey.cache &&
                                    s.id == 'system_cache')
                                  _MiniActionButton(
                                    label: l10n.storageSpaceClearButton,
                                    enabled: !clearing,
                                    onTap: () => onClearSystemCache?.call(),
                                  ),
                                if (category.key ==
                                        StorageUsageCategoryKey
                                            .legacyChatData &&
                                    s.path != null &&
                                    s.path!.isNotEmpty)
                                  _MiniActionButton(
                                    label: l10n
                                        .storageSpaceExportLegacyChatFileButton,
                                    enabled: true,
                                    onTap: () => _exportLegacyHiveFile(
                                      context,
                                      sourcePath: s.path!,
                                      fileName: s.id,
                                    ),
                                  ),
                                if (category.key ==
                                        StorageUsageCategoryKey.other &&
                                    s.id == 'fonts')
                                  _MiniActionButton(
                                    label: l10n.storageSpaceClearButton,
                                    enabled: !clearing && onClearFonts != null,
                                    onTap: () => onClearFonts?.call(),
                                  ),
                                if (category.key ==
                                        StorageUsageCategoryKey.other &&
                                    s.id == 'local_models')
                                  _MiniActionButton(
                                    label: l10n.storageSpaceClearButton,
                                    enabled:
                                        !clearing && onClearLocalModels != null,
                                    onTap: () => onClearLocalModels?.call(),
                                  ),
                              ],
                            ),
                            if (s.path != null && s.path!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                _wrapableFilePath(s.path!),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _exportLegacyHiveFile(
    BuildContext context, {
    required String sourcePath,
    required String fileName,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final saved = await NativeFileSave.saveFileFromPath(
        sourcePath: sourcePath,
        fileName: fileName,
      );
      if (saved && context.mounted) {
        showAppSnackBar(
          context,
          message: l10n.storageSpaceExportDone(fileName),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceExportFailed(e.toString()),
        type: NotificationType.error,
      );
    }
  }
}
