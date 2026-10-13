import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/models/feed.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13, 6);

  Map<String, dynamic> post(String id,
          {List<String> degrees = const ['B_TECH'], double exp = 0, int ur = 20}) =>
      {
        'id': id,
        'post_name': 'Post $id',
        'base_max_age': 30,
        'age_as_on': '2026-10-01',
        'allowed_degrees': degrees,
        'min_qualification_level': 'UG',
        'min_experience_years': exp,
        'vacancy': {'ur': ur, 'sc': 5, 'st': 2, 'obc': 8, 'ews': 3, 'total': ur + 18},
      };

  Map<String, dynamic> job(String id, Duration closesIn, List<Map<String, dynamic>> posts) => {
        'id': id,
        'organization': 'Org $id',
        'exam_name': 'Exam $id',
        'application_deadline': now.add(closesIn).toIso8601String(),
        'timeline': {'job_post_id': id},
        'posts': posts,
      };

  final profile = UserProfileData(
    displayName: 'Me',
    dateOfBirth: DateTime(2000, 1, 1),
    category: ReservationCategory.sc,
    qualificationTier: 'UG',
    degreeTitle: 'B_TECH',
    experienceYears: 1,
  );

  FeedSnapshot build(List<Map<String, dynamic>> jobs, {Set<String> applied = const {}}) => buildFeed(
        jobs: JobsFile.fromJson({'schema': 1, 'generated_at': now.toIso8601String(), 'jobs': jobs}),
        profile: profile,
        appliedPostIds: applied,
        now: now,
        fetchedAt: now,
      );

  test('deadline order, closed and ineligible jobs dropped, best post first', () {
    final snap = build([
      job('later', const Duration(days: 20), [post('a')]),
      job('closed', const Duration(hours: -1), [post('b')]),
      job('soon', const Duration(days: 2), [post('c', ur: 5), post('d', ur: 40)]),
      job('other-degree', const Duration(days: 1), [
        post('e', degrees: ['B_COM'])
      ]),
    ]);
    expect(snap.items.map((i) => i.jobPostId), ['soon', 'later']);
    expect(snap.items.first.bestPost.postDetailId, 'd'); // most reachable seats
    expect(snap.items.first.bestPost.totalReachableSeats, 45); // 40 UR + 5 SC
    expect(snap.items.first.bestPost.matchReasonLabel, 'Direct Degree Match');
    expect(snap.items.first.nextStep, startsWith('Apply for Post d (Org soon) — closes'));
    expect(snap.items.first.timelineJson, {'job_post_id': 'soon'});
    expect(snap.category, 'SC');
  });

  test('experience gap goes to Suggested, never both lists', () {
    final snap = build([
      job('gap', const Duration(days: 5), [post('a', exp: 2)]),
      job('mixed', const Duration(days: 6), [post('b', exp: 2), post('c')]),
    ]);
    expect(snap.items.map((i) => i.jobPostId), ['mixed']);
    expect(snap.suggested.map((i) => i.jobPostId), ['gap']);
    expect(snap.suggested.single.matchKind, MatchKind.suggested);
    expect(snap.suggested.single.nextStep, startsWith('Check if you fit'));
  });

  test('applied posts are hidden; everything else is listed (Today shows only the top few)', () {
    final jobs = [
      for (var i = 0; i < 8; i++) job('j$i', Duration(days: i + 1), [post('p$i')])
    ];
    final snap = build(jobs, applied: {'p0'});
    expect(snap.items.length, 7);
    expect(snap.items.first.jobPostId, 'j1');
    expect(snap.items.first.job?.id, 'j1'); // the whole notification, for the details panel
  });

  test('newer pipeline schema is refused, not misread', () {
    expect(() => JobsFile.fromJson({'schema': 99, 'jobs': const <dynamic>[]}), throwsFormatException);
  });
}
