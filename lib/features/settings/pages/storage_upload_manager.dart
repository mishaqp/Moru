part of 'storage_space_page.dart';

class _UploadManager extends StatefulWidget {
  const _UploadManager({
    super.key,
    required this.images,
    required this.refreshReport,
    required this.fmtBytes,
  });

  final bool images;
  final Future<void> Function() refreshReport;
  final String Function(int) fmtBytes;

  @override
  State<_UploadManager> createState() => _UploadManagerState();
}

enum _StorageImageSourceFilter { all, userUpload, assistant }

enum _StorageEntrySort { newest, oldest, largest, smallest }

class _UploadManagerState extends State<_UploadManager> {
  bool _loading = false;
  List<StorageFileEntry> _entries = const <StorageFileEntry>[];
  List<StorageFileEntry> _visibleEntries = const <StorageFileEntry>[];
  final Set<String> _selected = <String>{};
  _StorageImageSourceFilter _sourceFilter = _StorageImageSourceFilter.all;
  _StorageEntrySort _sort = _StorageEntrySort.newest;

  bool get _selectMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _UploadManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images != widget.images) {
      // When switching between Images <-> Files on desktop, ensure we reload with the new filter.
      setState(() {
        _selected.clear();
        _entries = const <StorageFileEntry>[];
        _visibleEntries = const <StorageFileEntry>[];
        _loading = false;
        _sourceFilter = _StorageImageSourceFilter.all;
        _sort = _StorageEntrySort.newest;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final list = await StorageUsageService.listUploadEntries(
        images: widget.images,
      );
      if (!mounted) return;
      setState(() {
        _entries = list;
        _visibleEntries = _buildVisibleEntries();
        final paths = _entries.map((e) => e.path).toSet();
        _selected.removeWhere((p) => !paths.contains(p));
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<StorageFileEntry> _buildVisibleEntries() {
    if (!widget.images) return _entries;

    final entries = _entries.where((entry) {
      return switch (_sourceFilter) {
        _StorageImageSourceFilter.all => true,
        _StorageImageSourceFilter.userUpload =>
          entry.source == StorageFileSource.userUpload,
        _StorageImageSourceFilter.assistant =>
          entry.source == StorageFileSource.assistant,
      };
    }).toList();

    entries.sort((a, b) {
      final order = switch (_sort) {
        _StorageEntrySort.newest => b.modifiedAt.compareTo(a.modifiedAt),
        _StorageEntrySort.oldest => a.modifiedAt.compareTo(b.modifiedAt),
        _StorageEntrySort.largest => b.bytes.compareTo(a.bytes),
        _StorageEntrySort.smallest => a.bytes.compareTo(b.bytes),
      };
      return order != 0 ? order : a.path.compareTo(b.path);
    });
    return entries;
  }

  void _setSourceFilter(_StorageImageSourceFilter filter) {
    if (_sourceFilter == filter) return;
    setState(() {
      _sourceFilter = filter;
      _visibleEntries = _buildVisibleEntries();
      _selected.clear();
    });
  }

  void _setSort(_StorageEntrySort sort) {
    if (_sort == sort) return;
    setState(() {
      _sort = sort;
      _visibleEntries = _buildVisibleEntries();
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  void _selectAll(Iterable<StorageFileEntry> entries) {
    setState(() {
      _selected
        ..clear()
        ..addAll(entries.map((e) => e.path));
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.storageSpaceDeleteConfirmTitle),
          content: Text(l10n.storageSpaceDeleteUploadsConfirmMessage(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.homePageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.homePageDelete),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    try {
      final deleted = await StorageUsageService.deleteUploadFiles(
        _selected,
        images: widget.images,
      );
      if (!mounted) return;
      _clearSelection();
      showAppSnackBar(
        context,
        message: l10n.storageSpaceDeletedUploadsDone(deleted),
        type: NotificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(error.toString()),
        type: NotificationType.error,
      );
    }
    await _load();
    await widget.refreshReport();
  }

  Future<void> _openImageViewer(
    List<StorageFileEntry> entries,
    int initialIndex,
  ) async {
    final images = entries.map((e) => e.path).toList(growable: false);
    final route = MaterialPageRoute<void>(
      builder: (_) =>
          ImageViewerPage(images: images, initialIndex: initialIndex),
    );
    await Navigator.of(context).push(route);
  }

  Future<void> _openFile(String path) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await OpenFilex.open(path);
      if (res.type != ResultType.done) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: l10n.chatMessageWidgetCannotOpenFile(res.message),
          type: NotificationType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.chatMessageWidgetOpenFileError(e.toString()),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Center(
        child: Text(
          l10n.storageSpaceNoUploads,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
        ),
      );
    }

    final entries = _visibleEntries;
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        IosTileButton(
          label: _selectMode
              ? l10n.storageSpaceClearSelection
              : l10n.storageSpaceSelectAll,
          icon: _selectMode ? Lucide.XCircle : Lucide.CheckSquare,
          backgroundColor: cs.primary,
          enabled: entries.isNotEmpty,
          onTap: _selectMode ? _clearSelection : () => _selectAll(entries),
        ),
        IosTileButton(
          label: l10n.homePageDelete,
          icon: Lucide.Trash2,
          backgroundColor: cs.error,
          enabled: _selected.isNotEmpty,
          onTap: _deleteSelected,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.images) ...[
          _StorageImageOrganizer(
            sourceFilter: _sourceFilter,
            sort: _sort,
            onSourceChanged: _setSourceFilter,
            onSortChanged: _setSort,
          ),
          const SizedBox(height: 12),
        ],
        actions,
        const SizedBox(height: 12),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _selectMode
                        ? l10n.storageSpaceSelectedCount(_selected.length)
                        : l10n.storageSpaceUploadsCount(entries.length),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
              if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      l10n.storageSpaceNoUploads,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                )
              else if (widget.images)
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 140,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final e = entries[index];
                      final selected = _selected.contains(e.path);
                      return _ImageTile(
                        path: e.path,
                        selected: selected,
                        onToggle: () => _toggleSelect(e.path),
                        onTap: () {
                          if (_selectMode) {
                            _toggleSelect(e.path);
                          } else {
                            _openImageViewer(entries, index);
                          }
                        },
                        onLongPress: () => _toggleSelect(e.path),
                      );
                    }, childCount: entries.length),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final e = entries[index];
                    final selected = _selected.contains(e.path);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FileRow(
                        entry: e,
                        selected: selected,
                        fmtBytes: widget.fmtBytes,
                        onTap: () {
                          if (_selectMode) {
                            _toggleSelect(e.path);
                          } else {
                            _openFile(e.path);
                          }
                        },
                        onLongPress: () => _toggleSelect(e.path),
                        onToggle: () => _toggleSelect(e.path),
                      ),
                    );
                  }, childCount: entries.length),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StorageImageOrganizer extends StatelessWidget {
  const _StorageImageOrganizer({
    required this.sourceFilter,
    required this.sort,
    required this.onSourceChanged,
    required this.onSortChanged,
  });

  final _StorageImageSourceFilter sourceFilter;
  final _StorageEntrySort sort;
  final ValueChanged<_StorageImageSourceFilter> onSourceChanged;
  final ValueChanged<_StorageEntrySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _StorageChoiceRow<_StorageImageSourceFilter>(
          label: l10n.storageSpaceSourceLabel,
          value: sourceFilter,
          options: [
            (_StorageImageSourceFilter.all, l10n.storageSpaceSourceAll),
            (
              _StorageImageSourceFilter.userUpload,
              l10n.storageSpaceSourceUserUpload,
            ),
            (
              _StorageImageSourceFilter.assistant,
              l10n.storageSpaceSourceAssistant,
            ),
          ],
          onChanged: onSourceChanged,
        ),
        const SizedBox(height: 8),
        _StorageChoiceRow<_StorageEntrySort>(
          label: l10n.storageSpaceSortLabel,
          value: sort,
          options: [
            (_StorageEntrySort.newest, l10n.storageSpaceSortNewest),
            (_StorageEntrySort.oldest, l10n.storageSpaceSortOldest),
            (_StorageEntrySort.largest, l10n.storageSpaceSortLargest),
            (_StorageEntrySort.smallest, l10n.storageSpaceSortSmallest),
          ],
          onChanged: onSortChanged,
        ),
      ],
    );
  }
}

