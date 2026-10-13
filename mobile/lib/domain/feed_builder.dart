/// Builds the feed on the phone from jobs.json + the local profile: a port of
/// backend/app/services/feed.py. Strict deadline order, direct matches and
/// 💡 suggestions in separate lists, each capped by the Paralysis Shield.
library;

import '../models/feed.dart';
import '../models/jobs_data.dart';
import '../models/user_profile.dart';
import 'eligibility.dart';
import 'urgency.dart';

const kFeedMaxItems = 5;

FeedPost _feedPost(PublishedPost post, EligibilityResult r) => FeedPost(
      postDetailId: post.id,
      postCode: post.postCode,
      postName: post.postName,
      categoryQuotaSeats: r.categoryQuotaSeats,
      urOpenSeats: r.urOpenSeats,
      totalReachableSeats: r.totalReachableSeats,
      eligibleViaRelaxation: r.eligibleViaRelaxation,
      notes: r.reasons,
      matchKind: r.kind == EligibilityKind.suggested ? MatchKind.suggested : MatchKind.direct,
      matchReasonLabel: r.matchReason?.label,
      suggestionReasons: r.kind == EligibilityKind.suggested ? const ['experience_gap'] : const [],
    );

FeedItem _feedItem(PublishedJob job, List<FeedPost> posts, MatchKind kind) {
  posts.sort((a, b) => b.totalReachableSeats.compareTo(a.totalReachableSeats));
  final best = posts.first;
  final deadline = job.applicationDeadline!;
  final verb = kind == MatchKind.direct ? 'Apply for' : 'Check if you fit';
  return FeedItem(
    jobPostId: job.id,
    organization: job.organization,
    examName: job.examName,
    portalUrl: job.portalUrl,
    deadline: deadline,
    urgency: urgencyFor(deadline, DateTime.now()),
    nextStep: '$verb ${best.postName} (${job.organization}) — closes ${formatDue(deadline)}',
    bestPost: best,
    matchKind: kind,
    timelineJson: job.timelineJson,
  );
}

/// [appliedPostIds]: posts already tracked on this phone (never shown again).
FeedSnapshot buildFeed({
  required JobsFile jobs,
  required UserProfileData profile,
  required Set<String> appliedPostIds,
  required DateTime now,
  required DateTime fetchedAt,
  bool fromCache = false,
  bool strictUrMigration = true,
}) {
  final open = [
    for (final j in jobs.jobs)
      if (j.applicationDeadline != null && j.applicationDeadline!.isAfter(now)) j,
  ]..sort((a, b) {
      final byDeadline = a.applicationDeadline!.compareTo(b.applicationDeadline!);
      return byDeadline != 0 ? byDeadline : a.id.compareTo(b.id);
    });

  final direct = <FeedItem>[];
  final suggested = <FeedItem>[];
  for (final job in open) {
    final directPosts = <FeedPost>[];
    final suggestedPosts = <FeedPost>[];
    for (final post in job.posts) {
      if (appliedPostIds.contains(post.id)) continue;
      final EligibilityResult r;
      try {
        r = evaluateEligibility(profile, post, strictUrMigration: strictUrMigration);
      } on ArgumentError {
        continue; // DOB after the cut-off: corrupt data, never eligible
      }
      switch (r.kind) {
        case EligibilityKind.direct:
          directPosts.add(_feedPost(post, r));
        case EligibilityKind.suggested:
          suggestedPosts.add(_feedPost(post, r));
        case null:
          break;
      }
    }
    // A job you directly qualify for is never also listed as a suggestion.
    if (directPosts.isNotEmpty) {
      direct.add(_feedItem(job, directPosts, MatchKind.direct));
    } else if (suggestedPosts.isNotEmpty) {
      suggested.add(_feedItem(job, suggestedPosts, MatchKind.suggested));
    }
  }

  return FeedSnapshot(
    items: direct.take(kFeedMaxItems).toList(growable: false),
    hiddenCount: direct.length > kFeedMaxItems ? direct.length - kFeedMaxItems : 0,
    suggested: suggested.take(kFeedMaxItems).toList(growable: false),
    suggestedHiddenCount: suggested.length > kFeedMaxItems ? suggested.length - kFeedMaxItems : 0,
    category: profile.category.wire,
    fetchedAt: fetchedAt,
    fromCache: fromCache,
  );
}
