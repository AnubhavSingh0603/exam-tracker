import 'dart:convert';
import 'dart:io';

import 'package:exam_tracker/domain/eligibility.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart engine must reproduce every case recorded from the Python engine
/// (backend/scripts/make_parity_cases.py -> shared/eligibility_cases.json).
void main() {
  final file = File('../shared/eligibility_cases.json');
  final cases = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['cases'] as List<dynamic>;

  UserProfileData profile(Map<String, dynamic> j) => UserProfileData(
        displayName: 'Me',
        dateOfBirth: DateTime.parse(j['date_of_birth'] as String),
        category: ReservationCategory.fromWire(j['category'] as String)!,
        qualificationTier: j['qualification_tier'] as String,
        degreeTitle: j['degree_title'] as String,
        customQualificationText: j['custom_qualification_text'] as String?,
        experienceYears: (j['experience_years'] as num).toDouble(),
        isPwbd: j['is_pwbd'] as bool,
        isExServiceman: j['is_ex_serviceman'] as bool,
        exServicemanServiceYears: j['ex_serviceman_service_years'] as int,
      );

  for (final raw in cases) {
    final c = raw as Map<String, dynamic>;
    test(c['name'] as String, () {
      final post = PublishedPost.fromJson({'id': 'p', 'post_name': 'Post', ...c['post'] as Map<String, dynamic>});
      final r = evaluateEligibility(profile(c['profile'] as Map<String, dynamic>), post);
      final expect_ = c['expect'] as Map<String, dynamic>;
      final actual = {
        'match_kind': r.kind?.name,
        'is_eligible': r.isEligible,
        'qualification_match': r.qualificationMatch,
        'match_reason': r.matchReason?.wire,
        'eligible_via_relaxation': r.eligibleViaRelaxation,
        'effective_max_age': r.effectiveMaxAge,
        'relaxation_years': r.relaxationYears,
        'category_quota_seats': r.categoryQuotaSeats,
        'ur_open_seats': r.urOpenSeats,
        'total_reachable_seats': r.totalReachableSeats,
        'experience_gap_years': r.experienceGapYears,
      };
      expect(actual, {...expect_, 'experience_gap_years': (expect_['experience_gap_years'] as num).toDouble()});
    });
  }

  group('Others keyword search', () {
    const cases = {
      ('CA/CS', 'Qualified CA or ICWA'): true,
      ('B Des (Fashion)', 'B.Des from NIFT'): true,
      ('Bachelor of Design', 'Bachelor of Design (B.Des)'): true,
      ('BVSc', 'B.V.Sc & A.H.'): true,
      ('CA', 'Graduate with knowledge of Excel'): false,
      ('Bachelor', "Bachelor's degree in Engineering"): false,
    };
    cases.forEach((input, ok) {
      test('${input.$1} in "${input.$2}"', () => expect(customTextMatches(input.$1, [input.$2]), ok));
    });
  });
}
