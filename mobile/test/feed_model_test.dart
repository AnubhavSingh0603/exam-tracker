import 'package:exam_tracker/models/feed.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item(String id, {String kind = 'direct', List<String> reasons = const []}) => {
      'job_post_id': 'job-$id',
      'organization': 'SSC',
      'exam_name': 'CGL 2026',
      'portal_url': null,
      'application_deadline': '2026-12-01T12:00:00+05:30',
      'hours_remaining': 30,
      'urgency': 'critical',
      'next_step': 'Apply',
      'match_kind': kind,
      'best_post': {
        'post_detail_id': 'post-$id',
        'post_name': 'Inspector',
        'category_quota_seats': 6,
        'ur_open_seats': 20,
        'total_reachable_seats': 26,
        'eligible_via_relaxation': false,
        'notes': const <String>[],
        'match_kind': kind,
        'match_reason_label': kind == 'direct' ? 'Universal Graduate Post' : null,
        'suggestion_reasons': reasons,
      },
      'other_eligible_posts': const <dynamic>[],
      'timeline': {'job_post_id': 'job-$id', 'admit_card_url': null},
    };

void main() {
  test('parses direct items, suggestions and timelines', () {
    final snap = FeedSnapshot.fromJson({
      'category': 'SC',
      'hero': _item('1'),
      'up_next': [_item('2')],
      'hidden_count': 0,
      'suggested': [
        _item('3', kind: 'suggested', reasons: ['experience_gap'])
      ],
      'suggested_hidden_count': 2,
    }, fetchedAt: DateTime(2026, 11, 30));

    expect(snap.items.map((i) => i.jobPostId), ['job-1', 'job-2']);
    expect(snap.items.first.bestPost.matchReasonLabel, 'Universal Graduate Post');
    expect(snap.items.first.timelineJson?['job_post_id'], 'job-1');
    final s = snap.suggested.single;
    expect(s.matchKind, MatchKind.suggested);
    expect(suggestionBadge(s.bestPost.suggestionReasons), '💡 Suggested: Experience Gap');
    expect(snap.suggestedHiddenCount, 2);
  });

  test('older cached feeds without the new fields still parse', () {
    final legacy = _item('1')
      ..remove('match_kind')
      ..remove('timeline');
    final snap =
        FeedSnapshot.fromJson({'hero': legacy, 'up_next': const <dynamic>[]}, fetchedAt: DateTime(2026));
    expect(snap.items.single.matchKind, MatchKind.direct);
    expect(snap.suggested, isEmpty);
  });
}
