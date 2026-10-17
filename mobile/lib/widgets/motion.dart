import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'celebrate.dart';

/// Small, slow motion that only marks a change. Everything here is skipped when
/// the phone's "Remove animations" is on.
bool motionOff(BuildContext context) => MediaQuery.of(context).disableAnimations;

// -----------------------------------------------------------------------------
// 1 · Cards settle: new cards rise into place, one after another
// -----------------------------------------------------------------------------

/// Fades and lifts [child] in the first time [id] is shown this session
/// (scrolling back to a card doesn't replay it).
class SettleIn extends StatefulWidget {
  const SettleIn({super.key, required this.id, required this.index, required this.child});

  final String id;
  final int index;
  final Widget child;

  static final _seen = <String>{};

  @override
  State<SettleIn> createState() => _SettleInState();
}

class _SettleInState extends State<SettleIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final bool _play = !SettleIn._seen.contains(widget.id);

  @override
  void initState() {
    super.initState();
    SettleIn._seen.add(widget.id);
    if (!_play) {
      _c.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: 70 * math.min(widget.index, 6)), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_play || motionOff(context)) return widget.child;
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(offset: Offset(0, 18 * (1 - t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

// -----------------------------------------------------------------------------
// 2 · Applied ✓: a ring closes and a tick draws
// -----------------------------------------------------------------------------

/// A short celebration in the middle of the screen after a swipe right.
void showAppliedCelebration(BuildContext context) {
  if (motionOff(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _AppliedTick(onDone: () => entry.remove()));
  overlay.insert(entry);
  showConfetti(context);
}

class _AppliedTick extends StatefulWidget {
  const _AppliedTick({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_AppliedTick> createState() => _AppliedTickState();
}

class _AppliedTickState extends State<_AppliedTick> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final v = _c.value;
              final fade = v < 0.75 ? 1.0 : 1 - (v - 0.75) / 0.25;
              return Opacity(
                opacity: fade.clamp(0, 1),
                child: Transform.scale(
                  scale: 0.85 + 0.15 * Curves.easeOutBack.transform(math.min(v / 0.4, 1)),
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: AppPalette.surface.withValues(alpha: 0.94),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24)],
                    ),
                    child: CustomPaint(painter: _TickPainter(v, AppPalette.sage, AppPalette.textPrimary)),
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t, this.ring, this.tick);

  final double t;
  final Color ring;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width * 0.32;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, r, stroke..color = ring.withValues(alpha: 0.25));
    final ringT = Curves.easeOutCubic.transform(math.min(t / 0.5, 1));
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, 2 * math.pi * ringT, false,
        stroke..color = ring);
    final tickT = Curves.easeOut.transform(((t - 0.3) / 0.35).clamp(0, 1));
    if (tickT <= 0) return;
    final a = center + Offset(-r * 0.42, r * 0.02);
    final b = center + Offset(-r * 0.1, r * 0.34);
    final c = center + Offset(r * 0.46, -r * 0.3);
    final path = Path()..moveTo(a.dx, a.dy);
    final first = (b - a).distance;
    final total = first + (c - b).distance;
    final drawn = total * tickT;
    if (drawn <= first) {
      final p = Offset.lerp(a, b, drawn / first)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = Offset.lerp(b, c, (drawn - first) / (total - first))!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = tick);
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t;
}

// -----------------------------------------------------------------------------
// 3 · Last-day glow: only countdowns under 24 hours breathe
// -----------------------------------------------------------------------------

class LastDayGlow extends StatefulWidget {
  const LastDayGlow({super.key, required this.active, required this.color, required this.child});

  final bool active;
  final Color color;
  final Widget child;

  @override
  State<LastDayGlow> createState() => _LastDayGlowState();
}

class _LastDayGlowState extends State<LastDayGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.active && !motionOff(context);
    if (on && !_c.isAnimating) _c.repeat();
    if (!on) {
      _c.stop();
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final wave = math.sin(_c.value * math.pi); // 0 → 1 → 0
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(color: widget.color.withValues(alpha: 0.35 * (1 - wave)), spreadRadius: 8 * wave),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// -----------------------------------------------------------------------------
// 4 · Gentle hints: the first card nudges once to teach the swipe
// -----------------------------------------------------------------------------

class SwipeNudge extends StatefulWidget {
  const SwipeNudge({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  static bool _shown = false; // once per app session

  @override
  State<SwipeNudge> createState() => _SwipeNudgeState();
}

class _SwipeNudgeState extends State<SwipeNudge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.enabled && !SwipeNudge._shown) {
      SwipeNudge._shown = true;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && !motionOff(context)) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final v = _c.value;
          final dx = v == 0 ? 0.0 : 28 * math.sin(v * math.pi) * (1 - v * 0.3);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: widget.child,
      );
}

/// Tabs: the new tab fades in, sliding a little from the side you moved towards.
class TabSwitcher extends StatefulWidget {
  const TabSwitcher({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<TabSwitcher> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..value = 1;
  int _from = 0;

  @override
  void didUpdateWidget(TabSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(index: widget.index, children: widget.children);
    if (motionOff(context)) return stack;
    final direction = widget.index >= _from ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: 0.3 + 0.7 * t,
          child: Transform.translate(offset: Offset(16 * direction * (1 - t), 0), child: child),
        );
      },
      child: stack,
    );
  }
}
