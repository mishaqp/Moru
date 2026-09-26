import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/settings_provider.dart';
import 'custom_theme.dart';
import 'palettes.dart';
import 'theme_factory.dart';

typedef _ThemeInput = ({
  String paletteId,
  CustomTheme? custom,
  bool dynamicColor,
  bool pureBackground,
  bool layeredSurfaces,
  String? font,
  ThemeMode mode,
  Locale? locale,
});

/// The app's light and dark themes, built from the theme settings.
@immutable
class AppThemes {
  const AppThemes({
    required this.light,
    required this.dark,
    required this.mode,
    required this.locale,
    required this.fontFamily,
  });

  final ThemeData light;
  final ThemeData dark;
  final ThemeMode mode;

  /// App language; null follows the system.
  final Locale? locale;

  /// User-selected app font, applied to every text style; null for default.
  final String? fontFamily;
}

/// Builds [AppThemes] from the settings and the wallpaper colours and hands
/// them to [builder] for the root `MaterialApp`.
class AppThemeBuilder extends StatelessWidget {
  const AppThemeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppThemes themes) builder;

  @override
  Widget build(BuildContext context) {
    // Only theme settings rebuild the app root; other settings change often
    // (model, tools, balances) and must not rebuild every screen.
    final input = context.select<SettingsProvider, _ThemeInput>(
      (s) => (
        paletteId: s.themePaletteId,
        custom: s.selectedCustomTheme,
        dynamicColor: s.useDynamicColor,
        pureBackground: s.usePureBackground,
        layeredSurfaces: s.useLayeredSurfaces,
        font: s.appFontFamily,
        mode: s.themeMode,
        locale: s.appLocaleForMaterialApp,
      ),
    );
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final isAndroid = Theme.of(context).platform == TargetPlatform.android;
        // Update dynamic color capability for settings UI (avoid notify
        // during build).
        final dynSupported =
            isAndroid && (lightDynamic != null || darkDynamic != null);
        final settings = context.read<SettingsProvider>();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          settings.setDynamicColorSupported(dynSupported);
        });

        final useDyn = isAndroid && input.dynamicColor;
        final custom = input.custom;
        final palette =
            input.paletteId == ThemePalettes.customPaletteId && custom != null
            ? buildCustomThemePalette(custom)
            : ThemePalettes.byId(input.paletteId);
        final font = input.font;
        final fontFamily = font == null || font.isEmpty ? null : font;
        return builder(
          context,
          AppThemes(
            light: _withFont(
              buildLightThemeForScheme(
                palette.light,
                dynamicScheme: useDyn ? lightDynamic : null,
                pureBackground: input.pureBackground,
                layeredSurfaces: input.layeredSurfaces,
              ),
              fontFamily,
            ),
            dark: _withFont(
              buildDarkThemeForScheme(
                palette.dark,
                dynamicScheme: useDyn ? darkDynamic : null,
                pureBackground: input.pureBackground,
                layeredSurfaces: input.layeredSurfaces,
              ),
              fontFamily,
            ),
            mode: input.mode,
            locale: input.locale,
            fontFamily: fontFamily,
          ),
        );
      },
    );
  }

  /// [base] with [family] as the font of every text theme and the app bar.
  static ThemeData _withFont(ThemeData base, String? family) {
    if (family == null) return base;
    TextStyle? withFamily(TextStyle? s) => s?.copyWith(fontFamily: family);
    TextTheme apply(TextTheme t) => t.copyWith(
      displayLarge: withFamily(t.displayLarge),
      displayMedium: withFamily(t.displayMedium),
      displaySmall: withFamily(t.displaySmall),
      headlineLarge: withFamily(t.headlineLarge),
      headlineMedium: withFamily(t.headlineMedium),
      headlineSmall: withFamily(t.headlineSmall),
      titleLarge: withFamily(t.titleLarge),
      titleMedium: withFamily(t.titleMedium),
      titleSmall: withFamily(t.titleSmall),
      bodyLarge: withFamily(t.bodyLarge),
      bodyMedium: withFamily(t.bodyMedium),
      bodySmall: withFamily(t.bodySmall),
      labelLarge: withFamily(t.labelLarge),
      labelMedium: withFamily(t.labelMedium),
      labelSmall: withFamily(t.labelSmall),
    );
    final bar = base.appBarTheme;
    return base.copyWith(
      textTheme: apply(base.textTheme),
      primaryTextTheme: apply(base.primaryTextTheme),
      appBarTheme: bar.copyWith(
        titleTextStyle: (bar.titleTextStyle ?? const TextStyle()).copyWith(
          fontFamily: family,
        ),
        toolbarTextStyle: (bar.toolbarTextStyle ?? const TextStyle()).copyWith(
          fontFamily: family,
        ),
      ),
    );
  }
}
