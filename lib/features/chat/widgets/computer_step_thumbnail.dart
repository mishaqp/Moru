import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/models/workspace_binding.dart';
import '../../../core/providers/external_mounts_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/browser/browser_thumbnail_cache.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/workspace/local_image_access.dart';
import '../../../shared/widgets/markdown_image_provider.dart';
import '../../../utils/safe_resize_image.dart';
import '../../workspace/workspace_file_navigation.dart';
import '../models/computer_step.dart';
import 'chat_surface.dart';

/// A checked preview of a tool step. Browser snapshots come from the cache
/// or an existing app-private screenshot; UI never captures the live WebView.
class ComputerStepThumbnail extends StatefulWidget {
  const ComputerStepThumbnail({
    super.key,
    required this.step,
    this.conversationId,
    this.width = 72,
    this.height = 54,
    this.borderRadius = 10,
    this.browserDomain,
    this.browserPageUrl,
    this.browserPageKey,
    this.browserStartedAt,
    this.browserActivityId,
    this.hideBrowserPlaceholder = false,
  });

  final ComputerStep step;
  final String? conversationId;
  final double width;
  final double height;
  final double borderRadius;

  /// Captured live context supplied only by the owning browser activity.
  /// The step's launch display filter still validates the page address.
  final String? browserDomain;
  final String? browserPageUrl;
  final String? browserPageKey;
  final DateTime? browserStartedAt;
  final String? browserActivityId;

  /// Detail sheets omit the empty browser tile while retaining checked images.
  final bool hideBrowserPlaceholder;

  @override
  State<ComputerStepThumbnail> createState() => _ComputerStepThumbnailState();
}

class _ComputerStepThumbnailState extends State<ComputerStepThumbnail> {
  Uint8List? _imageBytes;
  String? _source;
  String? _conversation;
  ComputerStepKind? _kind;
  int _readSerial = 0;

  @override
  void initState() {
    super.initState();
    widget.step.run?.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readImage();
  }

  @override
  void didUpdateWidget(covariant ComputerStepThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.run != widget.step.run) {
      oldWidget.step.run?.removeListener(_refresh);
      widget.step.run?.addListener(_refresh);
    }
    _readImage();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _readImage() {
    final step = widget.step;
    final browser = step.kind == ComputerStepKind.browser;
    final source =
        (browser && step.allowsBrowserPreview) ||
            step.kind == ComputerStepKind.image ||
            step.kind == ComputerStepKind.file
        ? step.imagePath
        : null;
    if (_source == source &&
        _conversation == widget.conversationId &&
        _kind == step.kind) {
      return;
    }
    _source = source;
    _conversation = widget.conversationId;
    _kind = step.kind;
    _imageBytes = null;
    final serial = ++_readSerial;
    if (source == null) return;
    if (browser) {
      final conversationId = widget.conversationId;
      if (conversationId == null) return;
      final cache = BrowserThumbnailCache.instance;
      if (cache.forSource(conversationId, source) != null) {
        return;
      }
      // Restore the exact preview through the checked screenshot directory.
      // Historical disk reads must not replace a newer live-page fallback.
      unawaited(
        cache.capture(
          conversationId: conversationId,
          // Tool IDs can repeat across replies; a saved image owns this entry.
          stepId: 'restored:$source',
          sourcePath: source,
          pageUrl: step.browserPageUrl,
          historical: true,
        ),
      );
      return;
    }
    final chat = context.read<ChatService?>();
    final conversationId = widget.conversationId ?? chat?.currentConversationId;
    final binding = WorkspaceBinding.fromExtras(
      conversationId == null
          ? {}
          : chat?.getConversation(conversationId)?.extras ?? {},
    );
    final workspaces = context.read<WorkspaceProvider?>();
    final externalMounts = context.read<ExternalMountsProvider?>();
    unawaited(() async {
      Uint8List? bytes;
      try {
        if (source.startsWith('data:image/')) {
          bytes = decodeMarkdownImageData(source);
        } else if (computerActionUri(source) != null) {
          bytes = (await MarkdownImageProvider(source).readSource()).bytes;
        } else if (source.startsWith('kelivo://')) {
          bytes = await readWorkspaceLinkedFile(
            context,
            source,
            conversationId: conversationId,
            maxBytes: kMaxMarkdownImageBytes,
          );
        } else {
          bytes = await readLocalImageBytes(
            source,
            conversationId: conversationId,
            binding: binding,
            workspaces: workspaces,
            externalMounts: externalMounts,
            maxBytes: kMaxMarkdownImageBytes,
          );
        }
      } on Object {
        // Missing, invalid or ungranted images keep the tool-type placeholder.
      }
      if (!mounted || serial != _readSerial) return;
      setState(() => _imageBytes = bytes);
    }());
  }

