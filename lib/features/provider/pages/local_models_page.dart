import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/local/local_model_catalog.dart';
import '../../../core/services/local/local_model_downloader.dart';
import '../../../core/services/local/local_model_import.dart';
import '../../../core/services/local/local_model_library.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../utils/app_directories.dart';

/// Settings page for the built-in "Локальные модели · LiteRT" provider:
/// installed on-device models (with delete) and file import. The catalog
/// (section 8/9 of the task this shipped for) is a later addition --
/// this page ships with import-only, which is enough to actually use a
/// local model end to end.
class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key});

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage> {
  static const _library = LocalModelLibrary();
  final _downloader = LiteRtModelDownloader();
  final Map<String, LiteRtDownloadProgress> _catalogProgress = {};

  @override
  void dispose() {
    _downloader.dispose();
    super.dispose();
  }

  Future<void> _downloadCatalogEntry(LiteRtCatalogEntry entry) async {
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _downloader.download(
        entry,
        settings,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _catalogProgress[entry.id] = p);
        },
      );
      if (!mounted) return;
      setState(() => _catalogProgress.remove(entry.id));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.localModelsCatalogDownloadSuccess)),
      );
    } on LiteRtDownloadCancelledException {
      if (!mounted) return;
      setState(() => _catalogProgress.remove(entry.id));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.localModelsCatalogDownloadCancelled)),
      );
    } on LiteRtDownloadFailedException catch (e) {
      if (!mounted) return;
      setState(() => _catalogProgress.remove(entry.id));
      messenger.showSnackBar(
        SnackBar(content: Text(_catalogFailureMessage(l10n, e.code))),
      );
    }
  }

  String _catalogFailureMessage(
    AppLocalizations l10n,
    LiteRtDownloadFailureCode code,
  ) => switch (code) {
    LiteRtDownloadFailureCode.httpError =>
      l10n.localModelsCatalogDownloadFailedHttp,
    LiteRtDownloadFailureCode.incompleteTransfer =>
      l10n.localModelsCatalogDownloadFailedIncomplete,
    LiteRtDownloadFailureCode.formatMismatch =>
      l10n.localModelsCatalogDownloadFailedFormat,
    LiteRtDownloadFailureCode.checksumMismatch =>
      l10n.localModelsCatalogDownloadFailedChecksum,
  };

  Future<void> _openCatalogEntryPage(LiteRtCatalogEntry entry) async {
    final uri = entry.repoUrl;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await launchUrl(uri);
    } catch (_) {
      await launchUrl(uri);
    }
  }

  Future<void> _import() async {
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['litertlm'],
      withReadStream: true,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return;
    final picked = files.first;
    if (!mounted) return;

    final progress = ValueNotifier<LocalModelImportProgress>(
      const LocalModelImportProgress(bytesWritten: 0, totalBytes: null),
    );
    var cancelled = false;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.localModelsImportingLabel),
          content: ValueListenableBuilder<LocalModelImportProgress>(
            valueListenable: progress,
            builder: (context, p, _) {
              final total = p.totalBytes;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: total != null ? p.bytesWritten / total : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total != null
                        ? '${_formatBytes(p.bytesWritten)} / ${_formatBytes(total)}'
                        : _formatBytes(p.bytesWritten),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.localModelsDeleteConfirmCancel),
            ),
          ],
        ),
      ),
    );

    final targetDir = await AppDirectories.getLocalModelsDirectory();
    final targetName =
        '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
    final outcome = await importLocalModelFile(
      source: picked.readStream,
      totalBytes: picked.size > 0 ? picked.size : null,
      targetDirectory: targetDir,
      targetFileName: targetName,
      onProgress: (p) => progress.value = p,
      isCancelled: () => cancelled,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).maybePop();

    switch (outcome) {
      case LocalModelImportSuccess(
        :final filePath,
        :final sizeBytes,
        :final sha256,
      ):
        await _library.registerInstalledModel(
          settings,
          filePath: filePath,
          sizeBytes: sizeBytes,
          displayName: _stripExtension(picked.name),
          sourceLabel: l10n.localModelsSourceImportedLabel,
          contentSha256: sha256,
        );
        if (!mounted) return;
        setState(() {});
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.localModelsImportSuccess)),
        );
      case LocalModelImportCancelled():
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.localModelsImportCancelled)),
        );
      case LocalModelImportRejected(:final reason):
        messenger.showSnackBar(
          SnackBar(content: Text(_rejectionMessage(l10n, reason))),
        );
    }
  }

  String _rejectionMessage(
    AppLocalizations l10n,
    LocalModelImportRejectReason reason,
  ) => switch (reason) {
    LocalModelImportRejectReason.ggufNotSupported =>
      l10n.localModelsImportRejectedGguf,
    LocalModelImportRejectReason.notLiteRtLmFormat =>
      l10n.localModelsImportRejectedFormat,
    LocalModelImportRejectReason.noReadableStream =>
      l10n.localModelsImportRejectedNoStream,
  };

  Future<void> _delete(InstalledLocalModel model) async {
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.localModelsDeleteConfirmTitle),
        content: Text(l10n.localModelsDeleteConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.localModelsDeleteConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.localModelsDeleteConfirmOk),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _library.deleteModel(settings, model.id);
      if (!mounted) return;
      setState(() {});
    } on LocalModelLibraryException {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.localModelsDeleteInUseError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final models = _library.installedModels(settings);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.localModelsProviderName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionHeader(l10n.localModelsInstalledSectionTitle),
          const SizedBox(height: 8),
          if (models.isEmpty)
            SectionCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 12,
                ),
                child: Column(
                  children: [
                    Icon(
                      Lucide.Package,
                      size: 32,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.localModelsEmptyTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.localModelsEmptySubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SectionCard(
              dividers: true,
              children: [
                for (final model in models)
                  _InstalledModelTile(
                    model: model,
                    onDelete: () => _delete(model),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          _SectionHeader(l10n.localModelsCatalogSectionTitle),
          const SizedBox(height: 8),
          SectionCard(
            dividers: true,
            children: [
              for (final entry in LiteRtModelCatalog.entries)
                _CatalogEntryTile(
                  entry: entry,
                  isInstalled: models.any(
                    (m) => m.sha256.isNotEmpty && m.sha256 == entry.sha256,
                  ),
                  progress: _catalogProgress[entry.id],
                  onDownload: () => _downloadCatalogEntry(entry),
                  onCancel: () => _downloader.cancel(entry.id),
                  onOpenPage: () => _openCatalogEntryPage(entry),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _import,
            icon: const Icon(Lucide.FolderInput, size: 18),
            label: Text(l10n.localModelsImportAction),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _CatalogEntryTile extends StatelessWidget {
  const _CatalogEntryTile({
    required this.entry,
    required this.isInstalled,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onOpenPage,
  });

  final LiteRtCatalogEntry entry;
  final bool isInstalled;
  final LiteRtDownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitle =
        '${_formatBytes(entry.sizeBytes)} · ${entry.license} · '
        '${l10n.localModelsCatalogContextLabel(entry.contextTokens)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Lucide.Package, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isInstalled)
                Text(
                  l10n.localModelsCatalogInstalledBadge,
                  style: textTheme.bodySmall?.copyWith(color: cs.primary),
                )
              else if (progress != null)
                Semantics(
                  button: true,
                  label: l10n.localModelsCatalogCancelAction,
                  child: IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: l10n.localModelsCatalogCancelAction,
                    icon: const Icon(Lucide.X, size: 18),
                    onPressed: onCancel,
                  ),
                )
              else if (entry.isDownloadable)
                Semantics(
                  button: true,
                  label: l10n.localModelsCatalogDownloadAction,
                  child: IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: l10n.localModelsCatalogDownloadAction,
                    icon: Icon(Lucide.Download, size: 18, color: cs.primary),
                    onPressed: onDownload,
                  ),
                )
              else
                Semantics(
                  button: true,
                  label: l10n.localModelsCatalogOpenPageAction,
                  child: IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: l10n.localModelsCatalogOpenPageAction,
                    icon: const Icon(Lucide.ExternalLink, size: 18),
                    onPressed: onOpenPage,
                  ),
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress!.fraction),
            const SizedBox(height: 4),
            Text(
              '${l10n.localModelsCatalogDownloadingLabel} '
              '${_formatBytes(progress!.receivedBytes)}'
              '${progress!.totalBytes != null ? ' / ${_formatBytes(progress!.totalBytes!)}' : ''}',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (!entry.isDownloadable && !isInstalled) ...[
            const SizedBox(height: 6),
            Text(
              l10n.localModelsCatalogGatedNote,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _InstalledModelTile extends StatelessWidget {
  const _InstalledModelTile({required this.model, required this.onDelete});

  final InstalledLocalModel model;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final backendLabel = model.backend == 'gpu'
        ? l10n.localModelsBackendGpuLabel
        : l10n.localModelsBackendCpuLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Lucide.Smartphone, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.displayName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatBytes(model.sizeBytes)} · $backendLabel'
                  '${model.sourceLabel.isNotEmpty ? ' · ${model.sourceLabel}' : ''}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: l10n.localModelsDeleteAction,
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.localModelsDeleteAction,
              icon: Icon(Lucide.Trash, size: 18, color: cs.error),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  double value = bytes.toDouble();
  var unitIndex = -1;
  do {
    value /= 1024;
    unitIndex++;
  } while (value >= 1024 && unitIndex < units.length - 1);
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unitIndex]}';
}

String _stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}
