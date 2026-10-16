import 'package:flutter/foundation.dart';

/// One role from private_jobs.json (an employer's own job board).
@immutable
class PrivateJob {
  const PrivateJob({
    required this.id,
    required this.company,
    required this.title,
    required this.applyUrl,
    this.team,
    this.locations = const [],
    this.remote = false,
    this.employmentType = 'full_time',
    this.experienceMin,
    this.experienceMax,
    this.experienceFrom,
    this.skills = const [],
    this.salary,
    this.postedAt,
    this.summary = '',
  });

  final String id;
  final String company;
  final String title;
  final String? team;
  final List<String> locations;
  final bool remote;
  final String employmentType; // full_time | part_time | contract | internship
  final int? experienceMin;
  final int? experienceMax;

  /// 'text' (the posting says it), 'title' (guessed from "Senior…"), or null.
  final String? experienceFrom;
  final List<String> skills;
  final String? salary;
  final DateTime? postedAt;
  final String applyUrl;
  final String summary;

  /// "2–4 yrs", "5+ yrs", "Fresher", "Senior level", or null.
  String? get experienceLabel {
    final lo = experienceMin;
    if (lo == null) return null;
    if (experienceFrom == 'title') return lo == 0 ? 'Entry level' : 'Usually $lo+ yrs';
    if (lo == 0 && (experienceMax ?? 1) <= 1) return 'Fresher';
    final hi = experienceMax;
    return hi != null && hi > lo ? '$lo–$hi yrs' : '$lo+ yrs';
  }

  factory PrivateJob.fromJson(Map<String, dynamic> j) => PrivateJob(
        id: j['id'] as String,
        company: j['company'] as String? ?? '',
        title: j['title'] as String? ?? '',
        team: j['team'] as String?,
        locations: [for (final l in (j['locations'] as List<dynamic>? ?? const [])) l.toString()],
        remote: j['remote'] as bool? ?? false,
        employmentType: j['employment_type'] as String? ?? 'full_time',
        experienceMin: (j['experience_min'] as num?)?.toInt(),
        experienceMax: (j['experience_max'] as num?)?.toInt(),
        experienceFrom: j['experience_from'] as String?,
        skills: [for (final s in (j['skills'] as List<dynamic>? ?? const [])) s.toString()],
        salary: j['salary'] as String?,
        postedAt: DateTime.tryParse(j['posted_at'] as String? ?? ''),
        applyUrl: j['apply_url'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
      );
}

/// The private profile: kept apart from the Govt profile (its own encrypted entry),
/// so saving one never touches the other.
@immutable
class PrivateProfile {
  const PrivateProfile({
    this.headline = '',
    this.skills = const [],
    this.targetRoles = const [],
    this.experienceYears = 0,
    this.cities = const [],
    this.includeInternships = false,
    this.resumePath,
    this.resumeName,
    this.linkedinImportedAt,
  });

  final String headline;
  final List<String> skills;
  final List<String> targetRoles; // "Backend Engineer", "Data Analyst"
  final double experienceYears;
  final List<String> cities; // kPrivateCities names; empty = anywhere
  final bool includeInternships;
  final String? resumePath; // a copy kept in the app's own files
  final String? resumeName;
  final DateTime? linkedinImportedAt;

  bool get isEmpty => skills.isEmpty && targetRoles.isEmpty && headline.isEmpty;

  PrivateProfile copyWith({
    String? headline,
    List<String>? skills,
    List<String>? targetRoles,
    double? experienceYears,
    List<String>? cities,
    bool? includeInternships,
    String? resumePath,
    String? resumeName,
    DateTime? linkedinImportedAt,
  }) =>
      PrivateProfile(
        headline: headline ?? this.headline,
        skills: skills ?? this.skills,
        targetRoles: targetRoles ?? this.targetRoles,
        experienceYears: experienceYears ?? this.experienceYears,
        cities: cities ?? this.cities,
        includeInternships: includeInternships ?? this.includeInternships,
        resumePath: resumePath ?? this.resumePath,
        resumeName: resumeName ?? this.resumeName,
        linkedinImportedAt: linkedinImportedAt ?? this.linkedinImportedAt,
      );

  Map<String, Object?> toJson() => {
        'headline': headline,
        'skills': skills,
        'target_roles': targetRoles,
        'experience_years': experienceYears,
        'cities': cities,
        'include_internships': includeInternships,
        'resume_path': resumePath,
        'resume_name': resumeName,
        'linkedin_imported_at': linkedinImportedAt?.toUtc().toIso8601String(),
      };

