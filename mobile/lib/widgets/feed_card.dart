import 'package:flutter/material.dart';

import '../models/feed.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'pills.dart';

/// Unapplied job. Swipe right → Applied (handled by the parent Dismissible).
class FeedCard extends StatelessWidget {
  const FeedCard({super.key, required this.item, required this.now, this.category, this.onOpenPortal});

  final FeedItem item;
  final DateTime now;
  final String? category;
  final VoidCallback? onOpenPortal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final post = item.bestPost;
    return AppCard(
      accent: context.urgencyColors.of(item.urgency),
      onTap: onOpenPortal,
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
              if (post.eligibleViaRelaxation) const StatusPill(label: 'Via age relaxation'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.swipe_right_rounded, size: 16, color: AppPalette.textMuted),
              const SizedBox(width: 6),
              Text('Swipe right once you have applied', style: text.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
