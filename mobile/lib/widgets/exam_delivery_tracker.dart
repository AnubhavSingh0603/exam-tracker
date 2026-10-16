import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../domain/delivery_track.dart';
import '../domain/lifecycle.dart';
import '../models/tracked_application.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import 'app_icons.dart';
import 'motion.dart';

/// A parcel-tracker view of an exam: stops along a rail, a runner that travels
/// the finished part and halts at the current stop, and a card under the stop
/// with one plain sentence and one action. Tap any stop to see its details.
class ExamDeliveryTracker extends StatefulWidget {
  const ExamDeliveryTracker({super.key, required this.app, required this.now, this.onTrackNextTier});

  final TrackedApplication app;
  final DateTime now;

  /// "Track Tier-2" on the last stop.
  final VoidCallback? onTrackNextTier;

  static Color colorOf(StageState s) => switch (s) {
        StageState.completed => AppPalette.sage,
        StageState.active => AppPalette.terracotta,
        StageState.upcoming => AppPalette.honey,
        StageState.locked => AppPalette.textMuted,
      };

  @override
  State<ExamDeliveryTracker> createState() => _ExamDeliveryTrackerState();
}

class _ExamDeliveryTrackerState extends State<ExamDeliveryTracker> with TickerProviderStateMixin {
  late final _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late DeliveryTrack _track = buildDeliveryTrack(widget.app, widget.now);

  /// Runner position in stops (0 = Applied), animated from [_from] to the active stop.
  double _from = 0;
  int? _selected; // null = the active stop

