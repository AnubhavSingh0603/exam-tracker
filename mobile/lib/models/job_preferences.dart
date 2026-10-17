import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile.dart';

/// The pipeline's job groups (`category` in jobs.json).
enum JobCategory {
  railway('railway', 'Railway'),
  bank('bank', 'Banks'),
  ssc('ssc', 'SSC'),
  upsc('upsc', 'UPSC'),
  psu('psu', 'PSU'),
  research('research', 'Research / JRF'),
  defence('defence', 'Defence & Police'),
  state('state', 'State govt'),
  teaching('teaching', 'Teaching'),
  medical('medical', 'Medical'),
  court('court', 'Courts & Legal'),
  other('other', 'Other');

  const JobCategory(this.wire, this.label);
  final String wire;
  final String label;

  static JobCategory fromWire(String? v) =>
      values.firstWhere((c) => c.wire == v, orElse: () => JobCategory.other);
}

/// Languages a post can demand ("Marathi Teacher", "knowledge of Tamil").
const kIndianLanguages = [
  'Hindi',
  'English',
  'Assamese',
  'Bengali',
  'Bodo',
  'Dogri',
  'Gujarati',
  'Kannada',
  'Kashmiri',
  'Konkani',
  'Maithili',
  'Malayalam',
  'Manipuri',
  'Marathi',
  'Nepali',
  'Odia',
  'Punjabi',
  'Sanskrit',
  'Santali',
  'Sindhi',
  'Tamil',
  'Telugu',
  'Urdu',
]; // dart format off

/// What the user wants to see in Jobs. Hidden categories, unknown languages and
/// (for graduates) 10th-pass-only posts are filtered out; preferred categories
/// and higher pay rank first.
@immutable
class JobPreferences {
  const JobPreferences({
    this.preferred = const {},
    this.hidden = const {},
    this.languages = const {'Hindi', 'English'},
    this.hideBelowMyLevel = true,
    this.minMonthlyPay = 0,
    this.hiddenTypes = const {},
    this.qualifications = const {},
    this.savedAt,
    this.subjects = const {},
    this.degreesHeld = const {},
  });

  final Set<JobCategory> preferred;
  final Set<JobCategory> hidden;
  final Set<String> languages;

  /// Graduates don't see posts that need only 10th pass or less (peon, chowkidar…).
  final bool hideBelowMyLevel;

  /// 0 = no minimum. Jobs that don't say their pay are kept.
  final int minMonthlyPay;

  /// e.g. {'apprenticeship', 'internship'}.
  final Set<String> hiddenTypes;

  /// Professional qualifications you have (Profession keys: 'teaching', 'tet',
  /// 'nursing', 'doctor'…). Posts that need one you don't have are hidden. Ones
  /// your profile's degree already shows count too (qualificationsFromProfile).
  final Set<String> qualifications;
  final DateTime? savedAt;

  /// Branches and subjects picked per degree group (`SubjectGroup.key`); empty =
  /// no subject filter. From the profile, never saved here.
  final Map<String, SubjectChoice> subjects;

  /// Every degree code the profile holds (an M.Tech holds the B.Tech too). From the
  /// profile, never saved here.
  final Set<String> degreesHeld;

  static const defaults = JobPreferences();

  JobPreferences copyWith({
    Set<JobCategory>? preferred,
    Set<JobCategory>? hidden,
    Set<String>? languages,
    bool? hideBelowMyLevel,
    int? minMonthlyPay,
    Set<String>? hiddenTypes,
    Set<String>? qualifications,
    DateTime? savedAt,
    Map<String, SubjectChoice>? subjects,
    Set<String>? degreesHeld,
  }) =>
      JobPreferences(
        preferred: preferred ?? this.preferred,
        hidden: hidden ?? this.hidden,
        languages: languages ?? this.languages,
        hideBelowMyLevel: hideBelowMyLevel ?? this.hideBelowMyLevel,
        minMonthlyPay: minMonthlyPay ?? this.minMonthlyPay,
        hiddenTypes: hiddenTypes ?? this.hiddenTypes,
        qualifications: qualifications ?? this.qualifications,
        savedAt: savedAt ?? this.savedAt,
        subjects: subjects ?? this.subjects,
        degreesHeld: degreesHeld ?? this.degreesHeld,
      );

  Map<String, dynamic> toJson() => {
        'preferred': [for (final c in preferred) c.wire],
        'hidden': [for (final c in hidden) c.wire],
        'languages': languages.toList(),
        'hide_below_my_level': hideBelowMyLevel,
        'min_monthly_pay': minMonthlyPay,
        'hidden_types': hiddenTypes.toList(),
        'qualifications': qualifications.toList(),
        if (savedAt != null) 'saved_at': savedAt!.toUtc().toIso8601String(),
      };

  factory JobPreferences.fromJson(Map<String, dynamic> j) {
    Set<String> strings(Object? v) => {for (final s in (v as List<dynamic>? ?? const [])) s.toString()};
    return JobPreferences(
      preferred: {for (final s in strings(j['preferred'])) JobCategory.fromWire(s)},
      hidden: {for (final s in strings(j['hidden'])) JobCategory.fromWire(s)},
      languages: j['languages'] == null ? defaults.languages : strings(j['languages']),
      hideBelowMyLevel: j['hide_below_my_level'] as bool? ?? true,
      minMonthlyPay: (j['min_monthly_pay'] as num?)?.toInt() ?? 0,
      hiddenTypes: strings(j['hidden_types']),
      qualifications: strings(j['qualifications']),
      savedAt: DateTime.tryParse(j['saved_at'] as String? ?? ''),
    );
  }
}

/// SharedPreferences storage (also carried in the Drive backup).
abstract final class JobPreferencesStore {
  static const _key = 'prefs.jobs';

  static Future<JobPreferences> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return JobPreferences.defaults;
      return JobPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return JobPreferences.defaults;
    }
  }

  static Future<void> write(JobPreferences prefs) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(prefs.toJson()));
}