  @override
  void dispose() {
    _readSerial++;
    widget.step.run?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrowserThumbnailCache.instance,
      builder: (context, _) {
        final step = widget.step;
        final cache = BrowserThumbnailCache.instance;
        final browser = step.kind == ComputerStepKind.browser;
        final allowsLivePage =
            widget.browserPageUrl != null &&
            step.canPreviewBrowserPage(widget.browserPageUrl);
        final candidate = browser && step.allowsBrowserPreview
            ? cache.previewForStep(
                widget.conversationId,
                sourcePath: step.imagePath,
                activityId: allowsLivePage ? widget.browserActivityId : null,
                pageUrl: allowsLivePage
                    ? widget.browserPageUrl
                    : step.browserPageUrl,
                pageKey: allowsLivePage
                    ? widget.browserPageKey
                    : step.browserPageKey,
                startedAt: allowsLivePage
                    ? widget.browserStartedAt
                    : step.browserStartedAt,
              )
            : null;
        // A snapshot may have been cached by an earlier launch with a
        // different display filter. Validate its own identity before showing
        // pixels, including an exact source match.
        final thumbnail =
            candidate != null &&
                step.canPreviewBrowserSource(candidate.sourcePath) &&
                (candidate.pageUrl == null ||
                    step.canPreviewBrowserPage(candidate.pageUrl))
            ? candidate
            : null;
        final bytes = thumbnail?.bytes ?? _imageBytes;
        if (browser && bytes == null && widget.hideBrowserPlaceholder) {
          return const SizedBox.shrink();
        }
        final preview = bytes == null
            ? _fallback(context, step)
            : Image(
                image: _imageProvider(context, bytes, step.imagePath ?? ''),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (context, _, _) => _fallback(context, step),
              );
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            key: ValueKey('computer-step-thumbnail:${step.id}'),
            width: widget.width,
            height: widget.height,
            child: browser
                ? preview
                : buildSharedChatSurface(
                    context,
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    padding: EdgeInsets.zero,
                    defaultColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: preview,
                  ),
          ),
        );
      },
    );
  }

  ImageProvider _imageProvider(
    BuildContext context,
    Uint8List bytes,
    String source,
  ) {
    final provider = markdownImageFromBytes(bytes, source: source);
    if (provider is! MemoryImage) return provider;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return SafeResizeImage.wrap(
      provider,
      width: math.max(1, math.min(1440, (widget.width * ratio).ceil())),
      height: math.max(1, math.min(1440, (widget.height * ratio).ceil())),
      fit: SafeResizeFit.cover,
      maxEdge: 1440,
      maxPixels: 1440 * 1440,
    );
  }

  Widget _fallback(BuildContext context, ComputerStep step) {
    final cs = Theme.of(context).colorScheme;
    if (step.kind == ComputerStepKind.browser) {
      if (widget.hideBrowserPlaceholder) return const SizedBox.shrink();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: cs.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Icon(step.icon, size: 18, color: cs.onSurfaceVariant),
      );
    }
    if (step.kind == ComputerStepKind.command) {
      final lines = const LineSplitter().convert(step.preview);
      final preview = lines
          .skip(lines.length > 4 ? lines.length - 4 : 0)
          .join('\n');
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFF11161E),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: const Color(0xFF46505E)),
        ),
        alignment: Alignment.topLeft,
        child: Text(
          preview,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 7,
            height: 1.15,
            fontFamily: 'monospace',
            color: Color(0xFFDDE6EE),
          ),
        ),
      );
    }
    if (step.kind == ComputerStepKind.file) {
      final preview = const LineSplitter()
          .convert(step.preview)
          .take(3)
          .join('\n');
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step.path != null)
              Text(
                p.posix.basename(step.path!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  height: 1.1,
                  color: cs.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 3),
            if (preview.isNotEmpty)
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 7,
                      height: 1.15,
                      fontFamily: 'monospace',
                      color: chatSurfacePlainTextColor(context),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final factor in [0.9, 0.65])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: FractionallySizedBox(
                          widthFactor: factor,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.25,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            step.icon,
            size: widget.height >= 100 ? 36 : 22,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
