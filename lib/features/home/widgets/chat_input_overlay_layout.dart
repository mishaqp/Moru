import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ChatInputOverlayLayout extends StatelessWidget {
  const ChatInputOverlayLayout({
    super.key,
    required this.topInset,
    required this.content,
    required this.bottomOverlay,
    this.topBackground,
    this.foreground,
    this.backgroundImageActive = false,
    this.frostedTopSigma,
  });

  static const double _topOverlayTailHeight = 24;
  static const double _bottomOverlayFadeHeight = 180;

  final double topInset;
  final Widget content;
  final Widget bottomOverlay;
  final Widget? topBackground;
  final Widget? foreground;
  final bool backgroundImageActive;

  /// Glass theme: the header strip blurs the chat scrolled under it instead of
  /// covering it with a copy of the background. Null keeps the copy.
  final double? frostedTopSigma;

  @override
  Widget build(BuildContext context) {
    // Keep message layout and scroll geometry intact while exposing the single
    // wallpaper under the plain header and system gesture area. Glass keeps
    // messages beneath the header so its existing blur can sample them.
    final messageTopInset =
        backgroundImageActive &&
            topBackground == null &&
            frostedTopSigma == null
        ? topInset
        : 0.0;
    final messageBottomInset = backgroundImageActive
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    final messageContent = messageTopInset > 0 || messageBottomInset > 0
        ? ClipRect(
            clipper: _MessageViewportClipper(
              topInset: messageTopInset,
              bottomInset: messageBottomInset,
            ),
            child: content,
          )
        : content;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(child: messageContent),
              if (backgroundImageActive && frostedTopSigma != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: topInset,
                  child: _FrostedTopBar(sigma: frostedTopSigma!),
                )
              else if (backgroundImageActive && topBackground != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ClipRect(
                      clipper: _TopOverlayClipper(
                        topInset + _topOverlayTailHeight,
                      ),
                      child: _TopBackgroundFade(
                        solidHeight: topInset,
                        height: topInset + _topOverlayTailHeight,
                        child: IgnorePointer(
                          key: const Key('chat-input-overlay-top-background'),
                          child: _KeyboardStableBackground(
                            child: topBackground!,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: topInset + _topOverlayTailHeight,
                  child: _TopOverlayFade(
                    solidFraction:
                        topInset / (topInset + _topOverlayTailHeight),
                    translucent: backgroundImageActive,
                  ),
                ),
              if (backgroundImageActive && topBackground != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ClipRect(
                      clipper: const _BottomOverlayClipper(
                        _bottomOverlayFadeHeight,
                      ),
                      child: _BottomBackgroundFade(
                        height: _bottomOverlayFadeHeight,
                        child: IgnorePointer(
                          key: const Key(
                            'chat-input-overlay-bottom-background',
                          ),
                          child: _KeyboardStableBackground(
                            child: topBackground!,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _bottomOverlayFadeHeight,
                  child: _BottomOverlayFade(translucent: backgroundImageActive),
                ),
              if (foreground != null) Positioned.fill(child: foreground!),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: UnconstrainedBox(
            constrainedAxis: Axis.horizontal,
            alignment: Alignment.bottomCenter,
            child: bottomOverlay,
          ),
        ),
      ],
    );
  }
}

class _MessageViewportClipper extends CustomClipper<Rect> {
  const _MessageViewportClipper({
    required this.topInset,
    required this.bottomInset,
  });

  final double topInset;
  final double bottomInset;

  @override
  Rect getClip(Size size) {
    final top = topInset.clamp(0.0, size.height);
    final bottom = (size.height - bottomInset).clamp(top, size.height);
    return Rect.fromLTRB(0, top, size.width, bottom);
  }

  @override
  bool shouldReclip(_MessageViewportClipper oldClipper) =>
      topInset != oldClipper.topInset || bottomInset != oldClipper.bottomInset;
}

/// Lays the chat artwork out as if the keyboard were closed, letting the extra
/// height overflow behind the IME instead of shrinking with the Scaffold body.
/// A `BoxFit.cover` background re-crops whenever its box changes height, so
/// without this the whole image visibly jumps upwards as the keyboard opens.
///
/// The inset has to come from the [View]: Scaffold strips the bottom view inset
/// off the MediaQuery it hands to its body, so reading it from MediaQuery here
/// would always yield zero. Reading it inside the [LayoutBuilder] also keeps it
/// in sync, because the body's constraints change on the very same frame.
class _KeyboardStableBackground extends StatelessWidget {
  const _KeyboardStableBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) return child;
          final view = View.of(context);
          final bottomInset = view.viewInsets.bottom / view.devicePixelRatio;
          if (bottomInset <= 0) return child;
          final height = constraints.maxHeight + bottomInset;
          return OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: height,
            maxHeight: height,
            child: child,
          );
        },
      ),
    );
  }
}

