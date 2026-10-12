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

  test('JSON matches the backend UserProfileCreate schema', () {
    final profile = UserProfileData(
      displayName: '  ',
      dateOfBirth: DateTime(1998, 6, 5),
      category: ReservationCategory.sc,
      streams: ['B.Tech ECE', 'General Graduate'],
      isExServiceman: false,
      exServicemanServiceYears: 6, // ignored unless ex-serviceman
    );
    expect(profile.toJson(), {
      'display_name': 'Me',
      'date_of_birth': '1998-06-05',
      'category': 'SC',
      'streams': ['B.Tech ECE', 'General Graduate'],
      'is_pwbd': false,
      'is_ex_serviceman': false,
      'ex_serviceman_service_years': 0,
    });

    final back = UserProfileData.fromJson({...profile.toJson(), 'id': 'x'});
    expect(back.category, ReservationCategory.sc);
    expect(back.dateOfBirth, DateTime(1998, 6, 5));
    expect(back.isComplete, isTrue);
  });

  test('every stream preset is something the backend matcher recognises', () {
    // Mirrors backend/app/services/streams.py: each preset names a degree or "graduate".
    final recognised = RegExp(r'b\.?tech|m\.?tech|diploma|b\.?sc|b\.?com|bca|mba|graduate', caseSensitive: false);
    for (final preset in kStreamPresets) {
      expect(recognised.hasMatch(preset), isTrue, reason: preset);
    }
  });
}