  @override
  void initState() {
    super.initState();
    _run.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && !_track.finished && !motionOff(context)) {
        _pulse.repeat();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_run.isDismissed) _start();
  }

  @override
  void didUpdateWidget(ExamDeliveryTracker old) {
    super.didUpdateWidget(old);
    final before = _track.activeIndex;
    _track = buildDeliveryTrack(widget.app, widget.now);
    if (_selected != null && _selected! >= _track.stops.length) _selected = null;
    if (_track.activeIndex != before) {
      _from = before.toDouble();
      _start();
    }
  }

  void _start() {
    _pulse.stop();
    if (motionOff(context)) {
      _run.value = 1;
      return;
    }
    _run.forward(from: 0);
  }

  @override
  void dispose() {
    _run.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _act(StageAction action, TrackStop stop) {
    if (stop.isNextTier) {
      widget.onTrackNextTier?.call();
    } else {
      openExternal(context, action.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = _track.stops;
    final selected = _selected ?? _track.activeIndex;
    return LayoutBuilder(builder: (context, box) {
      const edge = 28.0; // half a label's width, so end labels fit
      final step = (box.maxWidth - 2 * edge) / (stops.length - 1);
      double xOf(double stop) => edge + stop * step;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 86,
            child: AnimatedBuilder(
              animation: Listenable.merge([_run, _pulse]),
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_run.value);
                final at = lerpDouble(_from, _track.activeIndex.toDouble(), t)!;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RailPainter(
                          from: xOf(0),
                          progress: xOf(at),
                          to: xOf(stops.length - 1.0),
                          done: AppPalette.sage,
                          ahead: AppPalette.textMuted,
                        ),
                      ),
                    ),
                    for (var i = 0; i < stops.length; i++)
                      Positioned(
                        left: xOf(i.toDouble()) - step.clamp(48, 72) / 2,
                        width: step.clamp(48, 72),
                        top: 0,
                        bottom: 0,
                        child: _StopNode(
                          stop: stops[i],
                          // The runner covers the active stop once it arrives.
                          hidden: i == _track.activeIndex && !_track.finished,
                          reached: at >= i - 0.05,
                          selected: i == selected,
                          onTap: () => setState(() => _selected = i == _track.activeIndex ? null : i),
                        ),
                      ),
                    if (!_track.finished)
                      Positioned(
                        left: xOf(at) - 17,
                        top: _rail - 17,
                        child: IgnorePointer(
                          child: _Runner(
                            pulse: _run.isCompleted ? _pulse.value : null,
                            color: ExamDeliveryTracker.colorOf(stops[_track.activeIndex].state),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _StopCard(
            track: _track,
            index: selected,
            pointerX: xOf(selected.toDouble()),
            onAction: _act,
          ),
        ],
      );
    });
  }
}

const _rail = 20.0; // the rail's y inside the track

class _RailPainter extends CustomPainter {
  _RailPainter({required this.from, required this.progress, required this.to, required this.done, required this.ahead});

  final double from;
  final double progress;
  final double to;
  final Color done;
  final Color ahead;

  @override
  void paint(Canvas canvas, Size size) {
    // Ahead: dashed slate.
    final dash = Paint()
      ..color = ahead.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = progress + 6; x < to; x += 9) {
      canvas.drawLine(Offset(x, _rail), Offset(math.min(x + 4, to), _rail), dash);
    }
    // Done: solid sage, grows with the runner.
    if (progress > from) {
      canvas.drawLine(
        Offset(from, _rail),
        Offset(progress, _rail),
        Paint()
          ..color = done
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.progress != progress || old.from != from || old.to != to || old.done != done || old.ahead != ahead;
}

class _StopNode extends StatelessWidget {
  const _StopNode({
    required this.stop,
    required this.hidden,
    required this.reached,
    required this.selected,
    required this.onTap,
  });

  final TrackStop stop;
  final bool hidden;
  final bool reached;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // A completed stop turns sage only when the runner has passed it.
    final state = stop.state == StageState.completed && !reached ? StageState.upcoming : stop.state;
    final color = ExamDeliveryTracker.colorOf(state);
    final filled = state == StageState.completed;
    final stateWord = switch (stop.state) {
      StageState.completed => 'done',
      StageState.active => 'now',
      StageState.upcoming => 'next',
      StageState.locked => 'not announced yet',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '${stop.label}, $stateWord',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Column(
          children: [
            SizedBox(
              height: 2 * _rail,
              child: Center(
                child: Opacity(
                  opacity: hidden ? 0 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 22 : 18,
                    height: selected ? 22 : 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? color : AppPalette.surface,
                      border: Border.all(color: color, width: selected ? 3 : 2),
                    ),
                    child: filled ? Icon(Icons.check_rounded, size: 12, color: AppPalette.background) : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stop.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: stop.state == StageState.locked ? AppPalette.textMuted : AppPalette.textPrimary,
                fontWeight: stop.state == StageState.active || selected ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The marker at the current stop: a small runner in a disc, with a soft ring
/// that breathes once it has arrived.
class _Runner extends StatelessWidget {
  const _Runner({required this.pulse, required this.color});

  final double? pulse;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = pulse;
    return SizedBox.square(
      dimension: 34,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (p != null)
            Container(
              width: 30 + 16 * p,
              height: 30 + 16 * p,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.28 * (1 - p)),
              ),
            ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Icon(Icons.directions_run_rounded, size: 19, color: AppPalette.background),
          ),
        ],
      ),
    );
  }
}

/// Under the track: the current stop's one sentence and one action, or the
/// tapped stop's dates, details and links. A small pointer marks the stop.
class _StopCard extends StatelessWidget {
  const _StopCard({required this.track, required this.index, required this.pointerX, required this.onAction});

  final DeliveryTrack track;
  final int index;
  final double pointerX;
  final void Function(StageAction, TrackStop) onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stop = track.stops[index];
    final isCurrent = index == track.activeIndex;
    final color = ExamDeliveryTracker.colorOf(stop.state);
    final date = stop.date;

    final StageAction? main = isCurrent
        ? track.action
        : stop.actions.where((a) => a.primary).firstOrNull ?? stop.actions.firstOrNull;
    final others = [
      for (final a in stop.actions)
        if (a != main) a
    ];

    final title = isCurrent
        ? track.headline
        : switch (stop.state) {
            StageState.completed => '${stop.label}: done',
            StageState.locked => '${stop.label}: not announced yet',
            _ => stop.label,
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 8,
          child: CustomPaint(painter: _PointerPainter(x: pointerX, color: color.withValues(alpha: 0.12))),
        ),
        AnimatedSwitcher(
          duration: motionOff(context) ? Duration.zero : const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey(index),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(liveRegion: isCurrent, child: Text(title, style: text.titleSmall)),
                if (date != null && !isCurrent) ...[
                  const SizedBox(height: 2),
                  Text(stageDateLabel(date, stop.dateEnd), style: text.labelMedium?.copyWith(color: color)),
                ],
                for (final d in stop.details) ...[
                  const SizedBox(height: 2),
                  Text(d, style: text.bodySmall),
                ],
                if (main != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () => onAction(main, stop),
                    icon: DuoIcon(
                        stop.isNextTier
                            ? AppIcon.addExam
                            : main.label.startsWith('Download')
                                ? AppIcon.download
                                : AppIcon.applyOnline,
                        size: 18),
                    label: Text(main.label),
                  ),
                ],
                if (others.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final a in others) TextButton(onPressed: () => onAction(a, stop), child: Text(a.label)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  _PointerPainter({required this.x, required this.color});

  final double x;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(x - 8, size.height)
        ..lineTo(x, 0)
        ..lineTo(x + 8, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.x != x || old.color != color;
}
