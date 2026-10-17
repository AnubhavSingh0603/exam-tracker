import 'package:flutter/material.dart';

import '../domain/urgency.dart';

/// One set of colours: bright and playful. Dark is a deep violet-navy with the full
/// brights; light is a soft lilac white with deeper shades of the same hues, so text
/// on it stays readable (yellow text on white would vanish, so "soon" turns amber).
@immutable
class Palette {
  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.outline,
    required this.textPrimary,
    required this.textMuted,
    required this.sage,
    required this.honey,
    required this.terracotta,
    required this.periwinkle,
    required this.lavender,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color outline;
  final Color textPrimary;
  final Color textMuted;
  final Color sage; // mint: done, safe (> 14 days)
  final Color honey; // sunny: soon (3–14 days)
  final Color terracotta; // coral: urgent (< 72 hrs)
  final Color periwinkle; // violet: the app's main colour, information
  final Color lavender; // pink: the answer-key stage

  static const dark = Palette(
    background: Color(0xFF110E24), // deep violet-navy
    surface: Color(0xFF1C1838),
    surfaceVariant: Color(0xFF2A2452),
    outline: Color(0xFF3A3370),
    textPrimary: Color(0xFFF4F2FF),
    textMuted: Color(0xFFA8A3D1),
    sage: Color(0xFF2BD9A0), // mint
    honey: Color(0xFFFFC93C), // sunny yellow
    terracotta: Color(0xFFFF6B6B), // coral
    periwinkle: Color(0xFFA594FF), // violet, lifted for the dark background
    lavender: Color(0xFFF472B6), // pink
  );

  static const light = Palette(
    background: Color(0xFFF5F3FF), // soft lilac white
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFECE8FF),
    outline: Color(0xFFDDD6FE),
    textPrimary: Color(0xFF1F1A3D),
    textMuted: Color(0xFF635D8A),
    sage: Color(0xFF0E9F6E), // mint, deepened for text on white
    honey: Color(0xFFB45309), // amber: yellow can't be read on white
    terracotta: Color(0xFFE5484D), // coral
    periwinkle: Color(0xFF6B4EF0), // violet
    lavender: Color(0xFFDB2777), // pink
  );
}

/// The active palette's colours. Switched by the app root before anything below
/// it builds (the whole screen is rebuilt when light/dark changes).
abstract final class AppPalette {
  static Palette _current = Palette.dark;

  static Palette get current => _current;
  static void use(Brightness brightness) =>
      _current = brightness == Brightness.light ? Palette.light : Palette.dark;

  static Color get background => _current.background;
  static Color get surface => _current.surface;
  static Color get surfaceVariant => _current.surfaceVariant;
  static Color get outline => _current.outline;
  static Color get textPrimary => _current.textPrimary;
  static Color get textMuted => _current.textMuted;
  static Color get sage => _current.sage;
  static Color get honey => _current.honey;
  static Color get terracotta => _current.terracotta;
  static Color get periwinkle => _current.periwinkle;
  static Color get lavender => _current.lavender;
}

abstract final class AppRadii {
  static const card = 22.0;
  static const control = 16.0;
  static const sheet = 28.0;
}

/// Urgency palette as a ThemeExtension so it lerps with theme changes and can
/// be swapped (e.g. a future high-contrast variant) without touching widgets.
@immutable
class UrgencyColors extends ThemeExtension<UrgencyColors> {
  const UrgencyColors({
    required this.safe,
    required this.warning,
    required this.urgent,
    required this.info,
  });

  final Color safe;
  final Color warning;
  final Color urgent;
  final Color info;

  factory UrgencyColors.of(Palette p) =>
      UrgencyColors(safe: p.sage, warning: p.honey, urgent: p.terracotta, info: p.periwinkle);

  static final darkPastel = UrgencyColors.of(Palette.dark);

  Color of(Urgency u) => switch (u) {
        Urgency.safe => safe,
        Urgency.warning => warning,
        Urgency.urgent => urgent,
        Urgency.info => info,
      };

