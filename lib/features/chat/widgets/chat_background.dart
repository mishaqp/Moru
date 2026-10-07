import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_background_video.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'chat_gradient_background.dart';
import 'frosted/chat_frosted_backdrop.dart';

@visibleForTesting
int debugChatBackgroundFilterBuildCount = 0;
@visibleForTesting
int debugChatBackgroundImageProviderBuildCount = 0;
@visibleForTesting
VideoPlayerController Function(File, VideoPlayerOptions)?
debugChatBackgroundVideoControllerFactory;

/// The sole artwork layer behind a chat, also reused by the settings preview.
/// Effects are cached independently of image/GIF/video and gradient frames.
class ChatBackground extends StatefulWidget {
  const ChatBackground({
    super.key,
    required this.configuration,
    this.desktop = false,
    this.includeSurfaceFill = false,
    this.active = true,
    this.onGradientFrame,
  });

  final ChatBackgroundSettings configuration;
  final bool desktop;
  final bool includeSurfaceFill;
  final bool active;
  final ValueChanged<double>? onGradientFrame;

  @override
  State<ChatBackground> createState() => _ChatBackgroundState();
}

class _ChatBackgroundState extends State<ChatBackground> {
  ColorFilter? _colorFilter;
  ui.ImageFilter? _blurFilter;
  ImageProvider? _imageProvider;
  (String, int, int)? _imageIdentity;
  (ImageProvider, int)? _decodedFrame;

  @override
  void initState() {
    super.initState();
    _updateFilters();
  }

  @override
  void didUpdateWidget(ChatBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.configuration;
    final current = widget.configuration;
    if (previous.blur != current.blur ||
        previous.brightness != current.brightness ||
        previous.saturation != current.saturation) {
      _updateFilters();
    }
  }

