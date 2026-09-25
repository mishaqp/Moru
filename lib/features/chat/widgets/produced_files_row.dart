import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:Kelivo/features/workspace/widgets/files/file_browser_ops.dart';
import 'package:Kelivo/features/workspace/widgets/files/workspace_file_thumbnail.dart';

import 'package:flutter/material.dart';

import 'package:Kelivo/core/services/workspace/workspace_tool_metadata.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/custom_bottom_sheet.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

import 'unified_diff_view.dart';
import 'workspace_tool_ui.dart';

class ProducedFileEntry {
  const ProducedFileEntry({required this.file, required this.revision});

  final WorkspaceToolFile file;
  final String revision;
  String get label => file.path;
  String? get link => file.link;
  bool get isImage => isWorkspaceImagePath(file.path);
  String get dedupeKey => file.identity;
}

const int kProducedFilesLimit = 12;

List<ProducedFileEntry> collectProducedFileEntries(
  Iterable<WorkspaceToolPart> parts,
) {
  final entries = <String, ProducedFileEntry>{};
  for (final part in parts) {
    final meta = workspaceMetadataFrom(part.metadata);
    if (part.loading || meta == null || meta.status == 'denied') continue;
    for (final file in meta.files) {
      if (!file.isProduced || file.path.isEmpty) continue;
      entries[file.identity] = ProducedFileEntry(file: file, revision: part.id);
    }
  }
  return entries.values.toList();
}

/// One edit a reply made to a file.
class ReplyFileEdit {
  const ReplyFileEdit({
    required this.path,
    required this.diff,
    required this.added,
    required this.removed,
    required this.truncated,
  });

  final String path;
  final String diff;
  final int added;
  final int removed;
  final bool truncated;
}

/// Successful edits with a diff, in the order the reply made them.
List<ReplyFileEdit> collectReplyFileEdits(Iterable<WorkspaceToolPart> parts) {
  final edits = <ReplyFileEdit>[];
  for (final part in parts) {
    final meta = workspaceMetadataFrom(part.metadata);
    final diff = meta?.diff ?? '';
    if (part.loading || meta == null || meta.status != 'ok' || diff.isEmpty) {
      continue;
    }
    final counts = countUnifiedDiffChanges(diff);
    edits.add(
      ReplyFileEdit(
        path: meta.path ?? '',
        diff: diff,
        added: meta.added ?? counts.added,
        removed: meta.removed ?? counts.removed,
        truncated: meta.diffTruncated == true,
      ),
    );
  }
  return edits;
}

/// [edits] merged per file in order of first edit: one diff whose later
/// hunks follow the first without repeating the `---`/`+++` file lines.
List<ReplyFileEdit> groupReplyFileEdits(List<ReplyFileEdit> edits) {
  final byPath = <String, List<ReplyFileEdit>>{};
  for (final edit in edits) {
    (byPath[edit.path] ??= []).add(edit);
  }
  return [
    for (final entry in byPath.entries)
      ReplyFileEdit(
        path: entry.key,
        diff: [
          entry.value.first.diff.trimRight(),
          for (final edit in entry.value.skip(1))
            _withoutFileHeader(edit.diff).trimRight(),
        ].join('\n'),
        added: entry.value.fold(0, (sum, edit) => sum + edit.added),
        removed: entry.value.fold(0, (sum, edit) => sum + edit.removed),
        truncated: entry.value.any((edit) => edit.truncated),
      ),
  ];
}

String _withoutFileHeader(String diff) {
  final lines = diff.split('\n');
  if (lines.length >= 2 &&
      lines[0].startsWith('--- ') &&
      lines[1].startsWith('+++ ')) {
    return lines.skip(2).join('\n');
  }
  return diff;
}

/// Deduped chips / image thumbs for files written or edited in a turn.
class ProducedFilesRow extends StatelessWidget {
  const ProducedFilesRow({
    super.key,
    required this.parts,
    required this.conversationId,
  });

  static const ValueKey<String> rowKey = ValueKey<String>('produced-files-row');
  static const ValueKey<String> moreKey = ValueKey<String>(
    'produced-files-more',
  );
  static const ValueKey<String> editsSummaryKey = ValueKey<String>(
    'reply-edits-summary',
  );

