import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/delivery_track.dart';
import '../models/tracked_application.dart';
import '../theme/app_theme.dart';
import 'motion.dart';

/// The Summit trail (the app icon's mountain) with each tracked exam as a climber at
/// its stop: Applied at the foot, Result at the flag. Progress at a glance.
class ProgressMap extends StatelessWidget {
  const ProgressMap({super.key, required this.apps, required this.now});

  final List<TrackedApplication> apps;
  final DateTime now;

  /// Where the stops sit, as fractions of the map (foot of the trail to summit).
  static const stops = [
    Offset(0.10, 0.86), // Applied
    Offset(0.36, 0.70), // Admit card
    Offset(0.20, 0.50), // Exam
    Offset(0.46, 0.32), // Answer key
    Offset(0.62, 0.13), // Result (summit)
  ];
  static const stopNames = ['Applied', 'Admit card', 'Exam', 'Answer key', 'Result'];

  /// The stop an exam stands at: its track's current stop, the summit once done.
  static int stopOf(TrackedApplication app, DateTime now) {
    final track = buildDeliveryTrack(app, now);
    if (track.finished || track.offersNextTier) return 4;
    return track.activeIndex.clamp(0, 4);
  }

  /// "CGL", "IBPS PO", "RRB": short enough for a badge.
  static String shortName(TrackedApplication app) {
    final catalog = app.catalogExam;
    if (catalog != null) {
      // "SSC CGL", "IBPS PO" (not just "PO", which IBPS and SBI share).
      final name = catalog.name.replaceAll(RegExp(r'\s*\(.*\)'), '');
      if (name.length <= 9) return name;
      final words = name.split(' ');
      final tail = words.length > 1 ? words.sublist(1).join(' ') : name;
      return tail.length <= 8 ? tail : words.first;
    }
    final words = [
      for (final w in app.examName.split(RegExp(r'[\s·()-]+')))
        if (w.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(w)) w,
    ];
    if (words.isEmpty) return '?';
    final acronym = words.take(3).map((w) => w[0].toUpperCase()).join();
    return words.first.length <= 5 ? words.first.toUpperCase() : acronym;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final byStop = <int, List<TrackedApplication>>{};
    for (final a in apps) {
      byStop.putIfAbsent(stopOf(a, now), () => []).add(a);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: SizedBox(
        height: 210,
        child: LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth, 210);
          Offset at(int stop) => Offset(stops[stop].dx * size.width, stops[stop].dy * size.height);
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MountainPainter(Theme.of(context).brightness))),
              for (var i = 0; i < stops.length; i++)
                Positioned(
                  left: at(i).dx - 6,
                  top: at(i).dy + 7,
                  child: Text(stopNames[i],
                      style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                ),
              for (final MapEntry(key: stop, value: group) in byStop.entries)
                for (final (i, app) in group.indexed)
                  _Climber(
                    key: ValueKey('climber-${app.id}'),
                    label: shortName(app),
                    tooltip: '${app.postName}: ${buildDeliveryTrack(app, now).statusLabel}',
                    from: at(0),
                    // Several at one stop fan out left and right.
                    to: at(stop) + Offset((i.isEven ? 1 : -1) * ((i + 1) ~/ 2) * 100.0 - 10, -30 - (i.isOdd ? 6 : 0)),
                    color: _climberColors[app.id.hashCode.abs() % _climberColors.length],
                  ),
            ],
          );
        }),
      ),
    );
  }
}

List<Color> get _climberColors =>
    [AppPalette.periwinkle, AppPalette.lavender, AppPalette.sage, AppPalette.terracotta, AppPalette.honey];

/// One exam on the trail: climbs from the foot to its stop when the map appears.
class _Climber extends StatelessWidget {
  const _Climber({
    super.key,
    required this.label,
    required this.tooltip,
    required this.from,
    required this.to,
    required this.color,
  });