class _StorageChoiceRow<T> extends StatelessWidget {
  const _StorageChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final shellColor = cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05);
    final selectedColor = cs.primary.withValues(alpha: isDark ? 0.22 : 0.13);

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: shellColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int index = 0; index < options.length; index++) ...[
                      Semantics(
                        button: true,
                        selected: options[index].$1 == value,
                        child: IosCardPress(
                          onTap: () => onChanged(options[index].$1),
                          haptics: false,
                          pressedScale: 1.0,
                          borderRadius: BorderRadius.circular(8),
                          baseColor: options[index].$1 == value
                              ? selectedColor
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Text(
                            options[index].$2,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: AppFontWeights.semibold,
                              color: options[index].$1 == value
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ),
                      if (index != options.length - 1) const SizedBox(width: 2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.path,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onLongPress,
  });

  final String path;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cs = Theme.of(context).colorScheme;
        final border = cs.onSurface.withValues(alpha: 0.10);
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final side = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 140.0;
        final int cachePx = (side * dpr).clamp(64.0, 1024.0).round();

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary.withValues(alpha: 0.55) : border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IosCardPress(
            onTap: onTap,
            onLongPress: onLongPress,
            haptics: false,
            pressedScale: 1.0,
            borderRadius: BorderRadius.circular(12),
            baseColor: cs.onSurface.withValues(alpha: 0.03),
            padding: EdgeInsets.zero,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: cachePx,
                  cacheHeight: cachePx,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      alignment: Alignment.center,
                      child: Icon(
                        Lucide.ImageOff,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IosCheckbox(
                    value: selected,
                    size: 20,
                    hitTestSize: 22,
                    borderWidth: 1.6,
                    activeColor: cs.primary,
                    borderColor: cs.primary.withValues(alpha: 0.55),
                    onChanged: (_) => onToggle(),
                    enableHaptics: false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.selected,
    required this.fmtBytes,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });

  final StorageFileEntry entry;
  final bool selected;
  final String Function(int) fmtBytes;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = cs.onSurface.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IosCardPress(
        onTap: onTap,
        onLongPress: onLongPress,
        haptics: false,
        pressedScale: 1.0,
        borderRadius: BorderRadius.circular(12),
        baseColor: cs.onSurface.withValues(alpha: 0.03),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            IosCheckbox(
              value: selected,
              size: 20,
              hitTestSize: 22,
              borderWidth: 1.6,
              activeColor: cs.primary,
              borderColor: cs.primary.withValues(alpha: 0.55),
              onChanged: (_) => onToggle(),
              enableHaptics: false,
            ),
            const SizedBox(width: 10),
            Icon(
              Lucide.Paperclip,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.82),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fmtBytes(entry.bytes)} · ${_fmtTime(entry.modifiedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color fg = enabled
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.35);
    final Color bg = enabled
        ? cs.primary.withValues(alpha: 0.12)
        : cs.onSurface.withValues(alpha: 0.03);
    final Color border = enabled
        ? cs.primary.withValues(alpha: 0.35)
        : cs.onSurface.withValues(alpha: 0.10);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: AppFontWeights.semibold,
            color: fg,
          ),
        ),
      ),
    );
  }
}
