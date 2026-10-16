import 'package:exam_tracker/domain/delivery_track.dart';
import 'package:exam_tracker/domain/exam_watcher.dart';
import 'package:exam_tracker/models/exam_timeline.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/screens/my_exams_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final oct1 = DateTime(2026, 10, 1);

  ({DateTime start, DateTime? end})? w(String text, [DateTime? ref]) =>
      extractEventWindow(text, reference: ref ?? oct1);

  group('reading exam dates from notices', () {
    test('windows in the ways Indian notices print them', () {
      final cgl = (start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 19));
      expect(w('Tier-I exam 12–19 October 2026'), cgl);
      expect(w('Tier-I exam 12th to 19th Oct, 2026'), cgl);
      expect(w('Exam schedule: October 12-19, 2026'), cgl);
      expect(w('Exam from 12.10.2026 to 19.10.2026'), cgl);
      expect(w('Exam 12-19 October'), cgl); // year from when it was seen
      expect(w('Tier 1 October 12 to 19'), cgl); // not "1 October"
    });

    test('SSC CGL 2026 Tier 1 as SSC words it (month names and years on both sides)', () {
      final tier1 = (start: DateTime(2026, 9, 30), end: DateTime(2026, 10, 30));
      expect(w('SSC CGL Tier 1 Exam 2026 from September 30, 2026 to October 30, 2026.'), tier1);
      expect(w('Tier 1 Exam Dates: September 30, 2026 – October 30, 2026'), tier1);
      expect(w('Tier 1: Sep 30 - Oct 30, 2026'), tier1);
    });

    test('windows across months and years', () {
      expect(w('CBT 28 Nov to 3 Dec 2026'), (start: DateTime(2026, 11, 28), end: DateTime(2026, 12, 3)));
      expect(w('CBT 28 to 3 December 2026'), (start: DateTime(2026, 11, 28), end: DateTime(2026, 12, 3)));
      expect(w('CBT 28 Dec to 3 Jan 2027'), (start: DateTime(2026, 12, 28), end: DateTime(2027, 1, 3)));
    });

    test('single dates still work, and the first day of a window is the exam date', () {
      expect(w('Exam on 14.12.2026'), (start: DateTime(2026, 12, 14), end: null));
      expect(w('scheduled from 3rd March 2027'), (start: DateTime(2027, 3, 3), end: null));
      expect(extractEventDate('Exam 12-19 October 2026'), DateTime(2026, 10, 12)); // was the 19th
    });

    test('no false dates', () {
      expect(w('SSC CGL 2026 Tier-1 admit card released'), isNull);
      expect(w('Decision on 12 decision makers'), isNull);
      expect(w('Answer key for posts 1 to 5'), isNull);
    });
  });

  group('filling the timeline', () {
    DetectedUpdate schedule(String title, {DateTime? start, DateTime? end}) => DetectedUpdate(
        milestone: Milestone.examSchedule,
        title: title,
        url: 'https://ssc.gov.in/n/1',
        source: UpdateSource.official,
        eventDate: start,
        eventEnd: end);

    test('a window sets the start and the end', () {
      final t = fillTimeline({}, schedule('x', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 19)), oct1);
      expect(t['exam_start'], '2026-10-12');
      expect(t['exam_end'], '2026-10-19');
    });

    test('an exam that already started or just ended is still learned; an old one is not', () {
      final seen = DateTime(2026, 10, 25);
      final recent = fillTimeline({}, schedule('x', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 19)), seen);
      expect(recent['exam_start'], '2026-10-12');
      final old = fillTimeline({}, schedule('x', start: DateTime(2026, 6, 1)), seen);
      expect(old['exam_start'], isNull);
    });

    test('dates read wrongly before (a window stored as its last day) are repaired', () {
      final stored = [
        ExamUpdate(
          milestone: 'admit_card',
          title: 'SSC CGL 2026 Tier-I Admit Card (Exam 12-19 October 2026)',
          url: 'https://ssc.gov.in/a',
          detectedAt: DateTime(2026, 10, 5),
        ),
      ];
      final t = refreshExamDates({'job_post_id': 'j', 'exam_start': '2026-10-19'}, stored, DateTime(2026, 10, 25));
      expect(t['exam_start'], '2026-10-12');
      expect(t['exam_end'], '2026-10-19');
    });
  });

  group('cards', () {
    TrackedApplication cgl({DateTime? examAt, bool archived = false, Map<String, dynamic> t = const {}}) =>
        TrackedApplication(
          id: 'cgl',
          examName: 'SSC CGL 2026',
          postName: 'SSC CGL 2026',
          status: examAt == null ? ApplicationStatus.applied : ApplicationStatus.examScheduled,
          examAt: examAt,
          archived: archived,
          tiers: const ['Tier-1', 'Tier-2'],
          createdAt: oct1,
          updatedAt: oct1,
          timeline: ExamTimeline.fromJson({'job_post_id': 'j', ...t}),
        );
    final window = {'exam_start': '2026-10-12', 'exam_end': '2026-10-19'};

    test('before, during and after an exam window', () {
      final a = cgl(t: window);
      expect(a.focusDateAt(DateTime(2026, 10, 5)), DateTime(2026, 10, 12));
      expect(buildDeliveryTrack(a, DateTime(2026, 10, 5)).statusLabel, 'Admit card awaited'); // comes first
      final scheduled = cgl(t: {...window, 'admit_card_url': 'https://ssc.gov.in/ac'});
      expect(buildDeliveryTrack(scheduled, DateTime(2026, 10, 5)).statusLabel, 'Admit card out');
      expect(a.focusDateAt(DateTime(2026, 10, 15)), DateTime(2026, 10, 19));
      expect(buildDeliveryTrack(a, DateTime(2026, 10, 15)).statusLabel, 'Exam on, till 19 Oct');
      expect(a.focusDateAt(DateTime(2026, 10, 25)), isNull);
    });

    test('after Tier-1 with no answer key yet: answer key is next, with the expected month', () {
      final t = buildDeliveryTrack(cgl(t: window), DateTime(2026, 10, 25));
      expect(t.activeIndex, 3);
      expect(t.stops[1].state.name, 'completed'); // admit card
      expect(t.stops[2].state.name, 'completed'); // exam
      expect(t.statusLabel, 'Answer key expected Nov');
      expect(t.headline, 'Tier-1 exam is done. Answer keys usually come about 3 weeks later, so expect it around November.');
    });

    test('a date you enter ("Exam is done") wins over the notice', () {
      final a = cgl(examAt: DateTime(2026, 10, 12), t: {'exam_start': '2026-11-30'});
      expect(buildDeliveryTrack(a, DateTime(2026, 10, 20)).activeIndex, 3);
    });

    test('three tabs: tracked, results out, archived', () {
      final now = DateTime(2026, 10, 25);
      expect(tabOf(cgl(t: window), now), ExamTab.tracked);
      expect(tabOf(cgl(t: {...window, 'merit_list_url': 'https://ssc.gov.in/r'}), now), ExamTab.resultsOut);
      expect(tabOf(cgl(archived: true), now), ExamTab.archived);
    });
  });
}
