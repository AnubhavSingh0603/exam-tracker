import 'package:exam_tracker/domain/eligibility.dart';
import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/domain/relevance.dart';
import 'package:exam_tracker/domain/requirements.dart';
import 'package:exam_tracker/domain/subjects.dart';
import 'package:exam_tracker/models/job_preferences.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 17, 6);

PublishedPost post(
  String name, {
  String? text,
  List<String> streams = const [],
  List<String> degrees = const ['B_TECH'],
  bool anyGraduate = false,
}) =>
    PublishedPost(
      id: 'p',
      postName: name,
      qualificationText: text,
      eligibleStreams: streams,
      allowedDegrees: degrees,
      openToAnyGraduate: anyGraduate,
    );

UserProfileData profile(String degree, List<SubjectChoice> subjects, {List<String> others = const []}) =>
    UserProfileData(
      displayName: 'Me',
      dateOfBirth: DateTime(2000),
      category: ReservationCategory.ur,
      qualificationTier: 'UG',
      degreeTitle: degree,
      otherDegrees: others,
      subjects: subjects,
    );

JobPreferences prefsFor(UserProfileData p) =>
    JobPreferences(subjects: subjectsFromProfile(p), degreesHeld: profileDegreesHeld(p));

/// The verdict for one group, as a holder of [picked] sees it.
SubjectVerdict? verdict(SubjectGroup g, PublishedPost p, Set<String> picked, {String custom = ''}) =>
    subjectsOf(p)?.needs[g.key]?.verdictFor(SubjectChoice(group: g.key, subjects: picked, custom: custom));

String? hiddenFor(PublishedPost p, UserProfileData who) => unmetRequirement(requirementsOf(p), prefsFor(who));

