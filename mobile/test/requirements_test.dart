import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/domain/relevance.dart';
import 'package:exam_tracker/domain/requirements.dart';
import 'package:exam_tracker/models/job_preferences.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 17, 6);

ExtraRequirements req(String text, [String name = 'Post']) =>
    requirementsOf(PublishedPost(id: 'p', postName: name, qualificationText: text));

String? unmet(String text, [JobPreferences prefs = JobPreferences.defaults]) => unmetRequirement(req(text), prefs);

const teacherAndMarathi = 'Graduate with D.El.Ed / B.Ed / B.El.Ed, along with CTET or TET qualified and studied in '
    'Marathi medium at Secondary level.';

void main() {
  group('teaching qualifications', () {
    test('real notices: a teacher training degree and TET', () {
      final r = req(teacherAndMarathi);
      expect(r.teachingDegree, isTrue);
      expect(r.tet, isTrue);
      expect(req('Graduate degree plus B.T.C. or D.El.Ed. and Teacher Eligibility Test (TET) for Classes 1 to 5.').tet,
          isTrue);
      expect(req('Postgraduate degree in the relevant subject along with a B.Ed degree.').teachingDegree, isTrue);
    });

    test('"desirable" or "preferably" is not a requirement', () {
      expect(req('Post-Graduation in Nutrition with 5 years experience. B.Ed. desirable.').teachingDegree, isFalse);
      expect(req('Graduate, preferably B.Ed.').teachingDegree, isFalse);
    });

    test('no false B.Ed', () {
      expect(req('MBBS with experience in a 100 bed hospital.').teachingDegree, isFalse);
      expect(req('M.Tech in Computer Science with GATE.').isEmpty, isTrue);
    });

    test('hidden until you say you have them', () {
      expect(unmet(teacherAndMarathi), 'Needs B.Ed / D.El.Ed');
      final teacher = JobPreferences.defaults.copyWith(qualifications: {'teaching'});
      expect(unmet(teacherAndMarathi, teacher), 'Needs CTET / TET');
      final withTet = teacher.copyWith(qualifications: {'teaching', 'tet'});
      expect(unmet(teacherAndMarathi, withTet), 'Needs Marathi');
      expect(unmet(teacherAndMarathi, withTet.copyWith(languages: {'Hindi', 'English', 'Marathi'})), isNull);
    });
  });

  group('other professions: the post name and the text must agree', () {
    Set<Profession> needs(String name, String text) => req(text, name).professions;

    test('real posts that need a professional qualification', () {
      expect(needs('Project Nurse–I', 'Two-year Auxiliary Nurse & Midwife (ANM) course from a recognised institution.'),
          {Profession.nursing});
      expect(needs('Nursing Assistant', 'Plus Two Science group and Auxiliary Nursing & Midwifery course.'),
          {Profession.nursing});
      expect(needs('Pharmacist (NUHM)', 'D.Pharma or Bachelor Degree in Pharmacy with DCA.'), {Profession.pharmacy});
      expect(needs('Laboratory Technician', 'DMLT/BMLT/Pathology passed paramedical course and registration.'),
          {Profession.lab});
      expect(needs('Sr. Supervisor (Legal)', 'Graduate plus LLB (Regular).'), {Profession.law});
      expect(needs('Medical Officer - School Health', 'Any AYUSH Degree recognised by the statutory Council.'),
          {Profession.doctor});
      expect(needs('Physiotherapist', ''), {Profession.physio}); // the name alone is enough
      expect(needs('Staff Nurse', ''), {Profession.nursing});
    });

    test('open to others when the qualification is only one option, or the name says otherwise', () {
      expect(needs('Food Safety Officer (FSO)', "Bachelor's degree in Chemistry, Biotechnology, ... or MBBS."), isEmpty);
      expect(needs('Junior Assistant (Finance & Accounts)', 'Graduate in Commerce/MBA in Finance/CA Inter.'), isEmpty);
      expect(needs('Nursing Orderly', '10th pass.'), isEmpty);
      expect(needs('Labour Enforcement Officer', 'Graduate in any discipline.'), isEmpty);
      expect(needs('Lab Technician (School)', 'B.Sc with Physics and Chemistry. DMLT desirable.'), isEmpty);
    });

    test('your profile turns on what your degree shows', () {
      UserProfileData profile(String degree, [String? typed]) => UserProfileData(
            displayName: 'Me',
            dateOfBirth: DateTime(1998, 1, 1),
            category: ReservationCategory.ur,
            qualificationTier: 'UG',
            degreeTitle: degree,
            customQualificationText: typed,
          );
      expect(qualificationsFromProfile(profile('B_ED')), {'teaching'});
      expect(qualificationsFromProfile(profile('MBBS')), {'doctor'});
      expect(qualificationsFromProfile(profile('B_TECH')), isEmpty);
      expect(qualificationsFromProfile(profile('OTHERS', 'GNM nursing diploma')), {'nursing'});
      expect(qualificationsFromProfile(profile('OTHERS', 'BAMS')), {'doctor'});
      expect(qualificationsFromProfile(profile('OTHERS', 'D.El.Ed with CTET')), {'teaching', 'tet'});
    });
  });

  group('languages', () {
    test('the ways notices demand a language', () {
      expect(unmet('Knowledge of Marathi & English Language essential.'), 'Needs Marathi');
      expect(unmet('SSC or HSC passed with Marathi subject.'), 'Needs Marathi');
      expect(unmet('Must be able to speak, read and write Odia.'), 'Needs Odia');
      expect(unmet('Degree in Civil Engineering with knowledge of Konkani.'), 'Needs Konkani');
      expect(unmet('Proficiency in Bengali and English.'), 'Needs Bengali');
    });

    test('"or" means either will do; English and Hindi are yours by default', () {
      expect(unmet('Knowledge of Marathi or Hindi.'), isNull);
      expect(unmet('Post Graduate in English, B.Ed and studied in English medium.',
          JobPreferences.defaults.copyWith(qualifications: {'teaching'})), isNull);
    });

    test('a title naming the language of the work', () {
      String? byTitle(String name) => unmetRequirement(req('Graduate with 2 years experience.', name), JobPreferences.defaults);
      expect(byTitle('Telugu Reporter'), 'Needs Telugu');
      expect(byTitle('TGT (Sanskrit)'), 'Needs Sanskrit');
      expect(byTitle('Lecturer in Urdu'), 'Needs Urdu');
      expect(byTitle('Hindi Translator'), isNull, reason: 'Hindi is yours by default');
      expect(byTitle('Tamil Nadu Forest Guard'), isNull);
      expect(byTitle('Assistant Engineer (Electrical)'), isNull);
    });

    test('a desirable language is not a requirement', () {
      expect(unmet('Knowledge of Konkani is essential. Knowledge of Marathi is desirable.'), 'Needs Konkani');
      expect(unmet('Knowledge of Marathi is desirable.'), isNull);
    });
  });

  group('whole jobs', () {
    final graduate = UserProfileData(
      displayName: 'Me',
      dateOfBirth: DateTime(2000, 1, 1),
      category: ReservationCategory.ur,
      qualificationTier: 'UG',
      degreeTitle: 'B_TECH',
    );

    Map<String, dynamic> post(String id, String name, String text) => {
          'id': id,
          'post_name': name,
          'base_max_age': 40,
          'age_as_on': '2026-10-01',
          'min_qualification_level': 'UG',
          'is_open_to_any_graduate': true, // how the pipeline tags these today
          'qualification_text': text,
          'vacancy': {'ur': 10, 'total': 10},
        };

    List<String> visible(List<Map<String, dynamic>> posts, [JobPreferences prefs = JobPreferences.defaults]) {
      final items = buildFeed(
        jobs: JobsFile.fromJson({
          'schema': 1,
          'generated_at': now.toIso8601String(),
          'jobs': [
            {
              'id': 'job',
              'organization': 'Zilla Parishad',
              'exam_name': 'Teacher Recruitment',
              'category': 'teaching',
              'application_deadline': now.add(const Duration(days: 10)).toIso8601String(),
              'posts': posts,
            }
          ],
        }),
        profile: graduate,
        appliedPostIds: const {},
        now: now,
        fetchedAt: now,
      ).items;
      return [
        for (final r in rankJobs(items, prefs, Affinity.empty, myLevel: 'UG')) r.item.jobPostId
      ];
    }

    test('a teacher post you can’t take is hidden, with the reason', () {
      expect(visible([post('t', 'Full-Time Teacher', teacherAndMarathi)]), isEmpty);
      final qualified = JobPreferences.defaults
          .copyWith(qualifications: {'teaching', 'tet'}, languages: {'Hindi', 'English', 'Marathi'});
      expect(visible([post('t', 'Full-Time Teacher', teacherAndMarathi)], qualified), ['job']); // it comes back
    });

    test('a job shows only the posts you can take, headlined by one of them', () {
      final items = buildFeed(
        jobs: JobsFile.fromJson({
          'schema': 1,
          'generated_at': now.toIso8601String(),
          'jobs': [
            {
              'id': 'cmho',
              'organization': 'Chief Medical and Health Office',
              'exam_name': 'NHM Recruitment',
              'category': 'medical',
              'application_deadline': now.add(const Duration(days: 10)).toIso8601String(),
              'posts': [
                {...post('ph', 'Pharmacist', 'D.Pharm with registration in State Pharmacy Council.'), 'vacancy': {'ur': 30, 'total': 30}},
                post('deo', 'Data Entry Operator', 'Graduate in any discipline with typing speed.'),
              ],
            }
          ],
        }),
        profile: graduate,
        appliedPostIds: const {},
        now: now,
        fetchedAt: now,
      ).items;
      final shown = rankJobs(items, JobPreferences.defaults, Affinity.empty, myLevel: 'UG').single.item;
      expect(shown.bestPost.postName, 'Data Entry Operator');
      expect([for (final p in shown.posts) p.postName], ['Data Entry Operator']);
    });

    test('a job stays if even one of its posts suits you', () {
      expect(
        visible([
          post('t', 'Full-Time Teacher', teacherAndMarathi),
          post('c', 'Junior Clerk', 'Graduation in any discipline with basic computer knowledge.'),
        ]),
        ['job'],
      );
    });
  });
}
