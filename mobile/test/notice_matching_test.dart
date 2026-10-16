import 'package:exam_tracker/domain/delivery_track.dart';
import 'package:exam_tracker/domain/exam_watcher.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which tracked exam a notice is about', () {
    test('the long name finds the short one, through the exam list', () {
      expect(namesThisExam('SSC Combined Graduate Level Tier 1 Admit Card 2026', 'SSC CGL 2026', 'Staff Selection Commission'),
          isTrue);
      expect(namesThisExam('SSC CGL Tier-I Admit Card 2026', 'SSC CGL 2026', null), isTrue);
      expect(namesThisExam('IBPS SO XVI Pre Result 2026 – Out', 'IBPS SO XVI', 'Institute of Banking Personnel Selection'),
          isTrue);
    });

    test('not another exam, nor another year of this one', () {
      expect(namesThisExam('SSC CHSL Tier 1 Admit Card 2026', 'SSC CGL 2026', null), isFalse);
      expect(namesThisExam('SSC Combined Graduate Level Admit Card 2025', 'SSC CGL 2026', null), isFalse);
      expect(namesThisExam('Bihar STET Exam Date 2026', 'SSC CGL 2026', null), isFalse);
    });

    test('a notice about another stage is not attached', () {
      expect(namesAnotherStage('SSC CGL Tier-I Admit Card 2026', 'Tier-2'), isTrue);
      expect(namesAnotherStage('SSC CGL Tier II Admit Card 2026', 'Tier-2'), isFalse);
      expect(namesAnotherStage('SBI PO Mains Result 2026', 'Prelims'), isTrue);
      expect(namesAnotherStage('SBI PO Result 2026', 'Prelims'), isFalse); // names no stage
      expect(namesAnotherStage('SSC CGL Tier-I Admit Card 2026', null), isFalse);
    });
  });

  group('official links', () {
    const notice = PageLink(
      url: 'https://sarkariresult.com.cm/ssc-cgl-2026/?notice=admit_card-tier-i',
      title: 'SSC CGL Tier-I Admit Card 2026',
      link: 'https://ssc.gov.in/login',
    );

    test('a found notice keeps its page as its identity and the official link to open', () {
      final [d] = detectUpdates(
        [notice],
        examName: 'SSC CGL 2026',
        organization: 'Staff Selection Commission',
        source: UpdateSource.aggregator,
        examSpecificPage: false,
        knownUrls: const {},
        stage: 'Tier-1',
      );
      expect(d.url, notice.url);
      expect(d.open, 'https://ssc.gov.in/login');
      expect(fillTimeline({}, d, DateTime(2026, 10, 17))['admit_card_url'], 'https://ssc.gov.in/login');
    });

    test('the card button and the saved notice open the official link', () {
      const update = ExamUpdate(
        milestone: 'admit_card',
        title: 'SSC CGL Tier-I Admit Card 2026',
        url: 'https://sarkariresult.com.cm/ssc-cgl-2026/?notice=admit_card-tier-i',
        link: 'https://ssc.gov.in/login',
      );
      expect(ExamUpdate.fromJson(update.toJson()).open, 'https://ssc.gov.in/login');
      final now = DateTime(2026, 10, 17);
      final app = TrackedApplication(
        id: 'cgl',
        examName: 'SSC CGL 2026',
        postName: 'SSC CGL 2026',
        status: ApplicationStatus.applied,
        createdAt: now,
        updatedAt: now,
        watcherStatus: TrackerStatus.admitCardLive,
        updates: const [update],
      );
      expect(buildDeliveryTrack(app, now).action?.url, 'https://ssc.gov.in/login');
    });

    test('without an official link, the notice page opens', () {
      const update = ExamUpdate(milestone: 'result', title: 'X Result', url: 'https://agg/x/');
      expect(update.open, 'https://agg/x/');
    });
  });
}
