import 'package:flutter/material.dart';

import '../models/feed.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'pills.dart';

/// Unapplied job. Swipe right → Applied (handled by the parent Dismissible).
class FeedCard extends StatelessWidget {
  const FeedCard({super.key, required this.item, required this.now, this.category, this.onApply});

  final FeedItem item;
  final DateTime now;
  final String? category;

  /// Opens the application form (or the official website when the form isn't known).
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final post = item.bestPost;
    return AppCard(
      accent: context.urgencyColors.of(item.urgency),
      onTap: onApply,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(post.postName, style: text.titleMedium)),
              const SizedBox(width: 8),
              CountdownPill(due: item.deadline, now: now),
            ],
          ),
          const SizedBox(height: 4),
          Text('${item.organization} · ${item.examName}', style: text.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SeatPill(
                total: post.totalReachableSeats,
                ur: post.urOpenSeats,
                quota: post.categoryQuotaSeats,
                category: category,
              ),
              if (post.matchKind == MatchKind.suggested)
                TonePill(label: suggestionBadge(post.suggestionReasons), color: context.urgencyColors.warning)
              else if (post.matchReasonLabel != null)
                StatusPill(label: post.matchReasonLabel!),
              if (post.eligibleViaRelaxation) const StatusPill(label: 'Via age relaxation'),
            ],
          ),
          // Why it's only a suggestion, e.g. "Needs 2 yr experience; you have 1.5."
          for (final note in post.notes)
            if (post.matchKind == MatchKind.suggested && note.contains('experience')) ...[
              const SizedBox(height: 8),
              Text(note, style: text.bodySmall),
            ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (onApply != null) ...[
                FilledButton.tonalIcon(
                  onPressed: onApply,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Apply online'),
                ),
                const SizedBox(width: 12),
              ],
              const Icon(Icons.swipe_right_rounded, size: 16, color: AppPalette.textMuted),
              const SizedBox(width: 6),
              Flexible(child: Text('Swipe right once you have applied', style: text.labelSmall)),
            ],
          ),
        ],
      ),
    );
  }
}