class _TopOverlayClipper extends CustomClipper<Rect> {
  const _TopOverlayClipper(this.height);

  final double height;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width, height.clamp(0, size.height));
  }

  @override
  bool shouldReclip(_TopOverlayClipper oldClipper) {
    return height != oldClipper.height;
  }
}

class _BottomOverlayClipper extends CustomClipper<Rect> {
  const _BottomOverlayClipper(this.height);

  final double height;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      0,
      (size.height - height).clamp(0, size.height),
      size.width,
      height.clamp(0, size.height),
    );
  }

  @override
  bool shouldReclip(_BottomOverlayClipper oldClipper) {
    return height != oldClipper.height;
  }
}

class _TopBackgroundFade extends StatelessWidget {
  const _TopBackgroundFade({
    required this.solidHeight,
    required this.height,
    required this.child,
  });

  /// The header stays fully covered; only the tail below it fades.
  final double solidHeight;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, height <= 0 ? 0.0 : solidHeight / height, 1.0],
          colors: [surface, surface, surface.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, height));
      },
      child: child,
    );
  }
}

class _BottomBackgroundFade extends StatelessWidget {
  const _BottomBackgroundFade({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.48, 1.0],
          colors: [
            surface.withValues(alpha: 0),
            surface.withValues(alpha: isDark ? 0.74 : 0.82),
            surface.withValues(alpha: isDark ? 0.92 : 0.98),
          ],
        ).createShader(
          Rect.fromLTWH(0, bounds.height - height, bounds.width, height),
        );
      },
      child: child,
    );
  }
}

class _TopOverlayFade extends StatelessWidget {
  const _TopOverlayFade({
    required this.solidFraction,
    this.translucent = false,
  });

  /// Share of the height behind the header before the veil fades out.
  final double solidFraction;
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    // Artwork already covers the entire Scaffold. Keep it visible through the
    // header without mounting another image, gradient or video player here.
    final alpha = translucent ? (isDark ? 0.28 : 0.42) : 1.0;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.0, solidFraction, 1.0],
      colors: [
        surface.withValues(alpha: alpha),
        surface.withValues(alpha: (isDark ? 0.97 : 0.99) * alpha),
        surface.withValues(alpha: 0),
      ],
    );

    return IgnorePointer(
      key: const Key('chat-input-overlay-top-fade'),
      child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
    );
  }
}

class _BottomOverlayFade extends StatelessWidget {
  const _BottomOverlayFade({this.translucent = false});

  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final alpha = translucent ? (isDark ? 0.28 : 0.42) : 1.0;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      // Without artwork, the gesture strip stays opaque. With artwork, the
      // same veil follows the composer above the keyboard and preserves it.
      stops: const [0.0, 0.48, 0.8, 1.0],
      colors: [
        surface.withValues(alpha: 0),
        surface.withValues(alpha: (isDark ? 0.64 : 0.82) * alpha),
        surface.withValues(alpha: alpha),
        surface.withValues(alpha: alpha),
      ],
    );

    return IgnorePointer(
      key: const Key('chat-input-overlay-bottom-fade'),
      child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
    );
  }
}

/// Frosted glass behind the chat header: blurs whatever scrolls under it.
class _FrostedTopBar extends StatelessWidget {
  const _FrostedTopBar({required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    return IgnorePointer(
      key: const Key('chat-input-overlay-top-frosted'),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: isDark ? 0.28 : 0.42),
              border: Border(
                bottom: BorderSide(
                  color: cs.onSurface.withValues(alpha: isDark ? 0.12 : 0.08),
                  width: 0.8,
                ),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
