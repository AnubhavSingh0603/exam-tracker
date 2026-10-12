import 'package:flutter/material.dart';

import '../domain/next_step.dart';
import '../domain/urgency.dart';
import '../theme/app_theme.dart';

/// "One Next Step": the only loud thing on the screen, and only as loud as it
/// needs to be (terracotta < 72 h, honey < 14 d, sage otherwise).
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.step, required this.now, required this.onPrimary, this.onMarkApplied});

  final NextStep step;
  final DateTime now;
  final VoidCallback onPrimary;
  final VoidCallback? onMarkApplied;

  @override
  Widget build(BuildContext context) {
    final colors = context.urgencyColors;
    final tone = colors.of(step.urgency);
    final text = Theme.of(context).textTheme;
    final closesWord = step.kind == NextStepKind.apply ? 'Closes' : 'On';

    return Semantics(
      container: true,
      label: 'Next step',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.tint(step.urgency, 0.12),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: tone.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 18, color: tone),
                const SizedBox(width: 8),
                Text('Your one next step', style: text.labelMedium?.copyWith(color: tone)),
              ],
            ),
            const SizedBox(height: 12),
            Text(step.title, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${countdownLabel(step.due, now)} · $closesWord ${formatDue(step.due)}',
              style: text.bodyMedium?.copyWith(color: tone),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(backgroundColor: tone, foregroundColor: AppPalette.background),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(step.actionLabel),
                ),
                if (onMarkApplied != null)
                  OutlinedButton.icon(
                    onPressed: onMarkApplied,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('I applied'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when nothing is pending — reassurance, not emptiness.
class CalmEmptyHero extends StatelessWidget {
  const CalmEmptyHero({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.urgencyColors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.tint(Urgency.safe, 0.10),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          Icon(Icons.spa_rounded, color: colors.safe),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nothing urgent right now. You are on track.', style: text.bodyLarge),
          ),
        ],
      ),
    );
  }
}
