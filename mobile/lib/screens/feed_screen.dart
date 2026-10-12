import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed.dart';
import '../models/tracked_application.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/system_actions.dart';
import '../widgets/feed_card.dart';

/// Which half of the feed is showing. Direct matches by default, every launch.
class FeedTabNotifier extends Notifier<MatchKind> {
  @override
  MatchKind build() => MatchKind.direct;

  void show(MatchKind kind) => state = kind;
}

final feedTabProvider = NotifierProvider<FeedTabNotifier, MatchKind>(FeedTabNotifier.new);

/// "New for you", split into Direct Matches (degree / Any Graduate / age /
/// experience all met) and 💡 Suggested (up to a year short on experience).
/// Both halves keep the Paralysis Shield: never more than 5 cards.
class SplitFeedSection extends ConsumerWidget {
  const SplitFeedSection({
    super.key,
    required this.markApplied,
    required this.afterApplied,
    required this.excludePostId,
  });

  /// Persists the application; throws on failure.
  final Future<TrackedApplication> Function(FeedItem item) markApplied;
  final void Function(TrackedApplication app) afterApplied;

  /// The hero card already shows this one.
  final String? excludePostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);
    final snapshot = feedAsync.dataOrNull;
    final tab = ref.watch(feedTabProvider);
    final now = ref.watch(nowProvider);

    if (snapshot == null) {
      return _pad(
        feedAsync.hasError
            ? const MutedNote(
                'Can’t reach the server right now. Your tracked applications still work offline.')
            : const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        top: 8,
      );
    }

    final direct = [
      for (final i in ref.watch(visibleFeedProvider))
        if (i.bestPost.postDetailId != excludePostId) i,
    ];
    final suggested = ref.watch(visibleSuggestedProvider);
    final items = tab == MatchKind.direct ? direct : suggested;
    final hidden = tab == MatchKind.direct ? snapshot.hiddenCount : snapshot.suggestedHiddenCount;

    return SliverMainAxisGroup(
      slivers: [
        _pad(
          _FeedTabs(
            tab: tab,
            directCount: direct.length,
            suggestedCount: suggested.length,
            onChanged: ref.read(feedTabProvider.notifier).show,
          ),
          top: 12,
        ),
        if (items.isEmpty)
          _pad(
            MutedNote(tab == MatchKind.direct
                ? 'No other new jobs. Nice and quiet.'
                : 'No near-misses right now. Suggestions appear when a job needs a little more experience than you have.'),
            top: 12,
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _SwipeToApply(
                item: items[i],
                now: now,
                category: snapshot.category,
                markApplied: markApplied,
                afterApplied: afterApplied,
              ),
            ),
          ),
        if (hidden > 0)
          _pad(MutedNote('+$hidden more waiting. Finish these first — they’ll appear here.'), top: 12),
      ],
    );
  }
}

class _FeedTabs extends StatelessWidget {
  const _FeedTabs({
    required this.tab,
    required this.directCount,
    required this.suggestedCount,
    required this.onChanged,
  });

  final MatchKind tab;
  final int directCount;
  final int suggestedCount;
  final ValueChanged<MatchKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final honey = context.urgencyColors.warning;
    return SegmentedButton<MatchKind>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppPalette.surfaceVariant,
        selectedForegroundColor: AppPalette.textPrimary,
        foregroundColor: AppPalette.textMuted,
        side: const BorderSide(color: AppPalette.outline),
      ),
      segments: [
        ButtonSegment(value: MatchKind.direct, label: Text('Direct matches ($directCount)')),
        ButtonSegment(
          value: MatchKind.suggested,
          label: Text('💡 Suggested ($suggestedCount)',
              style: TextStyle(color: tab == MatchKind.suggested ? honey : null)),
        ),
      ],
      selected: {tab},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Swipe right → Applied. Persists *before* the card animates away so it is
/// already gone from the provider when Dismissible finishes.
class _SwipeToApply extends StatefulWidget {
  const _SwipeToApply({
    required this.item,
    required this.now,
    required this.category,
    required this.markApplied,
    required this.afterApplied,
  });

  final FeedItem item;
  final DateTime now;
  final String? category;
  final Future<TrackedApplication> Function(FeedItem item) markApplied;
  final void Function(TrackedApplication app) afterApplied;

  @override
  State<_SwipeToApply> createState() => _SwipeToApplyState();
}

class _SwipeToApplyState extends State<_SwipeToApply> {
  TrackedApplication? _applied;

  @override
  Widget build(BuildContext context) {
    final sage = context.urgencyColors.safe;
    final item = widget.item;
    return Dismissible(
      key: ValueKey('feed-${item.bestPost.postDetailId}'),
      direction: DismissDirection.startToEnd,
      background: SwipeBackground(color: sage, icon: Icons.check_circle_rounded, label: 'Applied'),
      confirmDismiss: (_) async {
        try {
          _applied = await widget.markApplied(item);
          return true;
        } catch (_) {
          if (context.mounted) showCalmSnack(context, 'Could not save. Try again.');
          return false;
        }
      },
      onDismissed: (_) {
        final app = _applied;
        if (app != null) widget.afterApplied(app);
      },
      child: FeedCard(
        item: item,
        now: widget.now,
        category: widget.category,
        onOpenPortal: () => unawaited(openExternal(context, item.portalUrl)),
      ),
    );
  }
}

Widget _pad(Widget child, {double top = 0}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 0),
      sliver: SliverToBoxAdapter(child: child),
    );

class MutedNote extends StatelessWidget {
  const MutedNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.textMuted));
}

class SwipeBackground extends StatelessWidget {
  const SwipeBackground({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    this.alignEnd = false,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: color),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignEnd ? children.reversed.toList() : children,
      ),
    );
  }
}
