import 'package:flutter/material.dart';

import '../domain/urgency.dart';

/// Raw design tokens. Widgets should prefer Theme / [UrgencyColors] over these.
abstract final class AppPalette {
  static const background = Color(0xFF121417); // deep midnight charcoal
  static const surface = Color(0xFF1A1D24); // card surface
  static const surfaceVariant = Color(0xFF242831);
  static const outline = Color(0xFF2E333D);
  static const textPrimary = Color(0xFFE6EDF3);
  static const textMuted = Color(0xFF8B949E);

  static const sage = Color(0xFF8FB996); // safe, > 14 days
  static const honey = Color(0xFFE2B874); // impending, 3–14 days
  static const terracotta = Color(0xFFE07A7A); // immediate, < 72 hrs
  static const periwinkle = Color(0xFF7A9EC7); // informational
  static const lavender = Color(0xFFB39DDB); // answer key stage (muted, not neon)
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

  static const darkPastel = UrgencyColors(
    safe: AppPalette.sage,
    warning: AppPalette.honey,
    urgent: AppPalette.terracotta,
    info: AppPalette.periwinkle,
  );

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
      Theme.of(this).extension<UrgencyColors>() ?? UrgencyColors.darkPastel;
}

abstract final class AppTheme {
  static ThemeData darkPastel() {
    const scheme = ColorScheme.dark(
      primary: AppPalette.periwinkle,
      onPrimary: AppPalette.background,
      secondary: AppPalette.sage,
      onSecondary: AppPalette.background,
      tertiary: AppPalette.honey,
      onTertiary: AppPalette.background,
      error: AppPalette.terracotta,
      onError: AppPalette.background,
      surface: AppPalette.surface,
      onSurface: AppPalette.textPrimary,
      onSurfaceVariant: AppPalette.textMuted,
      surfaceContainerHighest: AppPalette.surfaceVariant,
      surfaceContainerHigh: AppPalette.surfaceVariant,
      surfaceContainer: AppPalette.surface,
      outline: AppPalette.outline,
      outlineVariant: AppPalette.outline,
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
    final base = Typography.material2021(platform: TargetPlatform.android)
        .white
        .merge(custom)
        .apply(bodyColor: AppPalette.textPrimary, displayColor: AppPalette.textPrimary);
    final text = base.copyWith(
      bodySmall: base.bodySmall?.copyWith(color: AppPalette.textMuted),
      labelSmall: base.labelSmall?.copyWith(color: AppPalette.textMuted),
    );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control));
    const minTap = Size(48, 48);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppPalette.background,
      canvasColor: AppPalette.background,
      textTheme: text,
      dividerTheme: const DividerThemeData(color: AppPalette.outline, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: AppPalette.textMuted, size: 22),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: minTap, shape: controlShape, textStyle: text.labelLarge),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minTap,
          shape: controlShape,
          foregroundColor: AppPalette.textPrimary,
          side: const BorderSide(color: AppPalette.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minTap, shape: controlShape, textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surfaceVariant,
        labelStyle: const TextStyle(color: AppPalette.textMuted),
        hintStyle: const TextStyle(color: AppPalette.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppPalette.periwinkle, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.surfaceVariant,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppPalette.surfaceVariant,
        contentTextStyle: text.bodyMedium,
        actionTextColor: AppPalette.periwinkle,
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppPalette.surface,
        modalBackgroundColor: AppPalette.surface,
        showDragHandle: true,
        dragHandleColor: AppPalette.textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
      ),
      popupMenuTheme: PopupMenuThemeData(color: AppPalette.surfaceVariant, shape: controlShape),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppPalette.periwinkle),
      extensions: const [UrgencyColors.darkPastel],
    );
  }
}