void main() {
  group('every group reads its own subjects', () {
    test('engineering branches', () {
      expect(engineering.subjectsIn('B.E./B.Tech Electronics & Communication'), containsAll(['electronics', 'telecom']));
      expect(engineering.subjectsIn('Diploma in Civil Engineering'), {'civil'});
      expect(engineering.subjectsIn('B.Tech in CSE/IT'), {'computer'});
      expect(engineering.subjectsIn('B.E. Mechanical / Production'), {'mechanical'});
      expect(engineering.subjectsIn('B.Tech Chemical Engineering'), {'chemical'});
    });

    test('ITI trades', () {
      expect(iti.subjectsIn('ITI in Electrician / Wireman trade'), {'electrician', 'wireman'});
      expect(iti.subjectsIn('NCVT certificate in Fitter'), {'fitter'});
      expect(iti.subjectsIn('ITI (COPA)'), {'copa'});
    });

    test('science, arts, commerce, MBA and medical subjects', () {
      expect(science.subjectsIn('M.Sc. Physics'), {'physics'});
      expect(science.subjectsIn('B.Sc Agriculture / Horticulture'), {'agriculture', 'horticulture'});
      expect(arts.subjectsIn('M.A. in Political Science'), {'political_science'});
      expect(arts.subjectsIn('MA Hindi'), {'hindi'});
      expect(commerce.subjectsIn('M.Com with Accountancy'), {'accounting'});
      expect(management.subjectsIn('MBA (HR)'), {'hr'});
      expect(medicine.subjectsIn('MD/DNB in Paediatrics or DCH'), {'paediatrics'});
    });

    test('short forms count only in capitals; "preferred" is not a must', () {
      expect(engineering.subjectsIn('Degree as specified in it, with communication skills'), isEmpty);
      expect(engineering.subjectsIn('B.E./B.Tech (Mechanical/Civil preferred)'), isEmpty);
      expect(engineering.subjectsIn('Civil Services Examination'), isEmpty);
    });
  });

  group('verdicts', () {
    test('a named subject of yours matches; only others do not', () {
      final civilJe = post('Junior Engineer (Civil)',
          streams: ['Three-year Diploma in Civil Engineering', 'Degree in Civil Engineering'],
          degrees: ['DIPLOMA', 'B_TECH']);
      expect(verdict(engineering, civilJe, {'civil'}), SubjectVerdict.match);
      expect(verdict(engineering, civilJe, {'mechanical'}), SubjectVerdict.other);

      final pgt = post('PGT Physics', streams: ['M.Sc. Physics'], degrees: ['M_SC']);
      expect(verdict(science, pgt, {'physics'}), SubjectVerdict.match);
      expect(verdict(science, pgt, {'zoology'}), SubjectVerdict.other);

      final electrician = post('Technician', streams: ['ITI Electrician'], degrees: ['ITI']);
      expect(verdict(iti, electrician, {'electrician'}), SubjectVerdict.match);
      expect(verdict(iti, electrician, {'fitter'}), SubjectVerdict.other);
    });

    test('a subject you typed yourself', () {
      final p = post('Officer', streams: ['B.E./B.Tech Railway Engineering']);
      expect(verdict(engineering, p, {}, custom: 'Railway Engineering'), SubjectVerdict.match);
      expect(verdict(engineering, p, {'civil'}), SubjectVerdict.other);
    });

    test('any subject, or the degree in general', () {
      expect(verdict(engineering, post('GET', streams: ['B.E./B.Tech Any Branch']), {'civil'}), SubjectVerdict.any);
      expect(verdict(engineering, post('JRF', streams: ['B.E./B.Tech Engineering/Technology']), {'civil'}),
          SubjectVerdict.any);
      expect(verdict(science, post('Analyst', streams: ['B.Sc in any discipline'], degrees: ['B_SC']), {'physics'}),
          SubjectVerdict.any);
    });

    test('does not say: unclear', () {
      final p = post('JRF', text: 'B.Tech/M.Tech in relevant discipline.', streams: ['B.Tech/B.E. Relevant Discipline']);
      expect(verdict(engineering, p, {'textile'}), SubjectVerdict.unclear);
    });

    test('streams decide per degree: the B.Tech branch is not an M.Sc subject', () {
      final p = post('Scientist',
          text: 'B.Tech Electronics or M.Sc Physics', streams: ['B.Tech Electronics', 'M.Sc Physics'], degrees: ['B_TECH', 'M_SC']);
      expect(verdict(science, p, {'electronics'}), SubjectVerdict.other);
      expect(verdict(engineering, p, {'electronics'}), SubjectVerdict.match);
    });

    test('no rule for posts open to any graduate, or medical PG diplomas under DIPLOMA', () {
      expect(subjectsOf(post('Clerk', anyGraduate: true)), isNull);
      expect(subjectsOf(post('Skin specialist', streams: ['MD', 'PG Diploma'], degrees: ['DIPLOMA']))!.needs, isEmpty);
    });
  });

  group('in the job list', () {
    final civilOnly = post('JE (Civil)', streams: ['B.E./B.Tech Civil', 'B.E./B.Tech Mechanical']);
    final mechEngineer = profile('B_TECH', [const SubjectChoice(group: 'engineering', subjects: {'electrical'})]);

    test('hidden with a reason; no picks means no filter', () {
      expect(hiddenFor(civilOnly, mechEngineer), 'Needs Civil / Mechanical');
      expect(hiddenFor(civilOnly, profile('B_TECH', const [])), isNull);
    });

    test('any degree you hold that the post accepts can open it', () {
      final p = post('Programmer', streams: ['MCA', 'B.E./B.Tech CSE'], degrees: ['MCA', 'B_TECH']);
      expect(hiddenFor(p, mechEngineer), isNotNull);
      // MCA has no subject list: that route is open.
      final withMca = profile('B_TECH', [const SubjectChoice(group: 'engineering', subjects: {'electrical'})],
          others: ['MCA']);
      expect(hiddenFor(p, withMca), isNull);
      // Two routes with subjects: one fitting is enough.
      final both = post('Scientist', streams: ['B.Tech Civil', 'M.Sc Physics'], degrees: ['B_TECH', 'M_SC']);
      final engAndSci = profile('B_TECH', [
        const SubjectChoice(group: 'engineering', subjects: {'electrical'}),
        const SubjectChoice(group: 'science', subjects: {'physics'}),
      ], others: ['M_SC']);
      expect(hiddenFor(both, engAndSci), isNull);
    });

    test('a group with nothing picked stays open', () {
      final p = post('PGT Chemistry', streams: ['M.Sc Chemistry'], degrees: ['M_SC']);
      final scienceUnpicked = profile('M_SC', [const SubjectChoice(group: 'engineering', subjects: {'civil'})]);
      expect(hiddenFor(p, scienceUnpicked), isNull);
    });

    test('unclear posts stay, tagged with the group\'s word', () {
      final item = buildFeed(
        jobs: JobsFile.fromJson({
          'schema': 1,
          'generated_at': now.toIso8601String(),
          'jobs': [
            {
              'id': 'job',
              'organization': 'Institute',
              'exam_name': 'Research posts',
              'category': 'research',
              'application_deadline': now.add(const Duration(days: 10)).toIso8601String(),
              'posts': [
                {
                  'id': 'p',
                  'post_name': 'Project Assistant',
                  'allowed_degrees': ['B_SC'],
                  'qualification_text': 'B.Sc in a relevant subject.',
                  'eligible_streams': ['B.Sc relevant subject'],
                  'vacancy': {'ur': 2, 'total': 2},
                }
              ],
            }
          ],
        }),
        profile: profile('B_SC', [const SubjectChoice(group: 'science', subjects: {'botany'})]),
        appliedPostIds: const {},
        now: now,
        fetchedAt: now,
      ).items.single;
      final prefs = prefsFor(profile('B_SC', [const SubjectChoice(group: 'science', subjects: {'botany'})]));
      expect(subjectUnclear(item, prefs), 'subject');
      expect(rankJob(item, prefs, Affinity.empty).reasons, contains('Check subject'));
      expect(subjectUnclear(item, JobPreferences.defaults), isNull);
    });
  });

  group('profile', () {
    test('groups follow the degrees you hold; M.Sc shares the B.Sc list', () {
      expect(groupsForDegrees(['M_SC']).map((g) => g.key), ['science']);
      expect(groupsForDegrees(['B_TECH', 'MBA']).map((g) => g.key), ['engineering', 'management']);
      expect(groupsForDegrees(['LLB', 'BCA']), isEmpty);
    });

    test('nothing is ticked for you, for any subject', () {
      expect(profile('B_TECH', const []).subjects, isEmpty);
      expect(subjectsFromProfile(profile('B_TECH', const [])), isEmpty);
    });

    test('picks for a degree you no longer hold are ignored', () {
      final p = profile('B_COM', [const SubjectChoice(group: 'engineering', subjects: {'civil'})]);
      expect(subjectsFromProfile(p), isEmpty);
    });

    test('saved and read back, and 0.14.0 branches carried over', () {
      final p = profile('B_SC', [const SubjectChoice(group: 'science', subjects: {'physics'}, custom: 'Astronomy')]);
      final back = UserProfileData.fromJson(p.toJson());
      expect(back.subjects.single.subjects, {'physics'});
      expect(back.subjects.single.customTerms, ['Astronomy']);
      expect(subjectSummary(back.subjects.single), 'Physics, Astronomy');

      final old = {...profile('B_TECH', const []).toJson(), 'branch': 'electronics', 'also_branches': ['electrical']};
      final migrated = UserProfileData.fromJson(old).subjects.single;
      expect(migrated.group, 'engineering');
      expect(migrated.subjects, {'electronics', 'electrical'});
    });
  });
}
