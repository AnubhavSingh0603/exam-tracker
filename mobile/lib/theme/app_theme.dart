import 'package:flutter/material.dart';

import '../domain/urgency.dart';

/// One set of colours. Dark is the original calm charcoal; light is a warm paper
/// white with deeper accents, so text on it keeps a readable contrast.
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
  final Color sage; // safe, > 14 days
  final Color honey; // impending, 3–14 days
  final Color terracotta; // immediate, < 72 hrs
  final Color periwinkle; // informational
  final Color lavender; // answer key stage (muted, not neon)

  static const dark = Palette(
    background: Color(0xFF121417), // deep midnight charcoal
    surface: Color(0xFF1A1D24),
    surfaceVariant: Color(0xFF242831),
    outline: Color(0xFF2E333D),
    textPrimary: Color(0xFFE6EDF3),
    textMuted: Color(0xFF8B949E),
    sage: Color(0xFF8FB996),
    honey: Color(0xFFE2B874),
    terracotta: Color(0xFFE07A7A),
    periwinkle: Color(0xFF7A9EC7),
    lavender: Color(0xFFB39DDB),
  );

  static const light = Palette(
    background: Color(0xFFF6F4EF), // warm paper
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEDEAE3),
    outline: Color(0xFFDAD6CC),
    textPrimary: Color(0xFF1E2228),
    textMuted: Color(0xFF5E6570),
    sage: Color(0xFF3F7D4E),
    honey: Color(0xFF9A6A12),
    terracotta: Color(0xFFB8463F),
    periwinkle: Color(0xFF3E5FA3),
    lavender: Color(0xFF6E52A8),
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
  static const card = 16.0;
  static const control = 12.0;
  static const sheet = 24.0;
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

    // Calm, readable type: generous line height, no all-caps, weights max 600.
    const custom = TextTheme(
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35, letterSpacing: 0.1),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45),
      bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.4),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4),
    );
    final base = (light
            ? Typography.material2021(platform: TargetPlatform.android).black
            : Typography.material2021(platform: TargetPlatform.android).white)
        .merge(custom)
        .apply(bodyColor: p.textPrimary, displayColor: p.textPrimary);
    final text = base.copyWith(
      bodySmall: base.bodySmall?.copyWith(color: p.textMuted),
      labelSmall: base.labelSmall?.copyWith(color: p.textMuted),
    );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control));
    const minTap = Size(48, 48);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textMuted, size: 22),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: minTap, shape: controlShape, textStyle: text.labelLarge),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minTap,
          shape: controlShape,
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.outline),
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
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
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
