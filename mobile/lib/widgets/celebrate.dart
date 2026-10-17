import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/xp.dart';
import '../providers/xp_providers.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'motion.dart';

// -----------------------------------------------------------------------------
// Confetti
// -----------------------------------------------------------------------------

/// A short burst of confetti over everything (nothing with "Remove animations").
void showConfetti(BuildContext context, {int pieces = 70}) {
  if (motionOff(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Confetti(pieces: pieces, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.pieces, required this.onDone});

  final int pieces;
  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward().whenComplete(widget.onDone);
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    final colors = [AppPalette.periwinkle, AppPalette.sage, AppPalette.honey, AppPalette.terracotta, AppPalette.lavender];
    _pieces = [
      for (var i = 0; i < widget.pieces; i++)
        _Piece(
          x: r.nextDouble(),
          dx: (r.nextDouble() - 0.5) * 0.5,
          up: 0.55 + r.nextDouble() * 0.45,
          spin: (r.nextDouble() - 0.5) * 14,
          size: 6 + r.nextDouble() * 6,
          color: colors[i % colors.length],
          round: r.nextBool(),
        ),
    ];
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value)),
        ),
      );
}

class _Piece {
  _Piece({
    required this.x,
    required this.dx,
    required this.up,
    required this.spin,
    required this.size,
    required this.color,
    required this.round,
  });