  final String label;
  final String tooltip;
  final Offset from;
  final Offset to;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: motionOff(context) ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) {
        final p = Offset.lerp(from, to, t)!;
        return Positioned(left: p.dx - 4, top: p.dy, child: child!);
      },
      child: Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Text(label, style: text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// Dusk sky, back hills, the mountain with its lit face and snow, the dotted trail
/// through the stops, and the flag at the top: the app icon, wide.
class _MountainPainter extends CustomPainter {
  _MountainPainter(this.brightness);

  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Offset pt(Offset f) => Offset(f.dx * w, f.dy * h);

    final sky = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [Color(0xFF2A1F6B), Color(0xFF6B4EF0), Color(0xFFF59E8B)],
          const [0, 0.6, 1]);
    canvas.drawRect(Offset.zero & s, sky);
    canvas.drawCircle(Offset(w * 0.86, h * 0.30), h * 0.12, Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.9));
    final stars = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (final f in const [Offset(0.08, 0.12), Offset(0.27, 0.06), Offset(0.78, 0.08), Offset(0.93, 0.14), Offset(0.4, 0.1)]) {
      canvas.drawCircle(pt(f), 1.4, stars);
    }

    final back = Path()
      ..moveTo(0, h * 0.72)
      ..lineTo(w * 0.18, h * 0.55)
      ..lineTo(w * 0.32, h * 0.66)
      ..lineTo(w * 0.78, h * 0.40)
      ..lineTo(w, h * 0.62)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF3A3370).withValues(alpha: 0.85));

    final peak = pt(ProgressMap.stops[4]) + const Offset(0, 6);
    final mountain = Path()
      ..moveTo(-w * 0.05, h)
      ..lineTo(peak.dx, peak.dy)
      ..lineTo(w * 1.05, h)
      ..close();
    canvas.drawPath(
      mountain,
      Paint()..shader = ui.Gradient.linear(peak, Offset(w * 0.5, h), const [Color(0xFF2E2766), Color(0xFF1A1540)]),
    );
    final lit = Path()
      ..moveTo(peak.dx, peak.dy)
      ..lineTo(w * 1.05, h)
      ..lineTo(w * 0.72, h)
      ..close();
    canvas.drawPath(lit, Paint()..color = const Color(0xFF8E7CFF).withValues(alpha: 0.45));
    final snow = Path()
      ..moveTo(peak.dx, peak.dy)
      ..lineTo(peak.dx - w * 0.05, peak.dy + h * 0.11)
      ..lineTo(peak.dx - w * 0.015, peak.dy + h * 0.08)
      ..lineTo(peak.dx + w * 0.012, peak.dy + h * 0.12)
      ..lineTo(peak.dx + w * 0.05, peak.dy + h * 0.09)
      ..close();
    canvas.drawPath(snow, Paint()..color = const Color(0xFFF4F2FF));

    // The trail: a smooth line through the stops, drawn as dots.
    final points = [for (final f in ProgressMap.stops) pt(f)];
    final trail = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      trail.quadraticBezierTo(a.dx + (mid.dx - a.dx) * 1.4, a.dy, b.dx, b.dy);
    }
    final dot = Paint()..color = const Color(0xFFFFC93C);
    for (final metric in trail.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        final pos = metric.getTangentForOffset(d)?.position;
        if (pos != null) canvas.drawCircle(pos, 1.8, dot);
      }
    }
    final stop = Paint()..color = Colors.white;
    for (final p in points) {
      canvas.drawCircle(p, 5, stop);
      canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF6B4EF0));
    }

    // The flag at the summit.
    final top = points.last;
    canvas.drawLine(top, top - const Offset(0, 26), Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round);
    final flag = Path()
      ..moveTo(top.dx + 1, top.dy - 26)
      ..lineTo(top.dx + 20, top.dy - 21)
      ..lineTo(top.dx + 1, top.dy - 16)
      ..close();
    canvas.drawPath(flag, Paint()..color = const Color(0xFF2BD9A0));
  }

  @override
  bool shouldRepaint(_MountainPainter old) => old.brightness != brightness;
}
