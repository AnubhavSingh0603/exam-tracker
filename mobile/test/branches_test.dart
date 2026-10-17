import 'package:exam_tracker/domain/branches.dart';
import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/domain/relevance.dart';
import 'package:exam_tracker/domain/requirements.dart';
import 'package:exam_tracker/models/job_preferences.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 17, 6);

const ece = {Branch.electronics, Branch.telecom, Branch.instrumentation, Branch.electrical};

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

BranchVerdict? verdict(PublishedPost p) => branchNeedOf(p)?.verdictFor(ece);

UserProfileData profile({String degree = 'B_TECH', List<String> others = const [], String? branch = 'electronics'}) =>
    UserProfileData(
      displayName: 'Me',
      dateOfBirth: DateTime(2000),
      category: ReservationCategory.ur,
      qualificationTier: 'UG',
      degreeTitle: degree,
      otherDegrees: others,
      branch: branch,
      alsoBranches: [for (final b in Branch.electronics.usuallyAlso) b.key],
    );

const ecePrefs = JobPreferences(
  branches: {'electronics', 'telecom', 'instrumentation', 'electrical'},
  degreesHeld: {'B_TECH'},
);

void main() {
  group('reading branches', () {
    test('ECE spellings', () {
      for (final s in [
        'B.E./B.Tech Electronics & Communication',
        'B.E./B.Tech ECE',
        'B.Tech in E&C',
        'Diploma Electronics and Communication',
        'B.E./B.Tech Power Electronics',
        'M.Tech VLSI',
      ]) {
        expect(branchesIn(s), contains(Branch.electronics), reason: s);
      }
      expect(branchesIn('B.E. EXTC'), {Branch.telecom});
      expect(branchesIn('B.E./B.Tech Electronics & Telecommunication'), {Branch.electronics, Branch.telecom});
      expect(branchesIn('B.E./B.Tech Electrical & Electronics'), {Branch.electrical, Branch.electronics});
      expect(branchesIn('B.E./B.Tech Instrumentation & Control'), {Branch.instrumentation});
    });

    test('short forms count only in capitals', () {
      expect(branchesIn('B.Tech in CSE/IT'), {Branch.computer});
      expect(branchesIn('Degree as specified in it, with communication skills'), isEmpty);
      expect(branchesIn('Civil Services Examination'), isEmpty);
    });

    test('"preferred" branches are not a must', () {
      expect(branchesIn('B.E./B.Tech (Mechanical/Civil preferred)'), isEmpty);
      expect(branchesIn('B.E. preferably in Mechanical'), isEmpty);
    });
  });

  group('verdicts for an ECE graduate', () {
    test('a named branch of yours matches', () {
      expect(verdict(post('Assistant Engineer (Electrical)', streams: ['B.E./B.Tech Electrical Engineering'])),
          BranchVerdict.match);
      expect(
          verdict(post('Dy. Engineer (I&PC)',
              text: 'B.E./B.Tech in Instrumentation/Electronics & Instrumentation with 5 years experience.')),
          BranchVerdict.match);
    });

    test('only other branches: hidden', () {
      expect(
          verdict(post('Junior Engineer - Works',
              text: 'Three-year Diploma or relevant Degree in Civil or specified engineering discipline.',
              streams: ['Three-year Diploma in Civil Engineering', 'Degree in Civil Engineering'],
              degrees: ['DIPLOMA', 'B_TECH'])),
          BranchVerdict.other);
      expect(verdict(post('Technical Officer (Geoinformatics)', streams: ['B.E./B.Tech Geoinformatics'])),
          BranchVerdict.other);
      expect(verdict(post('Officer', streams: ['B.E./B.Tech Railway Engineering'])), BranchVerdict.other);
    });

    test('any branch, or engineering in general', () {
      expect(verdict(post('Graduate Engineer', streams: ['B.E./B.Tech Any Branch'])), BranchVerdict.anyBranch);
      expect(verdict(post('JRF', streams: ['B.E./B.Tech Engineering/Technology'])), BranchVerdict.anyBranch);
      expect(verdict(post('Marketing', text: 'B.E./B.Tech (Mechanical/Civil preferred)')), BranchVerdict.unclear);
    });

    test('a post that does not say', () {
      expect(
          verdict(post('Junior Research Fellow',
              text: 'B.Tech/B.E./M.Tech./M.E. or equivalent in relevant discipline with NET/GATE.',
              streams: ['B.Tech/B.E./M.Tech./M.E. Relevant Discipline'])),
          BranchVerdict.unclear);
    });

    test('not an engineering post: no rule', () {
      expect(verdict(post('Clerk', degrees: ['BA', 'B_COM'])), isNull);
      expect(verdict(post('Clerk', anyGraduate: true)), isNull);
      // DIPLOMA here is a medical PG diploma.
      expect(verdict(post('Skin specialist', streams: ['MD', 'PG Diploma'], degrees: ['MD_MS', 'DIPLOMA'])), isNull);
    });
  });

  group('in the job list', () {
    test('a post for other branches is hidden with a reason', () {
      final r = requirementsOf(post('JE (Civil)', streams: ['B.E./B.Tech Civil', 'B.E./B.Tech Mechanical']));
      expect(unmetRequirement(r, ecePrefs), 'Needs Civil / Mechanical');
      expect(unmetRequirement(r, JobPreferences.defaults), isNull, reason: 'no branch set: no filter');
    });

    test('another degree you hold opens it anyway', () {
      final r = requirementsOf(post('Programmer', streams: ['MCA', 'B.E./B.Tech CSE'], degrees: ['MCA', 'B_TECH']));
      expect(unmetRequirement(r, ecePrefs), isNotNull);
      expect(unmetRequirement(r, ecePrefs.copyWith(degreesHeld: {'B_TECH', 'MCA'})), isNull);
    });

    test('unclear posts stay, tagged "Check branch"', () {
      final p = post('JRF', text: 'B.Tech in relevant discipline.');
      expect(unmetRequirement(requirementsOf(p), ecePrefs), isNull);
      final item = buildFeed(
        jobs: JobsFile.fromJson({
          'schema': 1,
          'generated_at': now.toIso8601String(),
          'jobs': [
            {
              'id': 'job',
              'organization': 'IIT',
              'exam_name': 'JRF',
              'category': 'research',
              'application_deadline': now.add(const Duration(days: 10)).toIso8601String(),
              'posts': [
                {
                  'id': 'p',
                  'post_name': 'JRF',
                  'allowed_degrees': ['B_TECH'],
                  'qualification_text': 'B.Tech in relevant discipline.',
                  'vacancy': {'ur': 2, 'total': 2},
                }
              ],
            }
          ],
        }),
        profile: profile(),
        appliedPostIds: const {},
        now: now,
        fetchedAt: now,
      ).items.single;
      expect(branchUnclear(item, ecePrefs), isTrue);
      expect(rankJob(item, ecePrefs, Affinity.empty).reasons, contains('Check branch'));
      expect(branchUnclear(item, JobPreferences.defaults), isFalse);
    });
  });

  group('profile', () {
    test('ECE usually also covers Telecom, Instrumentation and Electrical', () {
      expect(branchesFromProfile(profile()), {'electronics', 'telecom', 'instrumentation', 'electrical'});
      expect(branchSummary(profile()), 'Electronics / ECE + 3 more');
    });

    test('no branch, or no engineering degree: no filter', () {
      expect(branchesFromProfile(profile(branch: null)), isEmpty);
      expect(branchesFromProfile(profile(degree: 'B_COM')), isEmpty);
      expect(branchesFromProfile(profile(degree: 'MBA', others: ['B_TECH'])), isNotEmpty);
    });

    test('saved and read back', () {
      final back = UserProfileData.fromJson(profile().toJson());
      expect(back.branch, 'electronics');
      expect(back.alsoBranches, ['telecom', 'instrumentation', 'electrical']);
      expect(UserProfileData.fromJson(profile(branch: null).toJson()).alsoBranches, isEmpty);
    });
  });
}
