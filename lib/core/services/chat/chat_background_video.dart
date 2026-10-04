import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Prepares a private, silent, screen-sized playback copy of the saved original.
///
/// Android performs file/codec work off the UI thread. The original remains the
/// backup asset; callers must initialize video_player only with the result.
final class ChatBackgroundVideo {
  const ChatBackgroundVideo._();

  static const MethodChannel _channel = MethodChannel(
    'app.chat_background_video',
  );

  @visibleForTesting
  static Future<String> Function(
    String sourcePath, {
    int? maxWidth,
    int? maxHeight,
  })?
  debugPrepareOverride;

  static Future<String> prepare(
    String sourcePath, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    final override = debugPrepareOverride;
    if (override != null) {
      return override(sourcePath, maxWidth: maxWidth, maxHeight: maxHeight);
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final size = views.isEmpty ? Size.zero : views.first.physicalSize;
    final width = maxWidth ?? size.width.floor();
    final height = maxHeight ?? size.height.floor();
    if (sourcePath.isEmpty || width <= 0 || height <= 0) {
      throw ArgumentError(
        'A video file and positive screen bounds are required.',
      );
    }
    final result = await _channel.invokeMethod<String>('prepare', {
      'sourcePath': sourcePath,
      'maxWidth': math.min(width, height),
      'maxHeight': math.max(width, height),
    });
    if (result == null || result.isEmpty) {
      throw StateError('Video preparation did not return a playback file.');
    }
    return result;
  }
}
