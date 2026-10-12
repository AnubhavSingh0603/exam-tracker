import 'package:exam_tracker/domain/next_step.dart';
import 'package:exam_tracker/domain/urgency.dart';
import 'package:exam_tracker/models/feed.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 11, 12);

TrackedApplication app(String id, ApplicationStatus status, {DateTime? examAt, bool archived = false}) =>
    TrackedApplication(
      id: id,
      examName: 'SSC CGL',
      postName: 'Inspector',
      status: status,
      examAt: examAt,
      archived: archived,
      createdAt: now,
      updatedAt: now,
    );

FeedItem feed(String id, DateTime deadline) => FeedItem(
      jobPostId: 'job-$id',
      organization: 'BEL',
      examName: 'PE 2026',
      deadline: deadline,
      urgency: Urgency.info,
      nextStep: '',
      bestPost: FeedPost(
        postDetailId: id,
        postName: 'Probationary Engineer',
        categoryQuotaSeats: 6,
        urOpenSeats: 20,
        totalReachableSeats: 26,
        eligibleViaRelaxation: false,
        notes: const [],
      ),
    );

void main() {
  test('nothing pending -> null', () {
    expect(computeNextStep(tracked: const [], feed: const [], now: now), isNull);
  });

  test('earliest due wins across tracked and feed', () {
    final step = computeNextStep(
      tracked: [app('a', ApplicationStatus.admitCardLive, examAt: now.add(const Duration(hours: 18)))],
      feed: [feed('f', now.add(const Duration(days: 3)))],
      now: now,
    )!;
    expect(step.kind, NextStepKind.downloadAdmitCard);
    expect(step.urgency, Urgency.urgent);
  });

  test('feed item becomes an apply step when sooner', () {
    final step = computeNextStep(
      tracked: [app('a', ApplicationStatus.examScheduled, examAt: now.add(const Duration(days: 20)))],
      feed: [feed('f', now.add(const Duration(days: 5)))],
      now: now,
    )!;
    expect(step.kind, NextStepKind.apply);
    expect(step.urgency, Urgency.warning);
  });

  test('archived, past and undated items are ignored', () {
    final step = computeNextStep(
      tracked: [
        app('arch', ApplicationStatus.examScheduled, examAt: now.add(const Duration(hours: 2)), archived: true),
        app('past', ApplicationStatus.examScheduled, examAt: now.subtract(const Duration(hours: 1))),
        app('nodate', ApplicationStatus.applied),
      ],
      feed: [feed('old', now.subtract(const Duration(minutes: 5)))],
      now: now,
    );
    expect(step, isNull);
  });

  test('tie prefers admit card over a new application', () {
    final due = now.add(const Duration(days: 2));
    final step = computeNextStep(
      tracked: [app('a', ApplicationStatus.admitCardLive, examAt: due)],
      feed: [feed('f', due)],
      now: now,
    )!;
    expect(step.kind, NextStepKind.downloadAdmitCard);
  });
}
