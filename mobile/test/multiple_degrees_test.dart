import 'package:exam_tracker/domain/eligibility.dart';
import 'package:exam_tracker/domain/requirements.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfileData person(String degree, [List<String> others = const []]) => UserProfileData(
      displayName: 'Me',
      dateOfBirth: DateTime(1998, 5, 1),
      category: ReservationCategory.ur,
      qualificationTier: 'UG',
      degreeTitle: degree,
      otherDegrees: others,
    );

void main() {
  // "Asst. Teacher (Mathematics): Graduate in Mathematics with B.Ed." as the pipeline stores it.
  final teacher = PublishedPost.fromJson({
    'id': 'p',
    'post_name': 'Asst. Teacher - Mathematics',
    'base_max_age': 40,
    'age_as_on': '2026-10-01',
    'min_qualification_level': 'UG',
    'allowed_degrees': ['B_ED'],
    'qualification_text': 'Graduate/Preferably Post Graduate in Mathematics with B.Ed.',
  });

  test('a B.Ed held next to a B.Sc opens B.Ed posts; the B.Sc alone does not', () {
    expect(evaluateEligibility(person('B_SC'), teacher).qualificationMatch, isNot(true));
    final both = evaluateEligibility(person('B_SC', ['B_ED']), teacher);
    expect(both.qualificationMatch, isTrue);
    expect(both.isEligible, isTrue);
  });

  test('every degree counts for professional qualifications, and the label lists them', () {
    expect(qualificationsFromProfile(person('B_SC', ['B_ED'])), {'teaching'});
    expect(qualificationsFromProfile(person('B_A', ['LLB', 'B_ED'])), {'law', 'teaching'});
    expect(person('B_SC', ['B_ED']).qualificationLabel, 'B.Sc + B.Ed');
  });

  test('saved and restored with the profile (and the Drive backup)', () {
    final back = UserProfileData.fromJson(person('B_A', ['B_ED', 'LLB']).toJson() as Map<String, dynamic>);
    expect(back.otherDegrees, ['B_ED', 'LLB']);
    expect(UserProfileData.fromJson(person('B_A').toJson() as Map<String, dynamic>).otherDegrees, isEmpty);
  });
}
