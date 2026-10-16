import 'package:flutter/foundation.dart';

import 'models.dart';

/// How a role fits the private profile: a score for ordering, the skills you share,
/// and why it's hidden (shown in "N hidden" so nothing disappears silently).
@immutable
class PrivateMatch {
  const PrivateMatch(this.job, {required this.score, this.sharedSkills = const [], this.hiddenBecause});

  final PrivateJob job;
  final double score;
  final List<String> sharedSkills;
  final String? hiddenBecause;
}

const _stop = {'and', 'the', 'for', 'of', 'in', 'with', 'senior', 'junior', 'sr', 'jr', 'lead', 'i', 'ii', 'iii'};

List<String> _words(String s) => [
      for (final w in s.toLowerCase().split(RegExp(r'[^a-z0-9+#]+')))
        if (w.length >= 2 && !_stop.contains(w)) w
    ];

/// A target role names this job when all its words are in the title ("backend
/// engineer" ~ "Senior Backend Engineer, Payments").
bool roleMatches(String title, String role) {
  final words = _words(role);
  final have = _words(title).toSet();
  return words.isNotEmpty && words.every(have.contains);
}

bool inYourCities(PrivateJob job, List<String> cities) {
  if (cities.isEmpty || job.remote) return true;
  final where = job.locations.join(' ').toLowerCase();
  // "India" alone (or no city at all) means anywhere in the country.
  if (where.trim().isEmpty || RegExp(r'^\W*india\W*$').hasMatch(where)) return true;
  for (final city in cities) {
    if (city == 'Remote') continue;
    if ((kPrivateCities[city] ?? [city.toLowerCase()]).any(where.contains)) return true;
  }
  return false;
}

PrivateMatch matchPrivateJob(PrivateJob job, PrivateProfile me, DateTime now) {
  final shared = [for (final s in job.skills) if (me.skills.contains(s)) s];
  final roleHit = me.targetRoles.any((r) => roleMatches(job.title, r));

  String? hidden;
  final needs = job.experienceMin;
  if (!me.includeInternships && job.employmentType == 'internship') {
    hidden = 'Internship';
  } else if (needs != null && needs > me.experienceYears + 1) {
    // One year of stretch is fine to apply for; more usually isn't.
    hidden = 'Needs $needs+ years';
  } else if (me.cities.isNotEmpty && !inYourCities(job, me.cities) &&
      !(me.cities.contains('Remote') && job.remote)) {
    hidden = 'Not in your cities';
  } else if (!me.isEmpty && shared.isEmpty && !roleHit) {
    hidden = 'Not your field';
  }

  var score = shared.length * 2.0 + (roleHit ? 3 : 0);
  if (needs != null && needs <= me.experienceYears && needs >= me.experienceYears - 2) score += 1; // a level that fits
  final age = job.postedAt == null ? null : now.difference(job.postedAt!).inDays;
  if (age != null) score += age <= 7 ? 1 : (age <= 30 ? 0.5 : 0);
  return PrivateMatch(job, score: score, sharedSkills: shared, hiddenBecause: hidden);
}

/// Shown best first; hidden ones separately, with their reasons.
({List<PrivateMatch> shown, List<PrivateMatch> hidden}) rankPrivateJobs(
  Iterable<PrivateJob> jobs,
  PrivateProfile me,
  DateTime now, {
  Set<String> dismissed = const {},
}) {
  final shown = <PrivateMatch>[];
  final hidden = <PrivateMatch>[];
  for (final job in jobs) {
    if (dismissed.contains(job.id)) continue;
    final m = matchPrivateJob(job, me, now);
    (m.hiddenBecause == null ? shown : hidden).add(m);
  }
  shown.sort((a, b) {
    final s = b.score.compareTo(a.score);
    return s != 0 ? s : (b.job.postedAt ?? DateTime(0)).compareTo(a.job.postedAt ?? DateTime(0));
  });
  return (shown: shown, hidden: hidden);
}

/// LinkedIn's own job search, opened in the user's browser and LinkedIn session: the
/// full LinkedIn results without any scraping. Experience filter f_E: 1 internship,
/// 2 entry, 3 associate, 4 mid-senior.
Uri linkedInSearch(PrivateProfile me) {
  final keywords = me.targetRoles.isNotEmpty ? me.targetRoles.first : (me.skills.take(2).join(' '));
  final city = me.cities.firstWhere((c) => c != 'Remote', orElse: () => 'India');
  final level = me.experienceYears < 1 ? '1,2' : (me.experienceYears < 3 ? '2,3' : '3,4');
  return Uri.https('www.linkedin.com', '/jobs/search/', {
    if (keywords.isNotEmpty) 'keywords': keywords,
    'location': city == 'Delhi NCR' ? 'Delhi, India' : (city == 'India' ? 'India' : '$city, India'),
    'f_E': level,
  });
}