  factory PrivateProfile.fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v) => [for (final s in (v as List<dynamic>? ?? const [])) s.toString()];
    return PrivateProfile(
      headline: j['headline'] as String? ?? '',
      skills: strings(j['skills']),
      targetRoles: strings(j['target_roles']),
      experienceYears: (j['experience_years'] as num?)?.toDouble() ?? 0,
      cities: strings(j['cities']),
      includeInternships: j['include_internships'] as bool? ?? false,
      resumePath: j['resume_path'] as String?,
      resumeName: j['resume_name'] as String?,
      linkedinImportedAt: DateTime.tryParse(j['linkedin_imported_at'] as String? ?? ''),
    );
  }
}

/// Private hiring stages. You move a card along yourself: no portal reports them.
enum PrivateStage {
  applied('applied', 'Applied'),
  screening('screening', 'Screening'),
  interview('interview', 'Interview'),
  offer('offer', 'Offer'),
  closed('closed', 'Not selected');

  const PrivateStage(this.wire, this.label);
  final String wire;
  final String label;

  static PrivateStage fromWire(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => applied);

  /// The four stops on the track (closed ends it early).
  static const track = [applied, screening, interview, offer];
}

@immutable
class PrivateApplication {
  const PrivateApplication({
    required this.id,
    required this.company,
    required this.title,
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    this.jobId,
    this.url,
    this.notes,
  });

  final String id;
  final String? jobId; // PrivateJob.id when applied from the feed
  final String company;
  final String title;
  final String? url;
  final PrivateStage stage;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PrivateApplication copyWith({PrivateStage? stage, String? notes, DateTime? updatedAt}) => PrivateApplication(
        id: id,
        jobId: jobId,
        company: company,
        title: title,
        url: url,
        stage: stage ?? this.stage,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'job_id': jobId,
        'company': company,
        'title': title,
        'url': url,
        'stage': stage.wire,
        'notes': notes,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
      };

  factory PrivateApplication.fromRow(Map<String, Object?> r) => PrivateApplication(
        id: r['id']! as String,
        jobId: r['job_id'] as String?,
        company: r['company']! as String,
        title: r['title']! as String,
        url: r['url'] as String?,
        stage: PrivateStage.fromWire(r['stage'] as String?),
        notes: r['notes'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int, isUtc: true),
      );
}

/// Skills the pipeline tags postings with (backend/app/modules/private_jobs/extract.py
/// SKILLS keys). Keep the two lists the same.
const kPrivateSkills = [
  'python', 'java', 'javascript', 'typescript', 'react', 'angular', 'vue', 'node', 'golang', 'rust', //
  'c++', 'c#', 'kotlin', 'swift', 'flutter', 'android', 'ios', 'sql', 'mongodb', 'redis', 'kafka', //
  'spark', 'airflow', 'snowflake', 'aws', 'gcp', 'azure', 'docker', 'kubernetes', 'terraform', //
  'linux', 'ci/cd', 'graphql', 'microservices', 'django', 'spring', 'machine learning', 'pytorch', //
  'tensorflow', 'llm', 'nlp', 'data science', 'data analysis', 'excel', 'power bi', 'tableau', //
  'figma', 'ui/ux', 'product management', 'sales', 'marketing', 'seo', 'content writing', //
  'customer support', 'finance', 'accounting', 'audit', 'hr', 'legal', 'operations', 'security', //
  'qa', 'devops', 'salesforce', 'sap',
];

/// Cities you can pick, with the names postings use for them.
const kPrivateCities = <String, List<String>>{
  'Bengaluru': ['bengaluru', 'bangalore'],
  'Hyderabad': ['hyderabad', 'secunderabad'],
  'Delhi NCR': ['delhi', 'gurugram', 'gurgaon', 'noida', 'faridabad', 'ghaziabad'],
  'Mumbai': ['mumbai', 'thane', 'navi mumbai'],
  'Pune': ['pune'],
  'Chennai': ['chennai'],
  'Kolkata': ['kolkata'],
  'Ahmedabad': ['ahmedabad', 'gandhinagar'],
  'Jaipur': ['jaipur'],
  'Kochi': ['kochi', 'cochin', 'trivandrum', 'thiruvananthapuram'],
};
