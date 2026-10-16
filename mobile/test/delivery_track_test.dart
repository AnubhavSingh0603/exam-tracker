import 'package:exam_tracker/domain/delivery_track.dart';
import 'package:exam_tracker/domain/lifecycle.dart';
import 'package:exam_tracker/models/exam_timeline.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/exam_delivery_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 12, 1, 10);

  TrackedApplication app({
    String name = 'IBPS PO XV',
    List<String> tiers = const ['Prelims', 'Mains', 'Interview'],
    int tier = 0,
    TrackerStatus? watcher,
    List<ExamUpdate> updates = const [],
    ExamTimeline? timeline,
  }) =>
      TrackedApplication(
        id: 'a1',
        examName: name,
        postName: name,
        status: ApplicationStatus.applied,
        applyUrl: 'https://ibpsreg.ibps.in/crppoxv',
        createdAt: now,
        updatedAt: now,
        tiers: tiers,
        tier: tier,
        watcherStatus: watcher,
        updates: updates,
        timeline: timeline,
      );

  ExamUpdate found(String milestone) =>
      ExamUpdate(milestone: milestone, title: milestone, url: 'https://example.gov.in/$milestone');

  test('just applied: the runner waits at the admit card; the next stage is the last stop', () {
    final t = buildDeliveryTrack(app(), now);
    expect([for (final s in t.stops) s.label], ['Applied', 'Admit card', 'Exam', 'Answer key', 'Result', 'Mains']);
    expect(t.activeIndex, 1);
    expect(t.stops[1].state, StageState.active);
    expect(t.headline, 'Waiting for the Prelims admit card. We’ll tell you the moment it’s out.');
    expect(t.action?.label, 'Candidate login');
  });

  test('an admit card the watcher found: download it is the step', () {
    final t = buildDeliveryTrack(
        app(watcher: TrackerStatus.admitCardLive, updates: [found('admit_card')]), now);
    expect(t.activeIndex, 1);
    expect(t.headline, startsWith('Prelims admit card is out.'));
    expect(t.action?.label, 'Download admit card');
    expect(t.action?.primary, isTrue);
  });

  test('result out with a next stage: the runner moves on to it, offering to track it', () {
    final t = buildDeliveryTrack(app(watcher: TrackerStatus.resultDeclared), now);
    expect(t.activeIndex, 5);
    expect(t.offersNextTier, isTrue);
    expect(t.headline, 'Prelims result is out. Next up: Mains.');
    expect(t.action?.label, 'Track Mains');
  });

  test('result of the last stage: everything done, no next stop', () {
    final t = buildDeliveryTrack(app(tier: 2, watcher: TrackerStatus.resultDeclared), now);
    expect(t.stops, hasLength(5));
    expect(t.finished, isTrue);
    expect(t.headline, 'Interview result is out.');
  });

  test('a one-stage exam has five stops and no stage prefix', () {
    final t = buildDeliveryTrack(app(name: 'My custom exam', tiers: const []), now);
    expect(t.stops, hasLength(5));
    expect(t.headline, startsWith('Waiting for the admit card'));
  });

  test('while objections are open, raising one is the action', () {
    final timeline = ExamTimeline.fromJson({
      'job_post_id': 'j1',
      'exam_start': '2026-11-20',
      'answer_key_url': 'https://example.gov.in/key',
      'challenge_portal_url': 'https://example.gov.in/objection',
      'objection_deadline': '2026-12-04',
    });
    final t = buildDeliveryTrack(app(timeline: timeline), now);
    expect(t.activeIndex, 3);
    expect(t.headline, 'Prelims answer key is out. Objections close 4 Dec.');
    expect(t.action?.label, 'Raise objection');
  });

  group('widget', () {
    final theme = AppTheme.of(Brightness.dark);
    Widget host(TrackedApplication a, {bool animationsOff = false, VoidCallback? onNext}) => MaterialApp(
          theme: theme,
          builder: (context, c) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: animationsOff), child: c!),
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: ExamDeliveryTracker(app: a, now: now, onTrackNextTier: onNext),
            ),
          ),
        );

    testWidgets('the runner travels to the current stop, then breathes there', (tester) async {
      await tester.pumpWidget(host(app()));
      expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.hasRunningAnimations, isTrue); // the pulse
      expect(find.textContaining('Waiting for the Prelims admit card'), findsOneWidget);
    });

    testWidgets('tapping a stop shows that stop; tapping the current one goes back', (tester) async {
      await tester.pumpWidget(host(app(), animationsOff: true));
      await tester.tap(find.text('Exam'));
      await tester.pump();
      expect(find.text('Exam: not announced yet'), findsOneWidget);
      await tester.tap(find.text('Admit card'));
      await tester.pump();
      expect(find.textContaining('Waiting for the Prelims admit card'), findsOneWidget);
    });

    testWidgets('with animations off nothing moves', (tester) async {
      await tester.pumpWidget(host(app(), animationsOff: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('"Track Mains" calls back instead of opening a link', (tester) async {
      var tracked = false;
      await tester.pumpWidget(
          host(app(watcher: TrackerStatus.resultDeclared), animationsOff: true, onNext: () => tracked = true));
      await tester.tap(find.text('Track Mains'));
      expect(tracked, isTrue);
    });
  });
}
