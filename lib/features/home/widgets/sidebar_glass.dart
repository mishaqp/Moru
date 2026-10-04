import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_appearance.dart';
import '../../../core/models/sidebar_appearance.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../shared/widgets/interactive_drawer.dart';
import '../../chat/widgets/chat_background.dart';

/// The sidebar's selected artwork and independent panel effects.
/// Glass blurs this same scene; economy mode omits the extra Glass blur.
class SidebarGlassBackdrop extends StatefulWidget {
  const SidebarGlassBackdrop({
    super.key,
    this.configuration,
    this.backgroundConfiguration,
    this.active = true,
  });

  final SidebarAppearanceSettings? configuration;
  final ChatBackgroundSettings? backgroundConfiguration;
  final bool active;

  static const double blurSigma = 26;

  @override
  State<SidebarGlassBackdrop> createState() => _SidebarGlassBackdropState();
}

class _SidebarGlassBackdropState extends State<SidebarGlassBackdrop> {
  late final _glassBlurFilter = ui.ImageFilter.blur(
    sigmaX: SidebarGlassBackdrop.blurSigma,
    sigmaY: SidebarGlassBackdrop.blurSigma,
    tileMode: TileMode.clamp,
  );
  InteractiveDrawerController? _drawer;
  var _drawerVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final drawer = InteractiveDrawer.maybeControllerOf(context);
    if (identical(drawer, _drawer)) return;
    _drawer?.removeListener(_onDrawerChanged);
    _drawer = drawer;
    _drawerVisible = drawer == null || drawer.value > 0;
    drawer?.addListener(_onDrawerChanged);
  }

  void _onDrawerChanged() {
    final visible = _drawer == null || _drawer!.value > 0;
    if (visible == _drawerVisible) return;
    setState(() => _drawerVisible = visible);
  }

  @override
  void dispose() {
    _drawer?.removeListener(_onDrawerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final appearance =
        widget.configuration ??
        context.select<SettingsProvider, SidebarAppearanceSettings>(
          (s) => s.sidebarAppearance,
        );
    final background =
        widget.backgroundConfiguration ??
        context.select<SettingsProvider, ChatBackgroundSettings>(
          (s) => appearance.backgroundFor(brightness, s.chatAppearance),
        );
    final (glass, economy) = context.select<SettingsProvider, (bool, bool)>(
      (s) => (s.glassTheme, s.glassEconomy),
    );
    final dark = brightness == Brightness.dark;
    // The panel owns masking and blur independently of the chat's settings.
    Widget scene = ChatBackground(
      configuration: background.copyWith(
        maskStrength: appearance.maskStrength,
        blur: appearance.blur,
      ),
      includeSurfaceFill: true,
      active: widget.active && _drawerVisible && appearance.opacity > 0,
    );
    if (glass && !economy) {
      scene = ImageFiltered(
        imageFilter: _glassBlurFilter,
        child: RepaintBoundary(child: scene),
      );
    }
    return IgnorePointer(
      child: Opacity(
        opacity: appearance.opacity,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              scene,
              if (glass)
                ColoredBox(
                  color: cs.surface.withValues(
                    alpha: economy ? (dark ? 0.58 : 0.5) : (dark ? 0.42 : 0.36),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps chosen artwork and translucent panel effects visible behind rows.
bool sidebarSurfacesClear(BuildContext context, {required bool embedded}) {
  final brightness = Theme.of(context).brightness;
  return embedded ||
      context.select<SettingsProvider, bool>(
        (s) =>
            s.glassTheme ||
            s.sidebarAppearance
                    .backgroundFor(brightness, s.chatAppearance)
                    .type !=
                ChatBackgroundType.none ||
            s.sidebarAppearance.opacity < 1,
      );
}

/// A light glass tile on the sidebar glass (search, buttons): a brighter
/// veil and a hairline edge. Plain surfaces without the glass theme.
BoxDecoration sidebarGlassTile(
  BuildContext context, {
  required bool glass,
  required BorderRadius radius,
  Color? fill,
}) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (!glass) {
    return BoxDecoration(
      color: fill ?? cs.surfaceContainerHighest.withValues(alpha: 0.8),
      borderRadius: radius,
    );
  }
  return BoxDecoration(
    color: fill ?? cs.surface.withValues(alpha: dark ? 0.34 : 0.55),
    borderRadius: radius,
    border: Border.all(
      color: (dark ? Colors.white : Colors.black).withValues(
        alpha: dark ? 0.1 : 0.06,
      ),
      width: 0.8,
    ),
  );
}
