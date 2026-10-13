import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/domain/relevance.dart';
import 'package:exam_tracker/models/feed.dart';
import 'package:exam_tracker/models/job_preferences.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:exam_tracker/providers/providers.dart';
import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/job_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.now().toUtc();

class _FakeFeed extends FeedNotifier {
  _FakeFeed(this.snapshot);

  final FeedSnapshot snapshot;

  @override
  Future<FeedSnapshot> build() async => snapshot;
}

FeedSnapshot _snapshot() => buildFeed(
      jobs: JobsFile.fromJson({
        'schema': 1,
        'generated_at': now.toIso8601String(),
        'jobs': [
          {
            'id': 'ntpc',
            'organization': 'Railway Recruitment Board (all RRBs, Centralised Employment Notice)',
            'exam_name': 'RRB NTPC Graduate Level CEN 06/2026 — Goods Train Manager, Station Master and more',
            'advertisement_no': 'CEN 06/2026',
            'category': 'railway',
            'employment_type': 'permanent',
            'application_start': now.subtract(const Duration(days: 5)).toIso8601String(),
            'application_deadline': now.add(const Duration(days: 20)).toIso8601String(),
            'timeline': {'job_post_id': 'ntpc', 'fee_deadline': '2026-11-08'},
            'posts': [
              for (final name in [
                'Station Master',
                'Goods Train Manager (very long post name to wrap twice)'
              ])
                {
                  'id': name,
                  'post_name': name,
                  'min_age': 18,
                  'base_max_age': 33,
                  'age_as_on': '2027-01-01',
                  'qualification_text': 'Degree from a recognised university, or equivalent.',
                  'raw_eligibility_text': 'Graduation from a recognised university. ' * 20,
                  'min_qualification_level': 'UG',
                  'is_open_to_any_graduate': true,
                  'pay_scale': 'Level 6 of 7th CPC Pay Matrix (Rs 35,400 – 1,12,400) plus allowances',
                  'monthly_pay_min': 35400,
                  'age_relaxation_overrides': {'OBC': 3},
                  'vacancy': {'ur': 1200, 'sc': 500, 'st': 250, 'obc': 900, 'ews': 340, 'total': 3190},
                },
            ],
          },
        ],
      }),
      profile: UserProfileData(
        displayName: 'Me',
        dateOfBirth: DateTime(2000, 1, 1),
        category: ReservationCategory.obc,
        qualificationTier: 'UG',
        degreeTitle: 'B_TECH',
      ),
      appliedPostIds: const {},
      now: now,
      fetchedAt: now,
    );

void main() {
  testWidgets('a job card fits a small phone, folded and unfolded', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 2400 * 3); // 320 dp wide: a small phone
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final snapshot = _snapshot();
    final ranked = rankJob(snapshot.items.single, JobPreferences.defaults, Affinity.empty);
    await tester.pumpWidget(ProviderScope(
      overrides: [feedProvider.overrideWith(() => _FakeFeed(snapshot))],
      child: MaterialApp(
        theme: AppTheme.darkPastel(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(
                builder: (context) => JobCard(ranked: ranked, screenContext: context, showSwipeHint: true)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Apply online'), findsNothing); // no link in this test job
    expect(find.text('Railway'), findsOneWidget);
    expect(find.text('₹35,400/month'), findsOneWidget);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Level 6 of 7th CPC'), findsNWidgets(2)); // one per post
    expect(find.textContaining('(+3 for OBC)'), findsNWidgets(2));
    expect(find.text('Show all'), findsNWidgets(2));
    expect(tester.takeException(), isNull); // no overflow
  });
}
