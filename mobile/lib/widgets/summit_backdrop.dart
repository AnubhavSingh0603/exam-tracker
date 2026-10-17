import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// How much of the mountain each screen shows below the status bar: all of it
/// (with the moon or sun) on Today, half on Jobs, a strip on My exams, none on
/// Agenda. Switching tabs slides it between these.
abstract final class SummitHeights {
  static const full = 236.0;
  static const today = full;
  static const jobs = 150.0;
  static const exams = 92.0;
  static const agenda = 0.0;

  static const privateRoles = 206.0;
  static const privateApplications = 118.0;
  static const privateProfile = 168.0;

  /// The Govt tabs, in order: Today, Jobs, My exams, Agenda.
  static const govtTabs = [today, jobs, exams, agenda];

  /// The Private tabs: Roles, Applications, Profile.
  static const privateTabs = [privateRoles, privateApplications, privateProfile];
}

/// The paper-cut Summit behind the screens: a moon (dark) or sun (light) over three
/// layers of paper mountains with soft shadows, and paper waves above the bottom
/// bar. [height] is how much shows under the status bar; a new value slides the
/// mountains up out of sight or back down (instantly with "Remove animations").
class SummitBackdrop extends StatelessWidget {
  const SummitBackdrop({super.key, required this.height, this.waves = true});

  final double height;
  final bool waves;

  static const duration = Duration(milliseconds: 520);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final colors = SummitColors.of(AppPalette.current);
    return Stack(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: height),
          duration: motionOff(context) ? Duration.zero : duration,
          curve: Curves.easeInOutCubic,
          builder: (context, h, _) => Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h <= 0.5 ? 0 : top + h,
            child: ClipRect(
              child: CustomPaint(painter: SummitPainter(colors, sceneHeight: top + SummitHeights.full)),
            ),
          ),
        ),
        if (waves)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 72,
            child: IgnorePointer(child: CustomPaint(painter: _WavesPainter(colors))),
          ),
      ],
    );
  }
}

/// The scene's colours, from a palette.
@immutable
class SummitColors {
  const SummitColors({
    required this.sky,
    required this.far,
    required this.mid,
    required this.front,
    required this.shadow,
    required this.snow,
    required this.orb,
    required this.stars,
    required this.wave1,
    required this.wave2,
  });

  final Color sky;
  final Color far;
  final Color mid;
  final Color front;
  final Color shadow;
  final Color snow;
  final Color orb; // the moon, or the sun
  final Color? stars; // night only
  final Color wave1;
  final Color wave2;

  factory SummitColors.of(Palette p) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    if (p.isLight) {
      return SummitColors(
        sky: mix(p.background, Colors.white, 0.6),
        far: mix(p.background, p.periwinkle, 0.22),
        mid: mix(p.background, p.periwinkle, 0.10),
        front: p.background,
        shadow: p.textPrimary.withValues(alpha: 0.10),
        snow: Colors.white,
        orb: p.sky,
        stars: null,
        wave1: mix(p.background, p.sky, 0.2),
        wave2: mix(p.background, p.sky, 0.38),
      );
    }
    return SummitColors(
      sky: mix(p.background, p.surface, 0.35),
      far: mix(p.background, p.outline, 0.75),
      mid: mix(p.background, p.surfaceVariant, 0.55),
      front: p.background,
      shadow: Colors.black.withValues(alpha: 0.35),
      snow: p.textPrimary,
      orb: p.sky,
      stars: p.textPrimary,
      wave1: mix(p.background, p.surface, 0.75),
      wave2: mix(p.background, p.surfaceVariant, 0.7),
    );
  }
}

/// Drawn in a 348 × 300 design space stretched to the scene, bottom-aligned in the
/// visible box: a shorter box shows only the lower part (the sky leaves first).
class SummitPainter extends CustomPainter {
  SummitPainter(this.c, {required this.sceneHeight});

  final SummitColors c;
  final double sceneHeight;

  static Path _far() => Path()
    ..moveTo(0, 190)
    ..lineTo(60, 130)
    ..lineTo(110, 170)
    ..lineTo(180, 96)
    ..lineTo(240, 150)
    ..lineTo(300, 112)
    ..lineTo(348, 150)
    ..lineTo(348, 300)
    ..lineTo(0, 300)
    ..close();

  static Path _snow() => Path()
    ..moveTo(180, 96)
    ..lineTo(196, 112)
    ..lineTo(188, 112)
    ..lineTo(176, 104)
    ..close();

  static Path _mid() => Path()
    ..moveTo(0, 232)
    ..cubicTo(40, 200, 70, 184, 100, 196)
    ..cubicTo(130, 208, 160, 162, 200, 160)
    ..cubicTo(240, 158, 262, 200, 300, 190)
    ..cubicTo(322, 184, 340, 178, 348, 180)
    ..lineTo(348, 300)
    ..lineTo(0, 300)
    ..close();

  static Path _front() => Path()
    ..moveTo(0, 270)
    ..cubicTo(60, 244, 120, 288, 180, 264)
    ..cubicTo(240, 240, 300, 278, 348, 258)
    ..lineTo(348, 300)
    ..lineTo(0, 300)
    ..close();

  static const _stars = [Offset(40, 56), Offset(110, 36), Offset(170, 66), Offset(320, 40), Offset(214, 22)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    canvas.save();
    // Bottom-align the full scene in the visible box.
    canvas.translate(0, size.height - sceneHeight);
    canvas.scale(size.width / 348, sceneHeight / 300);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 348, 300), Paint()..color = c.sky);
    final night = c.stars != null;
    // Low on the right, rising from behind the far ridge: clear of the title and avatar.
    canvas.drawCircle(const Offset(236, 112), 46, Paint()..color = c.orb.withValues(alpha: night ? 0.10 : 0.18));
    canvas.drawCircle(const Offset(236, 112), 32, Paint()..color = c.orb);
    if (night) {
      final star = Paint()..color = c.stars!.withValues(alpha: 0.8);
      for (final s in _stars) {
        canvas.drawCircle(s, 1.4, star);
      }
    }

    final shadow = Paint()..color = c.shadow;
    void layer(Path p, Color color, double drop) {
      canvas.drawPath(p.shift(Offset(0, drop)), shadow);
      canvas.drawPath(p, Paint()..color = color);
    }

    layer(_far(), c.far, 7);
    canvas.drawPath(_snow(), Paint()..color = c.snow);
    layer(_mid(), c.mid, 7);
    layer(_front(), c.front, 6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SummitPainter old) => old.c != c || old.sceneHeight != sceneHeight;
}

class _WavesPainter extends CustomPainter {
  _WavesPainter(this.c);

  final SummitColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 348, size.height / 80);
    canvas.drawPath(
      Path()
        ..moveTo(0, 30)
        ..cubicTo(60, 6, 120, 44, 180, 24)
        ..cubicTo(240, 4, 300, 34, 348, 18)
        ..lineTo(348, 80)
        ..lineTo(0, 80)
        ..close(),
      Paint()..color = c.wave1,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 56)
        ..cubicTo(70, 38, 130, 66, 200, 50)
        ..cubicTo(260, 36, 310, 58, 348, 46)
        ..lineTo(348, 80)
        ..lineTo(0, 80)
        ..close(),
      Paint()..color = c.wave2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.c != c;
}