  void _updateFilters() {
    debugChatBackgroundFilterBuildCount++;
    final options = widget.configuration;
    _blurFilter = options.blur <= 0
        ? null
        : ui.ImageFilter.blur(
            sigmaX: options.blur,
            sigmaY: options.blur,
            tileMode: TileMode.clamp,
          );
    if (options.brightness == 1 && options.saturation == 1) {
      _colorFilter = null;
      return;
    }
    final saturation = options.saturation;
    final brightness = options.brightness;
    final red = (1 - saturation) * 0.2126;
    final green = (1 - saturation) * 0.7152;
    final blue = (1 - saturation) * 0.0722;
    _colorFilter = ColorFilter.matrix([
      (red + saturation) * brightness,
      green * brightness,
      blue * brightness,
      0,
      0,
      red * brightness,
      (green + saturation) * brightness,
      blue * brightness,
      0,
      0,
      red * brightness,
      green * brightness,
      (blue + saturation) * brightness,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  ImageProvider _provider(String path, Size size, double dpr) {
    final width = (size.width * dpr).ceil().clamp(1, 16384);
    final height = (size.height * dpr).ceil().clamp(1, 16384);
    final identity = (path, width, height);
    if (_imageIdentity != identity) {
      final ImageProvider source = path.startsWith('http')
          ? NetworkImage(path)
          : FileImage(File(SandboxPathResolver.fix(path)));
      _imageProvider = ResizeImage(
        source,
        width: width,
        height: height,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );
      _imageIdentity = identity;
      debugChatBackgroundImageProviderBuildCount++;
    }
    return _imageProvider!;
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.configuration;
    final cs = Theme.of(context).colorScheme;
    final economy = context.select<SettingsProvider?, bool>(
      (settings) =>
          settings?.glassTheme == true && settings?.glassEconomy == true,
    );
    if (options.type == ChatBackgroundType.none) {
      return widget.includeSurfaceFill
          ? ColoredBox(color: cs.surface)
          : const SizedBox.expand();
    }
    final alignment = Alignment(options.focusX, options.focusY);
    return IgnorePointer(
      child: RepaintBoundary(
        child: TickerMode(
          enabled:
              widget.active &&
              !economy &&
              !MediaQuery.disableAnimationsOf(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              if (!size.isFinite || size.isEmpty) {
                return const SizedBox.shrink();
              }
              Widget source;
              switch (options.type) {
                case ChatBackgroundType.gradient:
                  source = ChatGradientBackgroundHost(
                    enabled: options.gradientAnimated,
                    phase: options.gradientPhase,
                    offset: Offset(
                      options.gradientOffsetX,
                      options.gradientOffsetY,
                    ),
                    onFrame: widget.onGradientFrame,
                    child: const ChatGradientBackground(),
                  );
                case ChatBackgroundType.video:
                  source = _VideoBackground(
                    path: options.path ?? '',
                    fit: _fit(options.fit),
                    alignment: alignment,
                  );
                case ChatBackgroundType.image:
                case ChatBackgroundType.gif:
                  final path = options.path;
                  if (path == null || path.isEmpty) {
                    source = const SizedBox.expand();
                  } else {
                    source = Image(
                      image: _provider(
                        path,
                        size,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      width: size.width,
                      height: size.height,
                      fit: options.fit == ChatBackgroundFit.tile
                          ? BoxFit.none
                          : _fit(options.fit),
                      repeat: options.fit == ChatBackgroundFit.tile
                          ? ImageRepeat.repeat
                          : ImageRepeat.noRepeat,
                      alignment: alignment,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, _) {
                        if (frame != null &&
                            options.type == ChatBackgroundType.image) {
                          final decoded = (_imageProvider!, frame);
                          if (_decodedFrame != decoded) {
                            _decodedFrame = decoded;
                            final scope =
                                ChatFrostedBackdropScope.maybeOfStatic(context);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) scope?.onPixelsChanged?.call();
                            });
                          }
                        }
                        return child;
                      },
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    );
                  }
                case ChatBackgroundType.none:
                  source = const SizedBox.expand();
              }
              if (_colorFilter != null) {
                source = ColorFiltered(
                  colorFilter: _colorFilter!,
                  child: source,
                );
              }
              if (_blurFilter != null) {
                source = ImageFiltered(
                  imageFilter: _blurFilter!,
                  child: source,
                );
              }
              final mask = options.maskStrength;
              return ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.includeSurfaceFill)
                      ColoredBox(color: cs.surface),
                    source,
                    if (mask > 0)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cs.surface.withValues(
                                alpha: ((widget.desktop ? 0.08 : 0.20) * mask)
                                    .clamp(0, 1),
                              ),
                              cs.surface.withValues(
                                alpha: ((widget.desktop ? 0.36 : 0.50) * mask)
                                    .clamp(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

BoxFit _fit(ChatBackgroundFit fit) => switch (fit) {
  ChatBackgroundFit.cover || ChatBackgroundFit.tile => BoxFit.cover,
  ChatBackgroundFit.contain => BoxFit.contain,
  ChatBackgroundFit.fill => BoxFit.fill,
};

class _VideoBackground extends StatefulWidget {
  const _VideoBackground({
    required this.path,
    required this.fit,
    required this.alignment,
  });

  final String path;
  final BoxFit fit;
  final Alignment alignment;

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  (String, int, int)? _sourceIdentity;
  var _generation = 0;
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSource();
    _updatePlayback();
  }

  @override
  void didUpdateWidget(_VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _updateSource();
    _updatePlayback();
  }

  void _updateSource() {
    final mq = MediaQuery.of(context);
    final identity = (
      widget.path,
      (mq.size.width * mq.devicePixelRatio).ceil().clamp(1, 16384),
      (mq.size.height * mq.devicePixelRatio).ceil().clamp(1, 16384),
    );
    if (_sourceIdentity == identity) return;
    _sourceIdentity = identity;
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    _initialized = false;
    if (previous != null) unawaited(previous.dispose());
    if (widget.path.isNotEmpty) unawaited(_initialize(identity, generation));
  }

  Future<void> _initialize((String, int, int) identity, int generation) async {
    VideoPlayerController? controller;
    try {
      final path = await ChatBackgroundVideo.prepare(
        SandboxPathResolver.fix(identity.$1),
        maxWidth: identity.$2,
        maxHeight: identity.$3,
      );
      if (!mounted || generation != _generation) return;
      final file = File(path);
      final options = VideoPlayerOptions(
        allowBackgroundPlayback: true,
        mixWithOthers: true,
        preventsDisplaySleepDuringVideoPlayback: false,
      );
      controller =
          debugChatBackgroundVideoControllerFactory?.call(file, options) ??
          VideoPlayerController.file(file, videoPlayerOptions: options);
      _controller = controller;
      await controller.initialize();
      if (!_isCurrent(controller, generation)) return;
      await controller.setVolume(0);
      if (!_isCurrent(controller, generation)) return;
      await controller.setLooping(true);
      if (!_isCurrent(controller, generation)) return;
      setState(() => _initialized = true);
      _updatePlayback();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _controller = null;
      _initialized = false;
      if (controller != null) unawaited(controller.dispose());
      setState(() {});
    }
  }

  bool _isCurrent(VideoPlayerController controller, int generation) =>
      mounted &&
      generation == _generation &&
      identical(_controller, controller);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _updatePlayback();

  void _updatePlayback() {
    final controller = _controller;
    if (!_initialized || controller == null) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final play =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    if (play == controller.value.isPlaying) return;
    final operation = play ? controller.play() : controller.pause();
    unawaited(operation.catchError((Object _) {}));
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_initialized || controller == null) return const SizedBox.expand();
    final size = controller.value.size;
    if (size.isEmpty) return const SizedBox.expand();
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          alignment: widget.alignment,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