  final List<WorkspaceToolPart> parts;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final entries = collectProducedFileEntries(parts);
    final truncated = parts.any(
      (part) =>
          part.toolName == 'shell' &&
          workspaceMetadataFrom(part.metadata)?.filesTruncated == true,
    );
    if (entries.isEmpty && !truncated) return const SizedBox.shrink();
    final visible = entries.length <= kProducedFilesLimit
        ? entries
        : entries.sublist(0, kProducedFilesLimit);
    final overflow = entries.length - visible.length;
    final l10n = AppLocalizations.of(context)!;
    final edits = collectReplyFileEdits(parts);
    final chips = Wrap(
      key: rowKey,
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in visible)
          entry.isImage && entry.link?.isNotEmpty == true
              ? _ProducedImageThumb(
                  entry: entry,
                  conversationId: conversationId,
                )
              : WorkspaceFileChip(
                  path: entry.label,
                  link: entry.link,
                  conversationId: conversationId,
                ),
        if (overflow > 0)
          IosCardPress(
            key: moreKey,
            borderRadius: BorderRadius.circular(8),
            baseColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onTap: () => unawaited(
              showWorkspaceFileList(
                context,
                files: entries.map((entry) => entry.file).toList(),
                conversationId: conversationId,
                title: l10n.workspaceToolChangedFiles,
              ),
            ),
            child: Text(
              l10n.workspaceToolMoreFiles(overflow),
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.medium,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        if (truncated)
          Text(
            l10n.workspaceToolFilesTruncated,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
      ],
    );
    if (edits.isEmpty) return chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReplyEditsSummary(edits: edits),
        const SizedBox(height: 8),
        chips,
      ],
    );
  }
}

/// "3 files changed · +120 −40"; opens every diff of the reply at once.
class _ReplyEditsSummary extends StatelessWidget {
  const _ReplyEditsSummary({required this.edits});

  final List<ReplyFileEdit> edits;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final files = {for (final edit in edits) edit.path}.length;
    var added = 0;
    var removed = 0;
    for (final edit in edits) {
      added += edit.added;
      removed += edit.removed;
    }
    final muted = cs.onSurface.withValues(alpha: 0.7);
    return IosCardPress(
      key: ProducedFilesRow.editsSummaryKey,
      borderRadius: BorderRadius.circular(10),
      baseColor: context.appColors.surfaceFill,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      onTap: () => unawaited(_open(context)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Lucide.FileDiff, size: 15, color: muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.replyChangedFilesSummary(files),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          WorkspaceAddedRemovedCounts(added: added, removed: removed),
          const SizedBox(width: 4),
          Icon(Lucide.ChevronRight, size: 15, color: muted),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final files = groupReplyFileEdits(edits);
    return showCustomBottomSheet<void>(
      context: context,
      title: l10n.workspaceToolChangedFiles,
      count: files.length,
      builder: (context, controller) => ListView.separated(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final file = files[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UnifiedDiffView(
                diff: file.diff,
                showHeader: true,
                fileName: file.path,
                added: file.added,
                removed: file.removed,
              ),
              if (file.truncated)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.workspaceToolDiffTruncated,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProducedImageThumb extends StatefulWidget {
  const _ProducedImageThumb({
    required this.entry,
    required this.conversationId,
  });

  final ProducedFileEntry entry;
  final String conversationId;

  @override
  State<_ProducedImageThumb> createState() => _ProducedImageThumbState();
}

class _ProducedImageThumbState extends State<_ProducedImageThumb> {
  FileBrowserEntry? _entry;
  bool _failed = false;
  int _resolveSerial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(covariant _ProducedImageThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.dedupeKey != widget.entry.dedupeKey ||
        oldWidget.entry.revision != widget.entry.revision ||
        oldWidget.conversationId != widget.conversationId) {
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final serial = ++_resolveSerial;
    setState(() {
      _failed = false;
      _entry = null;
    });
    final file = await resolveWorkspaceLinkedFile(
      context,
      widget.entry.link,
      conversationId: widget.conversationId,
    );
    FileBrowserEntry? entry;
    if (file != null) {
      try {
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file) {
          entry = FileBrowserEntry(
            name: p.basename(file.path),
            hostPath: file.path,
            isDirectory: false,
            size: stat.size,
            modified: stat.modified,
          );
        }
      } on FileSystemException {
        // A generated file may have been removed before its thumbnail loads.
      }
    }
    if (!mounted || serial != _resolveSerial) return;
    setState(() {
      _entry = entry;
      _failed = entry == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.entry.label,
      child: IosCardPress(
        borderRadius: BorderRadius.circular(10),
        baseColor: Colors.transparent,
        padding: EdgeInsets.zero,
        onTap: widget.entry.link == null
            ? null
            : () {
                unawaited(
                  openWorkspaceLinkedFile(
                    context,
                    widget.entry.link,
                    conversationId: widget.conversationId,
                    title: widget.entry.label,
                  ),
                );
              },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: _entry != null
                ? WorkspaceFileThumbnail(
                    entry: _entry!,
                    size: 56,
                    iconSize: 18,
                    iconColor: cs.onSurface.withValues(alpha: 0.4),
                  )
                : _placeholder(cs),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return ColoredBox(
      color: context.appColors.surfaceFill,
      child: Icon(
        _failed ? Lucide.ImageOff : Lucide.Image,
        size: 18,
        color: cs.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}
