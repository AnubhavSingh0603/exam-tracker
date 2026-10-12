import 'package:exam_tracker/domain/qualification_taxonomy.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 11);

  group('age validation', () {
    test('birthday later this year is not counted yet', () {
      expect(ageOn(DateTime(1998, 12, 1), today), 27);
      expect(ageOn(DateTime(1998, 10, 11), today), 28);
    });

    test('kind messages for missing / implausible dates', () {
      expect(validateDob(null, today), contains('Pick'));
      expect(validateDob(DateTime(2015, 1, 1), today), contains('at least'));
      expect(validateDob(DateTime(1950, 1, 1), today), contains('double-check'));
      expect(validateDob(DateTime(1998, 6, 15), today), isNull);
    });
  });

  UserProfileData profile({String tier = 'UG', String degree = 'B_TECH', String? custom}) => UserProfileData(
        displayName: '  ',
        dateOfBirth: DateTime(1998, 6, 5),
        category: ReservationCategory.sc,
        qualificationTier: tier,
        degreeTitle: degree,
        customQualificationText: custom,
        experienceYears: 1.5,
        exServicemanServiceYears: 6, // ignored unless ex-serviceman
      );

  test('JSON matches the backend UserProfileCreate schema', () {
    expect(profile().toJson(), {
      'display_name': 'Me',
      'date_of_birth': '1998-06-05',
      'category': 'SC',
      'qualification_tier': 'UG',
      'degree_title': 'B_TECH',
      'custom_qualification_text': null,
      'experience_years': 1.5,
      'is_pwbd': false,
      'is_ex_serviceman': false,
      'ex_serviceman_service_years': 0,
    });

    final back = UserProfileData.fromJson({...profile().toJson(), 'id': 'x'});
    expect(back.category, ReservationCategory.sc);
    expect(back.dateOfBirth, DateTime(1998, 6, 5));
    expect(back.experienceYears, 1.5);
    expect(back.isComplete, isTrue);
    expect(back.qualificationLabel, 'B.Tech / B.E.');
  });

  test('Others needs its own text, which is sent trimmed', () {
    expect(profile(degree: kOthersDegreeCode).isComplete, isFalse);
    final others = profile(degree: kOthersDegreeCode, custom: '  B.Des ');
    expect(others.isComplete, isTrue);
    expect(others.toJson()['custom_qualification_text'], 'B.Des');
    expect(others.qualificationLabel, '  B.Des ');
  });

  test('profiles saved before the degree picker ask to be completed', () {
    final old = UserProfileData.fromJson({
      'display_name': 'Me',
      'date_of_birth': '1998-06-05',
      'category': 'UR',
      'streams': ['B.Tech ECE'],
    });
    expect(old.isComplete, isFalse);
  });

  test('every degree belongs to a known level and codes are unique', () {
    final levels = {for (final l in kQualificationLevels) l.code};
    expect(kDegrees.map((d) => d.code).toSet().length, kDegrees.length);
    for (final d in kDegrees) {
      expect(levels, contains(d.level), reason: d.code);
    }
  });

  test('experience labels', () {
    expect(experienceLabel(0), 'Fresher');
    expect(experienceLabel(0.5), '6 months');
    expect(experienceLabel(1), '1 year');
    expect(experienceLabel(2.5), '2.5 years');
  });
}