  /// Low-alpha fill: colour carries meaning without flooding large areas.
  Color tint(Urgency u, [double alpha = 0.14]) => of(u).withValues(alpha: alpha);

  @override
  UrgencyColors copyWith({Color? safe, Color? warning, Color? urgent, Color? info}) =>
      UrgencyColors(
        safe: safe ?? this.safe,
        warning: warning ?? this.warning,
        urgent: urgent ?? this.urgent,
        info: info ?? this.info,
      );

  @override
  UrgencyColors lerp(ThemeExtension<UrgencyColors>? other, double t) {
    if (other is! UrgencyColors) return this;
    return UrgencyColors(
      safe: Color.lerp(safe, other.safe, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      urgent: Color.lerp(urgent, other.urgent, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension UrgencyColorsContext on BuildContext {
  UrgencyColors get urgencyColors =>
      Theme.of(this).extension<UrgencyColors>() ?? UrgencyColors.of(AppPalette.current);
}

abstract final class AppTheme {
  static ThemeData darkPastel() => of(Brightness.dark);

  static ThemeData of(Brightness brightness) {
    final light = brightness == Brightness.light;
    final p = light ? Palette.light : Palette.dark;
    final scheme = (light ? ColorScheme.light : ColorScheme.dark)(
      primary: p.periwinkle,
      onPrimary: light ? Colors.white : p.background,
      secondary: p.sage,
      onSecondary: p.background,
      tertiary: p.honey,
      onTertiary: p.background,
      error: p.terracotta,
      onError: p.background,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textMuted,
      surfaceContainerHighest: p.surfaceVariant,
      surfaceContainerHigh: p.surfaceVariant,
      surfaceContainer: p.surface,
      outline: p.outline,
      outlineVariant: p.outline,
      surfaceTint: Colors.transparent, // no M3 elevation tint wash
    );

    // Nunito: rounded and friendly. Bold headings and labels give the game-like punch;
    // body text stays regular with generous line height, never all-caps.
    const custom = TextTheme(
      headlineSmall: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.25),
      titleMedium: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.3),
      titleSmall: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, height: 1.45),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
    );
    final base = (light
            ? Typography.material2021(platform: TargetPlatform.android).black
            : Typography.material2021(platform: TargetPlatform.android).white)
        .merge(custom)
        .apply(fontFamily: 'Nunito', bodyColor: p.textPrimary, displayColor: p.textPrimary);
    final text = base.copyWith(
      bodySmall: base.bodySmall?.copyWith(color: p.textMuted),
      labelSmall: base.labelSmall?.copyWith(color: p.textMuted),
    );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control));
    const minTap = Size(48, 50);

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito',
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textMuted, size: 22),
      // Chunky, bright buttons with a soft coloured shadow: they look tappable.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minTap,
          shape: controlShape,
          textStyle: text.labelLarge,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minTap,
          shape: controlShape,
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.outline, width: 2),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minTap, shape: controlShape, textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceVariant,
        labelStyle: TextStyle(color: p.textMuted),
        hintStyle: TextStyle(color: p.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: p.periwinkle, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceVariant,
        selectedColor: p.periwinkle.withValues(alpha: 0.22),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.periwinkle.withValues(alpha: 0.2),
        indicatorShape: const StadiumBorder(),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: text.labelLarge,
          side: BorderSide(color: p.outline, width: 2),
          // The default picks a dark "on container" colour: unreadable on the dark theme.
          foregroundColor: p.textMuted,
          selectedForegroundColor: p.textPrimary,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.sage : null),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceVariant,
        contentTextStyle: text.bodyMedium,
        actionTextColor: p.periwinkle,
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        showDragHandle: true,
        dragHandleColor: p.textMuted,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
      ),
      popupMenuTheme: PopupMenuThemeData(color: p.surfaceVariant, shape: controlShape),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.periwinkle),
      extensions: [UrgencyColors.of(p)],
    );
  }
}
