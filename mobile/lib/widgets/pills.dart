import 'package:flutter/material.dart';

import '../domain/urgency.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'motion.dart';

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label, required this.foreground, required this.background, this.icon, this.semantics});

  final String label;
  final Color foreground;
  final Color background;
  final Object? icon;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground);
    return Semantics(
      label: semantics ?? label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final i?) ...[glyph(i, size: 14, color: foreground), const SizedBox(width: 4)],
            Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// "18 hrs left" tinted by urgency band.
class CountdownPill extends StatelessWidget {
  const CountdownPill({super.key, required this.due, required this.now, this.label});

  final DateTime? due;
  final DateTime now;

  /// Instead of the countdown ("Starts 12 Oct"); colour and glow still follow [due].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.urgencyColors;
    final d = due;
    final urgency = urgencyFor(d, now);
    final label = this.label ?? (d == null ? 'No date yet' : countdownLabel(d, now));
    // Only the last 24 hours breathe; nothing else on screen moves by itself.
    final lastDay = d != null && d.isAfter(now) && d.difference(now) <= const Duration(hours: 24);
    return LastDayGlow(
      active: lastDay,
      color: colors.of(urgency),
      child: _Pill(
        label: label,
        icon: AppIcon.reminder,
        foreground: colors.of(urgency),
        background: colors.tint(urgency),
        semantics: d == null ? label : '$label, due ${formatDue(d)}',
      ),
    );
  }
}

/// "🎯 26 Seats (20 UR + 6 SC)".
class SeatPill extends StatelessWidget {
  const SeatPill({super.key, required this.total, required this.ur, required this.quota, this.category});

  final int total;
  final int ur;
  final int quota;
  final String? category;

  String get label {
    final cat = category ?? 'Quota';
    if (cat == 'UR') return '🎯 $total Seats ($ur UR)';
    return '🎯 $total Seats ($ur UR + $quota $cat)';
  }

  @override
  Widget build(BuildContext context) {
    final info = context.urgencyColors.info;
    return _Pill(
      label: label,
      foreground: info,
      background: info.withValues(alpha: 0.12),
      semantics: '$total reachable seats: $ur open, $quota ${category ?? 'reserved'}',
    );
  }
}

/// Small tinted tag in one of the palette colours ("💡 Suggested: Experience Gap").
class TonePill extends StatelessWidget {
  const TonePill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      _Pill(label: label, foreground: color, background: color.withValues(alpha: 0.12));
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => _Pill(
        label: label,
        foreground: AppPalette.textMuted,
        background: AppPalette.surfaceVariant,
      );
}
