import 'package:flutter/foundation.dart';

import '../domain/urgency.dart';
import 'jobs_data.dart';
import 'links.dart';

/// Backend `MatchKind`: direct matches fill the main feed, suggestions their own tab.
enum MatchKind {
  direct,
  suggested;

  static MatchKind fromWire(Object? v) => v == 'suggested' ? suggested : direct;
}

/// Pastel badge text for a suggested post ("💡 Suggested: Experience Gap").
String suggestionBadge(List<String> reasons) => switch (reasons.firstOrNull) {
      'experience_gap' => '💡 Suggested: Experience Gap',
      _ => '💡 Suggested',
    };

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
    this.matchKind = MatchKind.direct,
    this.matchReasonLabel,
    this.suggestionReasons = const [],
  });

  final String postDetailId;
  final String? postCode;
  final String postName;
  final int categoryQuotaSeats;
  final int urOpenSeats;
  final int totalReachableSeats;
  final bool eligibleViaRelaxation;
  final List<String> notes;
  final MatchKind matchKind;

  /// "Direct Degree Match", "Universal Graduate Post", "Custom Qualification Match"…
  final String? matchReasonLabel;
  final List<String> suggestionReasons;

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        postDetailId: j['post_detail_id'] as String,
        postCode: j['post_code'] as String?,
        postName: j['post_name'] as String,
        categoryQuotaSeats: (j['category_quota_seats'] as num?)?.toInt() ?? 0,
        urOpenSeats: (j['ur_open_seats'] as num?)?.toInt() ?? 0,
        totalReachableSeats: (j['total_reachable_seats'] as num?)?.toInt() ?? 0,
        eligibleViaRelaxation: j['eligible_via_relaxation'] as bool? ?? false,
        notes: [for (final n in (j['notes'] as List<dynamic>? ?? const [])) n.toString()],
        matchKind: MatchKind.fromWire(j['match_kind']),
        matchReasonLabel: j['match_reason_label'] as String?,
        suggestionReasons: [
          for (final r in (j['suggestion_reasons'] as List<dynamic>? ?? const [])) r.toString()
        ],
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
    this.applyUrl,
    this.matchKind = MatchKind.direct,
    this.timelineJson,
    this.job,
    this.posts = const [],
  });

  final String jobPostId;
  final String organization;
  final String examName;
  final String? portalUrl;

  /// The registration / application page itself, when a job site links it.
  final String? applyUrl;

  /// Where "Apply online" goes: the application page, else the official website.
  String? get applicationUrl => preferredUrl(applyUrl, portalUrl);
  final DateTime deadline;
  final Urgency urgency;
  final String nextStep;
  final FeedPost bestPost;
  final MatchKind matchKind;

  /// Raw `timeline` object, stored as-is when the user marks the job Applied.
  final Map<String, dynamic>? timelineJson;

  /// The whole notification, for the expanded details (null for old cached feeds).
  final PublishedJob? job;

  /// Every post of [job] you qualify for, most seats first ([bestPost] is the first).
  final List<FeedPost> posts;

  /// The same job showing only [kept] (a subset of [posts]); the headline post is
  /// re-picked from them, most seats you can reach first.
  FeedItem withPosts(List<FeedPost> kept) {
    final best = kept.contains(bestPost)
        ? bestPost
        : (kept.toList()..sort((a, b) => b.totalReachableSeats.compareTo(a.totalReachableSeats))).first;
    return FeedItem(
      jobPostId: jobPostId,
      organization: organization,
      examName: examName,
      deadline: deadline,
      urgency: urgency,
      nextStep: nextStep,
      bestPost: best,
      portalUrl: portalUrl,
      applyUrl: applyUrl,
      matchKind: matchKind,
      timelineJson: timelineJson,
      job: job,
      posts: kept,
    );
  }

  /// The published post behind [bestPost].
  PublishedPost? get bestPublishedPost {
    for (final p in job?.posts ?? const <PublishedPost>[]) {
      if (p.id == bestPost.postDetailId) return p;
    }
    return null;
  }

  String get category => job?.category ?? 'other';

  /// Highest entry pay among the posts you qualify for.
  int? get monthlyPay {
    final ids = {
      for (final p in posts.isEmpty ? [bestPost] : posts) p.postDetailId
    };
    int? best;
    for (final p in job?.posts ?? const <PublishedPost>[]) {
      final pay = p.monthlyPayMin;
      if (ids.contains(p.id) && pay != null && (best == null || pay > best)) best = pay;
    }
    return best;
  }

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        jobPostId: j['job_post_id'] as String,
        organization: j['organization'] as String,
        examName: j['exam_name'] as String,
        portalUrl: j['portal_url'] as String?,
        applyUrl: j['apply_url'] as String?,
        deadline: DateTime.parse(j['application_deadline'] as String),
        urgency: urgencyFromWire(j['urgency'] as String?),
        nextStep: j['next_step'] as String? ?? '',
        bestPost: FeedPost.fromJson(j['best_post'] as Map<String, dynamic>),
        matchKind: MatchKind.fromWire(j['match_kind']),
        timelineJson: j['timeline'] as Map<String, dynamic>?,
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
    this.suggested = const [],
    this.suggestedHiddenCount = 0,
  });

  static final empty = FeedSnapshot(items: const [], hiddenCount: 0, fetchedAt: DateTime(1970));

  /// hero first, then up_next — already deadline-sorted by the backend.
  final List<FeedItem> items;
  final int hiddenCount;
  final String? category;
  final DateTime fetchedAt;
  final bool fromCache;

  /// "💡 Suggested" tab, deadline-sorted, already capped by the backend.
  final List<FeedItem> suggested;
  final int suggestedHiddenCount;

  factory FeedSnapshot.fromJson(Map<String, dynamic> j,
      {required DateTime fetchedAt, bool fromCache = false}) {
    final hero = j['hero'];
    return FeedSnapshot(
      items: [
        if (hero is Map<String, dynamic>) FeedItem.fromJson(hero),
        for (final i in (j['up_next'] as List<dynamic>? ?? const []))
          FeedItem.fromJson(i as Map<String, dynamic>),
      ],
      hiddenCount: (j['hidden_count'] as num?)?.toInt() ?? 0,
      category: j['category'] as String?,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
      suggested: [
        for (final i in (j['suggested'] as List<dynamic>? ?? const []))
          FeedItem.fromJson(i as Map<String, dynamic>),
      ],
      suggestedHiddenCount: (j['suggested_hidden_count'] as num?)?.toInt() ?? 0,
    );
  }
}
