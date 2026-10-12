import 'package:exam_tracker/domain/lifecycle.dart';
import 'package:exam_tracker/models/exam_timeline.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 12, 1, 10);

  TrackedApplication app({
    ApplicationStatus status = ApplicationStatus.applied,
    TrackerStatus? server,
    ExamTimeline? timeline,
  }) =>
      TrackedApplication(
        id: 'p1',
        examName: 'SSC CGL 2026',
        postName: 'Inspector',
        status: status,
        createdAt: now,
        updatedAt: now,
        timeline: timeline,
        serverStatus: server,
      );

  ExamTimeline timeline(Map<String, dynamic> fields) =>
      ExamTimeline.fromJson({'job_post_id': 'j1', ...fields});

  Map<LifecycleStage, StageState> states(TrackedApplication a) =>
      {for (final s in computeLifecycle(a, a.timeline, now)) s.stage: s.state};

  test('freshly applied, nothing announced: admit card is next, the rest locked', () {
    expect(states(app()), {
      LifecycleStage.applied: StageState.completed,
      LifecycleStage.admitCard: StageState.active,
      LifecycleStage.exam: StageState.locked,
      LifecycleStage.answerKey: StageState.locked,
      LifecycleStage.result: StageState.locked,
    });
  });

  test('announced dates turn locked stages into upcoming ones', () {
    final a = app(timeline: timeline({'exam_start': '2026-12-14', 'result_date': '2027-02-01'}));
    expect(states(a)[LifecycleStage.exam], StageState.upcoming);
    expect(states(a)[LifecycleStage.result], StageState.upcoming);
    expect(states(a)[LifecycleStage.answerKey], StageState.locked);
  });

  test('admit card link gives a primary download action', () {
    final a = app(timeline: timeline({'admit_card_url': 'https://ssc.gov.in/admit'}));
    final admit = computeLifecycle(a, a.timeline, now)[1];
    expect(admit.state, StageState.active);
    expect(admit.actions.single.label, 'Download admit card');
    expect(admit.actions.single.primary, isTrue);
  });

  test('exam over and answer key out with an open objection window', () {
    final a = app(
      timeline: timeline({
        'exam_start': '2026-11-20',
        'answer_key_url': 'https://k',
        'objection_deadline': '2026-12-05',
        'challenge_portal_url': 'https://c',
      }),
    );
    final s = states(a);
    expect(s[LifecycleStage.admitCard], StageState.completed);
    expect(s[LifecycleStage.exam], StageState.completed);
    expect(s[LifecycleStage.answerKey], StageState.active);
    final key = computeLifecycle(a, a.timeline, now)[3];
    expect(key.details.single, 'Objections close 5 Dec');
    expect(key.actions.map((x) => x.label), ['View answer key', 'Raise objection']);
  });

  test('result out completes everything and shows cut-offs', () {
    final a = app(
        timeline: timeline({
      'merit_list_url': 'https://m',
      'cutoff_marks': {'UR': 142.5, 'SC': 118}
    }));
    expect(states(a).values.toSet(), {StageState.completed});
    expect(computeLifecycle(a, a.timeline, now).last.details.single, 'Cut-off: UR 142.5 · SC 118');
  });

  test('display status is the further of local and watcher status', () {
    expect(app(server: TrackerStatus.answerKeyLive).displayStatus, TrackerStatus.answerKeyLive);
    expect(app(status: ApplicationStatus.examScheduled, server: TrackerStatus.applied).displayStatus,
        TrackerStatus.examScheduled);
    expect(app().displayStatus, TrackerStatus.applied);
  });

  test('date labels', () {
    expect(stageDateLabel(DateTime(2026, 12, 14)), '14 Dec');
    expect(stageDateLabel(DateTime(2026, 12, 14), DateTime(2026, 12, 18)), '14 – 18 Dec');
    expect(stageDateLabel(DateTime(2026, 11, 28), DateTime(2026, 12, 3)), '28 Nov – 3 Dec');
  });
}