  final double x, dx, up, spin, size;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
    for (final p in pieces) {
      // Shot up from the bottom, then falling: a simple arc.
      final rise = p.up * size.height;
      final y = size.height + 20 - rise * (2 * t - t * t) * 1.6 + size.height * 0.35 * t * t;
      final x = (p.x + p.dx * t) * size.width;
      final paint = Paint()..color = p.color.withValues(alpha: fade.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2.4, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
              const Radius.circular(1.5)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// -----------------------------------------------------------------------------
// "+20 XP" pop and the level-up moment
// -----------------------------------------------------------------------------

/// Listens for XP awards anywhere in the app and celebrates them: a "+20 XP" pop
/// (with the streak when it grew), and confetti with a card on a new level.
class XpCelebrations extends ConsumerWidget {
  const XpCelebrations({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<XpAward?>(lastXpAwardProvider, (_, award) {
      if (award == null) return;
      HapticFeedback.selectionClick();
      _showPop(context, award);
      if (award.levelUp) {
        HapticFeedback.mediumImpact();
        showConfetti(context, pieces: 110);
        showDialog<void>(context: context, builder: (_) => _LevelUpDialog(level: award.level));
      }
    });
    return child;
  }
}

OverlayEntry? _pop;

/// One pop at a time: a new award replaces the one still showing.
void _showPop(BuildContext context, XpAward award) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _pop?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _XpPop(
      key: UniqueKey(),
      award: award,
      onDone: () {
        if (identical(_pop, entry)) _pop = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _pop = entry;
  overlay.insert(entry);
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

class _XpPop extends StatefulWidget {
  const _XpPop({super.key, required this.award, required this.onDone});

  final XpAward award;
  final VoidCallback onDone;

  @override
  State<_XpPop> createState() => _XpPopState();
}

class _XpPopState extends State<_XpPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final still = motionOff(context);
    final a = widget.award;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.72),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final v = _c.value;
            final inT = still ? 1.0 : Curves.easeOutBack.transform(math.min(v / 0.25, 1));
            final out = v < 0.8 ? 1.0 : 1 - (v - 0.8) / 0.2;
            return Opacity(
              opacity: out.clamp(0, 1),
              child: Transform.translate(offset: Offset(0, still ? 0 : (1 - inT) * 30 - v * 12), child: child),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.periwinkle,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [BoxShadow(color: AppPalette.periwinkle.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('+${a.gained} XP · ${a.action.label}', style: text.labelLarge?.copyWith(color: Colors.white)),
                  if (a.streakUp && a.streak > 1) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.local_fire_department_rounded, size: 18, color: Colors.white),
                    Text(_days(a.streak), style: text.labelLarge?.copyWith(color: Colors.white)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelUpDialog extends StatelessWidget {
  const _LevelUpDialog({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppPalette.periwinkle, AppPalette.lavender]),
                boxShadow: [BoxShadow(color: AppPalette.periwinkle.withValues(alpha: 0.4), blurRadius: 20)],
              ),
              child: Text('$level', style: text.headlineSmall?.copyWith(color: Colors.white, fontSize: 38)),
            ),
            const SizedBox(height: 16),
            Text('Level up!', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'You’re now ${RegExp('^[AEIOU]').hasMatch(levelName(level)) ? 'an' : 'a'} ${levelName(level)}.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep climbing')),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Header badge, progress sheet, daily ring
// -----------------------------------------------------------------------------

/// ⭐ level and 🔥 streak in the screen header; tap for your progress.
class XpBadge extends ConsumerWidget {
  const XpBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(xpProvider);
    final streak = xp.streakOn(DateTime.now());
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Level ${xp.level}, ${streak == 0 ? 'no streak' : '$streak day streak'}. Your progress.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showXpSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppPalette.periwinkle.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, size: 18, color: AppPalette.periwinkle),
              const SizedBox(width: 2),
              Text('${xp.level}', style: text.labelLarge?.copyWith(color: AppPalette.periwinkle)),
              if (streak > 0) ...[
                const SizedBox(width: 8),
                Icon(Icons.local_fire_department_rounded, size: 18, color: AppPalette.terracotta),
                const SizedBox(width: 1),
                Text('$streak', style: text.labelLarge?.copyWith(color: AppPalette.terracotta)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showXpSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _XpSheet(),
    );

class _XpSheet extends ConsumerWidget {
  const _XpSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(xpProvider);
    final now = DateTime.now();
    final streak = xp.streakOn(now);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Level ${xp.level} · ${xp.levelTitle}', style: text.titleLarge),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: xp.levelProgress.clamp(0, 1)),
                duration: motionOff(context) ? Duration.zero : const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 14,
                  color: AppPalette.periwinkle,
                  backgroundColor: AppPalette.surfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('${xp.xp} XP · ${xp.nextLevelAt - xp.xp} more to Level ${xp.level + 1} (${levelName(xp.level + 1)})',
                style: text.bodySmall),
            const SizedBox(height: 18),
            Row(
              children: [
                DailyRing(done: xp.doneToday(now), size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(streak == 0 ? 'No streak yet' : '${_days(streak)} in a row', style: text.titleMedium),
                      Text(
                        xp.doneToday(now)
                            ? 'Done for today. Nice.'
                            : 'Do one useful thing today to keep it going. Missing one day is fine; it waits for you.',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('How to earn XP', style: text.titleMedium),
            const SizedBox(height: 6),
            for (final a in XpAction.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(a.label, style: text.bodyMedium)),
                    Text('+${a.points}', style: text.labelLarge?.copyWith(color: AppPalette.sage)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text('Opening the app earns nothing: only steps that move your job search forward.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A ring that fills (in mint) once you've done one useful thing today.
class DailyRing extends StatelessWidget {
  const DailyRing({super.key, required this.done, this.size = 64});

  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: done ? 1 : 0),
        duration: motionOff(context) ? Duration.zero : const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: size,
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: size / 8,
                  strokeCap: StrokeCap.round,
                  color: AppPalette.sage,
                  backgroundColor: AppPalette.surfaceVariant,
                ),
              ),
              done
                  ? Icon(Icons.check_rounded, size: size * 0.5, color: AppPalette.sage)
                  : Text('1', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppPalette.textMuted)),
            ],
          ),
        ),
      );
}

/// Today's tile: the daily ring, the streak and the level bar, so progress is in view.
class TodayProgress extends ConsumerWidget {
  const TodayProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(xpProvider);
    final now = DateTime.now();
    final done = xp.doneToday(now);
    final streak = xp.streakOn(now);
    final text = Theme.of(context).textTheme;
    return AppCard(
      accent: done ? AppPalette.sage : AppPalette.periwinkle,
      onTap: () => showXpSheet(context),
      padding: const EdgeInsets.all(14),
      child: Row(
          children: [
            DailyRing(done: done, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(done ? 'Today’s step: done!' : 'Today’s step: one useful thing', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text('Level ${xp.level} · ${xp.levelTitle}', style: text.bodySmall),
                      if (streak > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.local_fire_department_rounded, size: 15, color: AppPalette.terracotta),
                        Text(' ${_days(streak)}', style: text.bodySmall),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: xp.levelProgress.clamp(0, 1),
                      minHeight: 8,
                      color: AppPalette.periwinkle,
                      backgroundColor: AppPalette.surfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }
}
