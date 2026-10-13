import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/domain/relevance.dart';
import 'package:exam_tracker/models/feed.dart';
import 'package:exam_tracker/models/job_preferences.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 13, 6);

Map<String, dynamic> job(
  String id, {
  required String category,
  required String postName,
  String org = 'Org',
  int? pay,
  String level = 'UG',
  String? type,
  int days = 10,
}) =>
    {
      'id': id,
      'organization': org,
      'exam_name': 'Exam $id',
      'category': category,
      'employment_type': type,
      'application_deadline': now.add(Duration(days: days)).toIso8601String(),
      'posts': [
        {
          'id': 'p-$id',
          'post_name': postName,
          'base_max_age': 32,
          'age_as_on': '2026-10-01',
          'min_qualification_level': level,
          'is_open_to_any_graduate': level == 'UG',
          'monthly_pay_min': pay,
          'vacancy': {'ur': 10, 'sc': 3, 'st': 1, 'obc': 5, 'ews': 2, 'total': 21},
        }
      ],
    };

final graduate = UserProfileData(
  displayName: 'Me',
  dateOfBirth: DateTime(2000, 1, 1),
  category: ReservationCategory.ur,
  qualificationTier: 'UG',
  degreeTitle: 'B_TECH',
);

List<FeedItem> feed(List<Map<String, dynamic>> jobs) => buildFeed(
      jobs: JobsFile.fromJson({'schema': 1, 'generated_at': now.toIso8601String(), 'jobs': jobs}),
      profile: graduate,
      appliedPostIds: const {},
      now: now,
      fetchedAt: now,
    ).items;

List<String> ids(List<RankedJob> ranked) => [for (final r in ranked) r.item.jobPostId];

void main() {
  final items = feed([
    job('gardener', category: 'other', postName: 'Gardener', level: 'MATRIC', days: 2),
    job('marathi', category: 'teaching', postName: 'Assistant Teacher (Marathi)', days: 3),
    job('jrf',
        category: 'research', postName: 'Junior Research Fellow', pay: 37000, type: 'fellowship', days: 4),
    job('ntpc',
        category: 'railway', postName: 'Goods Train Manager', pay: 29200, type: 'permanent', days: 20),
    job('sbi', category: 'bank', postName: 'Probationary Officer', pay: 48480, type: 'permanent', days: 15),
  ]);

  test('graduates don’t see 10th-pass posts or posts in a language they don’t know', () {
    final ranked = rankJobs(items, JobPreferences.defaults, Affinity.empty, myLevel: 'UG');
    expect(ids(ranked), isNot(contains('gardener')));
    expect(ids(ranked), isNot(contains('marathi')));
    final withMarathi = JobPreferences.defaults.copyWith(languages: {'Hindi', 'English', 'Marathi'});
    expect(ids(rankJobs(items, withMarathi, Affinity.empty, myLevel: 'UG')), contains('marathi'));
    // A 10th-pass applicant sees the gardener post.
    expect(ids(rankJobs(items, JobPreferences.defaults, Affinity.empty, myLevel: 'MATRIC')),
        contains('gardener'));
  });

  test('big recruitments and better pay rank first; picks and hides apply', () {
    final ranked = rankJobs(items, JobPreferences.defaults, Affinity.empty, myLevel: 'UG');
    expect(ids(ranked).take(2), ['sbi', 'ntpc']);

    final researchFirst = JobPreferences.defaults.copyWith(preferred: {JobCategory.research});
    expect(ids(rankJobs(items, researchFirst, Affinity.empty, myLevel: 'UG')).first, 'jrf');

    final noBanks = JobPreferences.defaults.copyWith(hidden: {JobCategory.bank});
    expect(ids(rankJobs(items, noBanks, Affinity.empty, myLevel: 'UG')), isNot(contains('sbi')));

    final byPay =
        rankJobs(items, JobPreferences.defaults, Affinity.empty, myLevel: 'UG', sort: JobSort.highestPay);
    expect(ids(byPay), ['sbi', 'jrf', 'ntpc']);
    final bySoon =
        rankJobs(items, JobPreferences.defaults, Affinity.empty, myLevel: 'UG', sort: JobSort.closingSoon);
    expect(ids(bySoon), ['jrf', 'sbi', 'ntpc']);
  });

  test('it learns: jobs like the ones you apply to move up, ones you reject move down', () {
    final jrf = items.firstWhere((i) => i.jobPostId == 'jrf');
    final sbi = items.firstWhere((i) => i.jobPostId == 'sbi');
    final affinity = Affinity.fromDecisions([
      Decision(features: jobFeatures(jrf), applied: true),
      Decision(features: jobFeatures(jrf), applied: true),
      Decision(features: jobFeatures(sbi), applied: false),
    ]);
    final ranked = rankJobs(items, JobPreferences.defaults, affinity, myLevel: 'UG');
    expect(ids(ranked).first, 'jrf');
    expect(ranked.first.reasons, contains('Like jobs you applied to'));
    expect(ids(ranked).last, 'sbi');
  });

  test('minimum pay keeps jobs that don’t state pay', () {
    final noPay = feed([job('unknown', category: 'ssc', postName: 'Inspector')]);
    final prefs = JobPreferences.defaults.copyWith(minMonthlyPay: 40000);
    expect(ids(rankJobs([...items, ...noPay], prefs, Affinity.empty, myLevel: 'UG')), ['sbi', 'unknown']);
  });

  test('preferences survive a JSON round trip; pay is written the Indian way', () {
    final p = JobPreferences.defaults.copyWith(
      preferred: {JobCategory.psu, JobCategory.bank},
      hidden: {JobCategory.teaching},
      minMonthlyPay: 25000,
      hiddenTypes: {'apprenticeship'},
    );
    final back = JobPreferences.fromJson(p.toJson());
    expect(back.preferred, p.preferred);
    expect(back.hidden, p.hidden);
    expect(back.minMonthlyPay, 25000);
    expect(back.hiddenTypes, {'apprenticeship'});
    expect(formatPay(35400), '₹35,400/month');
    expect(formatPay(112400), '₹1,12,400/month');
  });
}
