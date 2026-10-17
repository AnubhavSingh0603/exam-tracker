import 'package:flutter/material.dart';

import '../models/tracked_application.dart';
import '../theme/app_theme.dart';
import 'motion.dart';
import 'summit_backdrop.dart';

/// Names under the trail's stops: the five lanes of My exams.
const kTrailStops = ['Applied', 'Admit card', 'Exam', 'Answer key', 'Result'];

/// The Summit trail on My exams: a dotted trail and its five stops (the lanes)
/// drawn onto the paper mountain, with your exams as climbers at their stop. Tap a
/// stop for its lane, a climber for its exam. Slides with the mountain, and the
/// climbers walk up to their stops each time you open the tab.
class SummitTrail extends StatefulWidget {
  const SummitTrail({
    super.key,
    required this.show,
    required this.height,
    required this.climbers,
    required this.lane,
    required this.onStop,
    required this.onClimber,
  });

  final bool show;

  /// The mountain's height right now (the same value the backdrop gets).
  final double height;

  /// Each exam with the stop (lane) it is at.
  final List<(TrackedApplication, int)> climbers;
  final int lane;
  final ValueChanged<int> onStop;
  final ValueChanged<TrackedApplication> onClimber;

  /// "CGL", "IBPS PO", "RRB": short enough for a climber's badge.
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
  State<SummitTrail> createState() => _SummitTrailState();
}

class _SummitTrailState extends State<SummitTrail> {
  int _visit = 0;

  @override
  void didUpdateWidget(SummitTrail old) {
    super.didUpdateWidget(old);
    if (widget.show && !old.show) _visit++; // the climbers walk up again
  }

  @override
  Widget build(BuildContext context) {
    final still = motionOff(context);
    final top = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      ignoring: !widget.show,
      child: AnimatedOpacity(
        opacity: widget.show ? 1 : 0,
        duration: still ? Duration.zero : const Duration(milliseconds: 320),
        child: LayoutBuilder(
          // Laid out once for where the mountain is going; the slide only moves it,
          // in step with the backdrop.
          builder: (context, box) => TweenAnimationBuilder<double>(
            tween: Tween(end: widget.height),
            duration: still ? Duration.zero : SummitBackdrop.duration,
            curve: Curves.easeInOutCubic,
            child: RepaintBoundary(child: _scene(context, box.maxWidth, top, widget.height, still)),
            builder: (context, h, child) => Transform.translate(offset: Offset(0, h - widget.height), child: child),
          ),
        ),
      ),
    );
  }

  Widget _scene(BuildContext context, double w, double top, double h, bool still) {
    final text = Theme.of(context).textTheme;
    Offset at(Offset design) => SummitScene.place(design, width: w, topInset: top, visible: h);
    final stops = [for (final s in SummitScene.stops) at(s)];
    final dots = <Offset>[
      for (final metric in SummitScene.trail().computeMetrics())
        for (var d = 0.0; d < metric.length; d += 9 * 348 / w) at(metric.getTangentForOffset(d)!.position),
    ];
    final label = text.labelSmall?.copyWith(color: AppPalette.textPrimary.withValues(alpha: 0.9), fontWeight: FontWeight.w800);
    final byStop = <int, List<TrackedApplication>>{};
    for (final (app, stop) in widget.climbers) {
      byStop.putIfAbsent(stop, () => []).add(app);
    }
    // One badge per stop, placed clear of its neighbours: above the low stops,
    // to the right of the two high ones (near the title).
    const slots = [Offset(-16, -34), Offset(-24, -34), Offset(-30, -34), Offset(14, -12), Offset(26, -14)];
    Offset clamp(Offset p) => Offset(p.dx.clamp(4, w - 96), p.dy.clamp(top + 4, double.infinity));

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _TrailPainter(dots: dots, stops: stops, lane: widget.lane))),
        ),
        // Stop names, placed clear of the trail.
        for (var i = 0; i < stops.length; i++)
          Positioned(
            left: i >= 3 ? null : stops[i].dx + 10,
            right: i >= 3 ? w - stops[i].dx + (i == 4 ? 6 : 10) : null,
            top: stops[i].dy + (i == 4 ? -30 : 2),
            child: IgnorePointer(child: Text(kTrailStops[i], style: label)),
          ),
        // Tap a stop: its lane.
        for (var i = 0; i < stops.length; i++)
          Positioned(
            left: stops[i].dx - 22,
            top: stops[i].dy - 22,
            width: 44,
            height: 44,
            child: Semantics(
              button: true,
              label: '${kTrailStops[i]} lane',
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => widget.onStop(i)),
            ),
          ),
        for (final MapEntry(key: stop, value: group) in byStop.entries)
          TweenAnimationBuilder<double>(
            key: ValueKey('climb-$_visit-$stop'),
            tween: Tween(begin: still ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) {
              final p = Offset.lerp(clamp(stops[0] + slots[0]), clamp(stops[stop] + slots[stop]), t)!;
              return Positioned(left: p.dx, top: p.dy, child: child!);
            },
            child: _Climber(
              label: group.length == 1
                  ? SummitTrail.shortName(group.first)
                  : '${SummitTrail.shortName(group.first)} +${group.length - 1}',
              color: _climberColors[group.first.id.hashCode.abs() % _climberColors.length],
              tooltip: group.length == 1
                  ? '${group.first.postName}: ${kTrailStops[stop]}'
                  : '${group.length} exams at ${kTrailStops[stop]}',
              // One exam: its journey. Several: their lane.
              onTap: () => group.length == 1 ? widget.onClimber(group.first) : widget.onStop(stop),
            ),
          ),
      ],
    );
  }
}

List<Color> get _climberColors => [AppPalette.periwinkle, AppPalette.lavender, AppPalette.sage, AppPalette.honey];

class _Climber extends StatelessWidget {
  const _Climber({required this.label, required this.color, required this.tooltip, required this.onTap});

  final String label;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: AppPalette.surface,
            shape: StadiumBorder(side: BorderSide(color: color, width: 2.5)),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: AppPalette.current.isLight ? 0.12 : 0.4),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppPalette.textPrimary, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ),
      );
}

/// The dotted trail, the stops (the chosen lane's ringed) and the flag at the top.
class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.dots, required this.stops, required this.lane});

  final List<Offset> dots;
  final List<Offset> stops;
  final int lane;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = AppPalette.honey;
    for (final d in dots) {
      canvas.drawCircle(d, 1.9, dot);
    }
    for (final (i, p) in stops.indexed) {
      if (i == lane) {
        canvas.drawCircle(p, 11, Paint()..color = AppPalette.periwinkle.withValues(alpha: 0.3));
      }
      canvas.drawCircle(p, 6, Paint()..color = AppPalette.textPrimary);
      canvas.drawCircle(p, 3.5, Paint()..color = AppPalette.periwinkle);
    }
    final summit = stops.last;
    canvas.drawLine(
      summit,
      summit - const Offset(0, 26),
      Paint()
        ..color = AppPalette.textPrimary
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(summit.dx + 1, summit.dy - 26)
        ..lineTo(summit.dx + 20, summit.dy - 21)
        ..lineTo(summit.dx + 1, summit.dy - 16)
        ..close(),
      Paint()..color = AppPalette.periwinkle,
    );
  }

  @override
  bool shouldRepaint(_TrailPainter old) => true;
}
