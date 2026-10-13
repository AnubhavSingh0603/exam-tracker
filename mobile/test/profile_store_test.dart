import 'dart:convert';

import 'package:exam_tracker/models/user_profile.dart';
import 'package:exam_tracker/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final profile = UserProfileData(
    displayName: 'Me',
    dateOfBirth: DateTime(2000, 1, 1),
    category: ReservationCategory.obc,
    qualificationTier: 'UG',
    degreeTitle: 'B_TECH',
    experienceYears: 1,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('profiles saved before backups existed (bare JSON) still load, without a date', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile.cache', jsonEncode(profile.toJson()));
    final (loaded, savedAt) = await ProfileStore.readStamped();
    expect(loaded?.degreeTitle, 'B_TECH');
    expect(loaded?.category, ReservationCategory.obc);
    expect(savedAt, isNull);
  });

  test('new saves are stamped and round-trip', () async {
    final at = DateTime.utc(2026, 10, 13, 8);
    await ProfileStore.write(profile, savedAt: at);
    final (loaded, savedAt) = await ProfileStore.readStamped();
    expect(loaded?.experienceYears, 1);
    expect(savedAt, at);
    await ProfileStore.clear();
    expect(await ProfileStore.read(), isNull);
  });

  test('a corrupt entry reads as "no profile" instead of crashing', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile.cache', '{not json');
    expect(await ProfileStore.read(), isNull);
  });
}
