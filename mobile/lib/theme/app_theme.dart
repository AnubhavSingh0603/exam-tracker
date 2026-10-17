import 'package:flutter/material.dart';

import '../domain/urgency.dart';

/// The colours. Two moods, each with a Govt and a Private face (switching
/// workspace swaps the whole palette):
/// - Dark, "Dusk": plum and lavender for Govt, espresso and saffron for Private.
/// - Light, "Sea Glass" (A Dictionary of Color Combinations, No. 281 / 151): Nile
///   blue and Antwarp blue for Govt, pale lemon and Vandar Poel's blue for Private.
/// Deadlines avoid traffic lights: pink = last days, peach/amber = soon, blue = plenty.
@immutable
class Palette {
  const Palette({
    required this.isLight,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.outline,
    required this.cardBase,
    required this.textPrimary,
    required this.textMuted,
    required this.sage,
    required this.honey,
    required this.terracotta,
    required this.periwinkle,
    required this.lavender,
    required this.onAccent,
    required this.sky,
  });

  final bool isLight;
  final Color background;
  final Color surface; // cards
  final Color surfaceVariant; // chips, fields, inner panels
  final Color outline;
  final Color cardBase; // the "3D" edge under a card
  final Color textPrimary;
  final Color textMuted;
  final Color sage; // blue: done, plenty of time (> 14 days)
  final Color honey; // peach / amber: soon (3–14 days)
  final Color terracotta; // pink: last days (< 72 hrs)
  final Color periwinkle; // the workspace's main colour
  final Color lavender; // rose: the answer-key stage
  final Color onAccent; // text on the main colour
  final Color sky; // the moon (dark) or sun (light) over the mountains

  static const duskGovt = Palette(
    isLight: false,
    background: Color(0xFF1A1220), // plum
    surface: Color(0xFF281C30),
    surfaceVariant: Color(0xFF372742),
    outline: Color(0xFF4A3857),
    cardBase: Color(0xFF110A15),
    textPrimary: Color(0xFFFBF2FF),
    textMuted: Color(0xFFBFA9CC),
    sage: Color(0xFF8FB8FF),
    honey: Color(0xFFFFB570),
    terracotta: Color(0xFFFF6FA8),
    periwinkle: Color(0xFFC3A6FF), // lavender
    lavender: Color(0xFFFF9EC4),
    onAccent: Color(0xFF1E0F3A),
    sky: Color(0xFFF3E6D0), // moon
  );

  static const duskPrivate = Palette(
    isLight: false,
    background: Color(0xFF1A150F), // espresso
    surface: Color(0xFF2A2219),
    surfaceVariant: Color(0xFF3B3125),
    outline: Color(0xFF4C4031),
    cardBase: Color(0xFF100C07),
    textPrimary: Color(0xFFFFF6EA),
    textMuted: Color(0xFFCDB89E),
    sage: Color(0xFF8FB8FF),
    honey: Color(0xFFFF9A62),
    terracotta: Color(0xFFFF6FA8),
    periwinkle: Color(0xFFFFB547), // saffron
    lavender: Color(0xFFFF9EC4),
    onAccent: Color(0xFF2E1A00),
    sky: Color(0xFFF3E6D0),
  );

  static const seaGovt = Palette(
    isLight: true,
    background: Color(0xFFE4F3F2), // Nile blue, light
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFD3EAE9),
    outline: Color(0xFFBFDCDB),
    cardBase: Color(0xFFC3DEDD),
    textPrimary: Color(0xFF0F2A33),
    textMuted: Color(0xFF4E6770),
    sage: Color(0xFF40456A), // violet blue
    honey: Color(0xFF94570F), // raw sienna, deepened for text
    terracotta: Color(0xFFB71F57), // pomegranate purple
    periwinkle: Color(0xFF007190), // Antwarp blue
    lavender: Color(0xFF8C4C62), // veronia purple
    onAccent: Color(0xFFFFFFFF),
    sky: Color(0xFFFDBF68), // sun
  );

  static const seaPrivate = Palette(
    isLight: true,
    background: Color(0xFFFFF6D6), // pale lemon
    surface: Color(0xFFFFFDF4),
    surfaceVariant: Color(0xFFF3E8BF),
    outline: Color(0xFFE6D8A6),
    cardBase: Color(0xFFE9DCA8),
    textPrimary: Color(0xFF0B2A36),
    textMuted: Color(0xFF5B6458),
    sage: Color(0xFF40456A),
    honey: Color(0xFF94570F),
    terracotta: Color(0xFFB71F57),
    periwinkle: Color(0xFF064F6E), // Vandar Poel's blue
    lavender: Color(0xFF8C4C62),
    onAccent: Color(0xFFFFFFFF),
    sky: Color(0xFFF99D1B),
  );

  /// The Govt palettes, under their old names.
  static const dark = duskGovt;
  static const light = seaGovt;

  static Palette of(Brightness brightness, {bool private = false}) => brightness == Brightness.light
      ? (private ? seaPrivate : seaGovt)
      : (private ? duskPrivate : duskGovt);
}

/// The active palette's colours. Switched by the app root before anything below
/// it builds (the whole screen is rebuilt when light/dark or the workspace changes).
abstract final class AppPalette {
  static Palette _current = Palette.dark;

  static Palette get current => _current;
  static void use(Brightness brightness, {bool private = false}) =>
      _current = Palette.of(brightness, private: private);

  static Color get background => _current.background;
  static Color get surface => _current.surface;
  static Color get surfaceVariant => _current.surfaceVariant;
  static Color get outline => _current.outline;
  static Color get cardBase => _current.cardBase;
  static Color get textPrimary => _current.textPrimary;
  static Color get textMuted => _current.textMuted;
  static Color get sage => _current.sage;
  static Color get honey => _current.honey;
  static Color get terracotta => _current.terracotta;
  static Color get periwinkle => _current.periwinkle;
  static Color get lavender => _current.lavender;
  static Color get onAccent => _current.onAccent;
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

  static ThemeData of(Brightness brightness, {bool private = false}) {
    final light = brightness == Brightness.light;
    final p = Palette.of(brightness, private: private);
    final scheme = (light ? ColorScheme.light : ColorScheme.dark)(
      primary: p.periwinkle,
      onPrimary: p.onAccent,
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
