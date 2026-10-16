import 'package:flutter/foundation.dart';

import '../domain/qualification_taxonomy.dart';

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

const kMinApplicantAge = 15;
const kMaxApplicantAge = 65;
const kMaxExperienceYears = 20.0;

int ageOn(DateTime dob, DateTime today) {
  var years = today.year - dob.year;
  if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) years--;
  return years;
}

/// null = valid; otherwise a short, kind message.
String? validateDob(DateTime? dob, DateTime today) {
  if (dob == null) return 'Pick your date of birth.';
  final age = ageOn(dob, today);
  if (age < kMinApplicantAge) {
    return 'That makes you $age. Applicants are usually at least $kMinApplicantAge.';
  }
  if (age > kMaxApplicantAge) return 'That makes you $age. Please double-check the year.';
  return null;
}

DegreeOption? degreeByCode(String? code) {
  for (final d in kDegrees) {
    if (d.code == code) return d;
  }
  return null;
}

QualificationLevel? levelByCode(String? code) {
  for (final l in kQualificationLevels) {
    if (l.code == code) return l;
  }
  return null;
}

/// "Fresher", "6 months", "2 years", "2.5 years".
String experienceLabel(double years) {
  if (years <= 0) return 'Fresher';
  if (years < 1) return '${(years * 12).round()} months';
  final y = years == years.roundToDouble() ? years.toInt().toString() : years.toStringAsFixed(1);
  return '$y year${years == 1 ? '' : 's'}';
}

@immutable
class UserProfileData {
  const UserProfileData({
    required this.displayName,
    required this.dateOfBirth,
    required this.category,
    required this.qualificationTier,
    required this.degreeTitle,
    this.customQualificationText,
    this.otherDegrees = const [],
    this.experienceYears = 0,
    this.isPwbd = false,
    this.isExServiceman = false,
    this.exServicemanServiceYears = 0,
  });

  final String displayName;
  final DateTime dateOfBirth;
  final ReservationCategory category;

  /// `QualificationLevel.code` (MATRIC … PHD).
  final String qualificationTier;

  /// `DegreeOption.code`, or [kOthersDegreeCode].
  final String degreeTitle;
  final String? customQualificationText;

  /// Further degrees held besides [degreeTitle] (`DegreeOption.code`s): a B.Ed on
  /// top of a B.Sc, an LL.B after a B.A. Jobs can ask for any of them.
  final List<String> otherDegrees;

  /// Every degree you hold: the main one and the others.
  List<String> get allDegrees => [degreeTitle, ...otherDegrees.where((d) => d != degreeTitle)];
  final double experienceYears;
  final bool isPwbd;
  final bool isExServiceman;
  final int exServicemanServiceYears;

  bool get isOthers => degreeTitle == kOthersDegreeCode;

  /// Profiles saved before the degree picker existed have no degree: ask again.
  bool get isComplete =>
      levelByCode(qualificationTier) != null &&
      (isOthers ? (customQualificationText?.trim().length ?? 0) >= 2 : degreeByCode(degreeTitle) != null);

  /// "B.Tech / B.E." or the user's own text for Others, plus the other degrees
  /// ("B.Sc + B.Ed").
  String get qualificationLabel => [
        isOthers ? (customQualificationText ?? 'Other') : (degreeByCode(degreeTitle)?.label ?? degreeTitle),
        for (final d in otherDegrees)
          if (d != degreeTitle) degreeByCode(d)?.label ?? d,
      ].join(' + ');

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Matches the backend's `UserProfileCreate`.
  Map<String, Object?> toJson() => {
        'display_name': displayName.trim().isEmpty ? 'Me' : displayName.trim(),
        'date_of_birth': _date(dateOfBirth),
        'category': category.wire,
        'qualification_tier': qualificationTier,
        'degree_title': degreeTitle,
        'custom_qualification_text': isOthers ? customQualificationText?.trim() : null,
        if (otherDegrees.isNotEmpty) 'other_degrees': otherDegrees,
        'experience_years': experienceYears,
        'is_pwbd': isPwbd,
        'is_ex_serviceman': isExServiceman,
        'ex_serviceman_service_years': isExServiceman ? exServicemanServiceYears : 0,
      };

  factory UserProfileData.fromJson(Map<String, dynamic> j) => UserProfileData(
        displayName: j['display_name'] as String? ?? '',
        dateOfBirth: DateTime.parse(j['date_of_birth'] as String),
        category: ReservationCategory.fromWire(j['category'] as String?) ?? ReservationCategory.ur,
        qualificationTier: j['qualification_tier'] as String? ?? '',
        degreeTitle: j['degree_title'] as String? ?? '',
        customQualificationText: j['custom_qualification_text'] as String?,
        otherDegrees: [for (final d in (j['other_degrees'] as List<dynamic>? ?? const [])) d.toString()],
        experienceYears: (j['experience_years'] as num?)?.toDouble() ?? 0,
        isPwbd: j['is_pwbd'] as bool? ?? false,
        isExServiceman: j['is_ex_serviceman'] as bool? ?? false,
        exServicemanServiceYears: (j['ex_serviceman_service_years'] as num?)?.toInt() ?? 0,
      );
}
