import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/chat/chat_service.dart';
import '../../../utils/sandbox_path_resolver.dart';

/// The newest few images of a chat as small rounded previews under its title
/// in the sidebar. Looked up when the row first builds and remembered by
/// [ChatService.recentImageUris]; a chat without local images shows nothing,
/// and a file that is gone leaves a plain grey square.
class ChatThumbnails extends StatefulWidget {
  const ChatThumbnails({super.key, required this.chatId});

  final String chatId;

  /// How many are looked up; the row shows as many as fit, like OmniBot.
  static const int maxCount = 8;
  static const double size = 34;
  static const double spacing = 6;

  @override
  State<ChatThumbnails> createState() => _ChatThumbnailsState();
}

class _ChatThumbnailsState extends State<ChatThumbnails> {
  Future<List<String>>? _future;
  int _stamp = -1;

  /// Only images stored on the phone: a link or an inline image is not worth
  /// fetching or decoding for a 44 dp preview.
  static List<String> _local(List<String> uris) => [
    for (final uri in uris)
      if (!uri.startsWith('http') && !uri.startsWith('data:'))
        SandboxPathResolver.fix(uri),
  ];

  @override
  Widget build(BuildContext context) {
    // A new message moves the chat's updatedAt; that is when to look again.
    final stamp = context.select<ChatService, int>(
      (service) =>
          service
              .getConversation(widget.chatId)
              ?.updatedAt
              .microsecondsSinceEpoch ??
          0,
    );
    if (_future == null || stamp != _stamp) {
      _stamp = stamp;
      _future = context.read<ChatService>().recentImageUris(
        widget.chatId,
        limit: ChatThumbnails.maxCount,
      );
    }
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (context, snapshot) {
        final paths = _local(snapshot.data ?? const <String>[]);
        if (paths.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 7),
          child: LayoutBuilder(
            builder: (context, box) {
              final fit =
                  ((box.maxWidth + ChatThumbnails.spacing) /
                          (ChatThumbnails.size + ChatThumbnails.spacing))
                      .floor()
                      .clamp(1, paths.length);
              return SizedBox(
                height: ChatThumbnails.size,
                child: Row(
                  children: [
                    for (final (i, path) in paths.take(fit).indexed) ...[
                      if (i > 0) const SizedBox(width: ChatThumbnails.spacing),
                      _Thumb(path: path),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixels = (ChatThumbnails.size * dpr).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox.square(
        dimension: ChatThumbnails.size,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          // Decoded at the preview's size, not the photo's.
          cacheWidth: pixels,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              ColoredBox(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}
