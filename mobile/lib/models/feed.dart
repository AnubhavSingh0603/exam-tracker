import 'package:flutter/foundation.dart';

import '../domain/urgency.dart';

/// Mirrors backend `app/schemas/feed.py`. Unknown fields are ignored.
@immutable
class FeedPost {
  const FeedPost({
    required this.postDetailId,
    required this.postName,
    required this.categoryQuotaSeats,
    required this.urOpenSeats,
    required this.totalReachableSeats,
    required this.eligibleViaRelaxation,
    required this.notes,
    this.postCode,
  });

  final String postDetailId;
  final String? postCode;
  final String postName;
  final int categoryQuotaSeats;
  final int urOpenSeats;
  final int totalReachableSeats;
  final bool eligibleViaRelaxation;
  final List<String> notes;

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        postDetailId: j['post_detail_id'] as String,
        postCode: j['post_code'] as String?,
        postName: j['post_name'] as String,
        categoryQuotaSeats: (j['category_quota_seats'] as num?)?.toInt() ?? 0,
        urOpenSeats: (j['ur_open_seats'] as num?)?.toInt() ?? 0,
        totalReachableSeats: (j['total_reachable_seats'] as num?)?.toInt() ?? 0,
        eligibleViaRelaxation: j['eligible_via_relaxation'] as bool? ?? false,
        notes: [for (final n in (j['notes'] as List<dynamic>? ?? const [])) n.toString()],
      );
}

@immutable
class FeedItem {
  const FeedItem({
    required this.jobPostId,
    required this.organization,
    required this.examName,
    required this.deadline,
    required this.urgency,
    required this.nextStep,
    required this.bestPost,
    this.portalUrl,
  });

  final String jobPostId;
  final String organization;
  final String examName;
  final String? portalUrl;
  final DateTime deadline;
  final Urgency urgency;
  final String nextStep;
  final FeedPost bestPost;

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        jobPostId: j['job_post_id'] as String,
        organization: j['organization'] as String,
        examName: j['exam_name'] as String,
        portalUrl: j['portal_url'] as String?,
        deadline: DateTime.parse(j['application_deadline'] as String),
        urgency: urgencyFromWire(j['urgency'] as String?),
        nextStep: j['next_step'] as String? ?? '',
        bestPost: FeedPost.fromJson(j['best_post'] as Map<String, dynamic>),
      );
}

@immutable
class FeedSnapshot {
  const FeedSnapshot({
    required this.items,
    required this.hiddenCount,
    required this.fetchedAt,
    this.category,
    this.fromCache = false,
  });

  static final empty = FeedSnapshot(items: const [], hiddenCount: 0, fetchedAt: DateTime(1970));

  /// hero first, then up_next — already deadline-sorted by the backend.
  final List<FeedItem> items;
  final int hiddenCount;
  final String? category;
  final DateTime fetchedAt;
  final bool fromCache;

  factory FeedSnapshot.fromJson(Map<String, dynamic> j, {required DateTime fetchedAt, bool fromCache = false}) {
    final hero = j['hero'];
    return FeedSnapshot(
      items: [
        if (hero is Map<String, dynamic>) FeedItem.fromJson(hero),
        for (final i in (j['up_next'] as List<dynamic>? ?? const [])) FeedItem.fromJson(i as Map<String, dynamic>),
      ],
      hiddenCount: (j['hidden_count'] as num?)?.toInt() ?? 0,
      category: j['category'] as String?,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
    );
  }
}
