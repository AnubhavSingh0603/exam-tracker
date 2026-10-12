import 'package:flutter/foundation.dart';

/// Wire values match the backend's `Category` enum.
enum ReservationCategory {
  ur('UR', 'UR (General / Unreserved)'),
  sc('SC', 'SC'),
  st('ST', 'ST'),
  obc('OBC', 'OBC (Non-Creamy Layer)'),
  ews('EWS', 'EWS');

  const ReservationCategory(this.wire, this.label);
  final String wire;
  final String label;

  static ReservationCategory? fromWire(String? v) {
    for (final c in values) {
      if (c.wire == v) return c;
    }
    return null;
  }
}

/// Labels the backend's stream matcher understands (see backend/app/services/streams.py):
/// "B.Tech ECE" matches "B.E. (Electronics & Communication)", "General Graduate" matches
/// "Any Graduate", and so on.
const kStreamPresets = <String>[
  'B.Tech ECE',
  'B.Tech EE',
  'B.Tech EEE',
  'B.Tech CSE',
  'B.Tech IT',
  'B.Tech Mechanical',
  'B.Tech Civil',
  'B.Tech Chemical',
  'B.Tech Instrumentation',
  'M.Tech',
  'Diploma Civil',
  'Diploma Mechanical',
  'Diploma Electrical',
  'Diploma Electronics',
  'B.Sc',
  'B.Com',
  'BCA',
  'MBA',
  'General Graduate',
];

const kMinApplicantAge = 15;
const kMaxApplicantAge = 65;

int ageOn(DateTime dob, DateTime today) {
  var years = today.year - dob.year;
  if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) years--;
  return years;
}

/// null = valid; otherwise a short, kind message.
String? validateDob(DateTime? dob, DateTime today) {
  if (dob == null) return 'Pick your date of birth.';
  final age = ageOn(dob, today);
  if (age < kMinApplicantAge) return 'That makes you $age. Applicants are usually at least $kMinApplicantAge.';
  if (age > kMaxApplicantAge) return 'That makes you $age. Please double-check the year.';
  return null;
}

@immutable
class UserProfileData {
  const UserProfileData({
    required this.displayName,
    required this.dateOfBirth,
    required this.category,
    required this.streams,
    this.isPwbd = false,
    this.isExServiceman = false,
    this.exServicemanServiceYears = 0,
  });

  final String displayName;
  final DateTime dateOfBirth;
  final ReservationCategory category;
  final List<String> streams;
  final bool isPwbd;
  final bool isExServiceman;
  final int exServicemanServiceYears;

  bool get isComplete => streams.isNotEmpty;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Matches the backend's `UserProfileCreate`.
  Map<String, Object?> toJson() => {
        'display_name': displayName.trim().isEmpty ? 'Me' : displayName.trim(),
        'date_of_birth': _date(dateOfBirth),
        'category': category.wire,
        'streams': streams,
        'is_pwbd': isPwbd,
        'is_ex_serviceman': isExServiceman,
        'ex_serviceman_service_years': isExServiceman ? exServicemanServiceYears : 0,
      };

  factory UserProfileData.fromJson(Map<String, dynamic> j) => UserProfileData(
        displayName: j['display_name'] as String? ?? '',
        dateOfBirth: DateTime.parse(j['date_of_birth'] as String),
        category: ReservationCategory.fromWire(j['category'] as String?) ?? ReservationCategory.ur,
        streams: [for (final s in (j['streams'] as List<dynamic>? ?? const [])) s.toString()],
        isPwbd: j['is_pwbd'] as bool? ?? false,
        isExServiceman: j['is_ex_serviceman'] as bool? ?? false,
        exServicemanServiceYears: (j['ex_serviceman_service_years'] as num?)?.toInt() ?? 0,
      );
}
