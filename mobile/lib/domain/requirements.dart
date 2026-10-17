import 'package:flutter/foundation.dart';

import '../models/feed.dart';
import '../models/job_preferences.dart';
import '../models/jobs_data.dart';
import '../models/user_profile.dart';
import 'subjects.dart';

/// Professional qualifications a post can need on top of a degree. The pipeline's
/// "open to any graduate" flag, or a post with no degree listed, lets these through
/// to everyone ("Graduate with D.El.Ed and CTET", "Staff Nurse", "Pharmacist").
enum Profession {
  teaching('teaching', 'Teacher training (B.Ed / D.El.Ed / BTC / B.P.Ed)', 'B.Ed / D.El.Ed'),
  tet('tet', 'Teacher eligibility test (CTET / TET)', 'CTET / TET'),
  nursing('nursing', 'Nursing (ANM / GNM / B.Sc Nursing)', 'a nursing qualification'),
  doctor('doctor', 'Doctor (MBBS / BDS / AYUSH)', 'a medical degree'),
  pharmacy('pharmacy', 'Pharmacy (D.Pharm / B.Pharm)', 'a pharmacy qualification'),
  lab('lab', 'Lab / paramedical (DMLT / X-ray / OT)', 'a lab / paramedical course'),
  physio('physio', 'Physiotherapy (BPT)', 'physiotherapy'),
  law('law', 'Law (LL.B)', 'a law degree');

  const Profession(this.key, this.label, this.needs);

  /// Stored in [JobPreferences.qualifications].
  final String key;
  final String label;

  /// "Needs …" in the hidden-jobs list.
  final String needs;
}

/// What a post's name and qualification text ask for beyond the degree.
@immutable
class ExtraRequirements {
  const ExtraRequirements({this.professions = const {}, this.languages = const [], this.subjects});

  final Set<Profession> professions;

  /// Each set is one requirement, met by any language in it ("Marathi or Hindi").
  final List<Set<String>> languages;

  /// The branches or subjects the post asks for, per degree group.
  final PostSubjects? subjects;

  bool get teachingDegree => professions.contains(Profession.teaching);
  bool get tet => professions.contains(Profession.tet);
  bool get isEmpty => professions.isEmpty && languages.isEmpty;
}

RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

// B.Ed and D.Ed need their dot or space, so a "100 bed hospital" is not a B.Ed.
const _teachingDegree = r'b(?:\.\s?|\s)ed\.?|b\.?\s?el\.?\s?ed\.?|d\.?\s?el\.?\s?ed\.?|b\.?\s?t\.?\s?c\.?|d(?:\.\s?|\s)ed\.?'
    r'|j\.?\s?b\.?\s?t\.?|n\.?\s?t\.?\s?t\.?|b\.?\s?p\.?\s?ed\.?|m\.?\s?p\.?\s?ed\.?|teacher training|teaching qualification'
    r'|b\.?\s?a\.?\s?ed\.?|b\.?\s?sc\.?\s?ed\.?';
final _teachingRe = _re('(?<![a-z])(?:$_teachingDegree)(?![a-z])');
final _tetRe = _re(r'(?<![a-z])(?:c\.?\s?tet|s\.?\s?tet|tet|teacher eligibility test)(?![a-z])');

/// A profession recognised from the post's name and the qualification text. Both
/// must agree, so "Food Safety Officer: any science degree, MBBS…" or "Accounts
/// Assistant: Commerce / MBA / CA Inter" stay open. A few names need nothing
/// else ("Staff Nurse", "Pharmacist", "Medical Officer").
class _Rule {
  const _Rule(this.profession, {required this.name, required this.text, this.nameAlone});

  final Profession profession;
  final RegExp name;
  final RegExp text;
  final RegExp? nameAlone;

  bool applies(String postName, String qualification) =>
      name.hasMatch(postName) &&
      ((nameAlone?.hasMatch(postName) ?? false) || (qualification.isNotEmpty && _required(qualification, text)));
}

final _rules = [
  _Rule(
    Profession.nursing,
    name: _re(r'\b(?:nurs\w*|anm|gnm|midwi\w*)\b'),
    nameAlone: _re(r'\b(?:staff nurse|nursing officer|nurse|anm|gnm|midwife)\b'),
    text: _re(r'(?<![a-z])(?:a\.?\s?n\.?\s?m\.?|g\.?\s?n\.?\s?m\.?)(?![a-z])|b\.?\s?sc\.?\s*\(?\s*nursing|nursing council'
        r'|registered (?:nurse|midwife)|auxiliary nurs\w*|general nursing|diploma in nursing|nurs\w* (?:&|and) midwi\w*'
        r'|post basic'),
  ),
  _Rule(
    Profession.doctor,
    name: _re(r'\b(?:medical officer|doctor|surgeon|physician|dentist|dental|gyn\w*|p(?:a)?ediatric\w*|an(?:a)?esthe\w*'
        r'|radiologist|pathologist|psychiatrist|orthop\w*|senior resident|junior resident|ayush|ayurved\w*'
        r'|homo?eopath\w*|unani|siddha)\b'),
    nameAlone: _re(r'\b(?:medical officer|doctor|surgeon|physician|dentist|senior resident|junior resident)\b'),
    text: _re(r'(?<![a-z])(?:m\.?\s?b\.?\s?b\.?\s?s|b\.?\s?d\.?\s?s|b\.?\s?a\.?\s?m\.?\s?s|b\.?\s?h\.?\s?m\.?\s?s|b\.?\s?u\.?\s?m\.?\s?s'
        r'|b\.?\s?s\.?\s?m\.?\s?s|bnys|nmc|mci|medical council|dental council|ayush)(?![a-z])'),
  ),
  _Rule(
    Profession.pharmacy,
    name: _re(r'\b(?:pharmac\w*|dispenser)\b'),
    nameAlone: _re(r'\bpharmacist\b'),
    text: _re(r'(?<![a-z])(?:d\.?\s?pharm\w*|b\.?\s?pharm\w*|m\.?\s?pharm\w*|pharm\.?\s?d)(?![a-z])|pharmacy council'
        r'|registered pharmacist|(?:diploma|degree|bachelor\w*) (?:degree )?in pharmacy'),
  ),
  _Rule(
    Profession.lab,
    name: _re(r'\b(?:lab\w*|technician|technologist|radiograph\w*|x-?ray|optometr\w*|dialysis|paramedic\w*|ecg)\b'),
    text: _re(r'(?<![a-z])(?:d\.?\s?m\.?\s?l\.?\s?t|b\.?\s?m\.?\s?l\.?\s?t|m\.?\s?l\.?\s?t)(?![a-z])|medical lab\w*'
        r'|lab(?:oratory)? technolog\w*|paramedical|radiograph\w*|x-?ray technician|operation theatre|optometr\w*'
        r'|dialysis technician|perfusion'),
  ),
  _Rule(
    Profession.physio,
    name: _re(r'\bphysio\w*'),
    nameAlone: _re(r'\bphysiotherapist\b'),
    text: _re(r'(?<![a-z])(?:b\.?\s?p\.?\s?t|m\.?\s?p\.?\s?t)(?![a-z])|physiotherap\w*'),
  ),
  _Rule(
    Profession.law,
    name: _re(r'\b(?:legal|law|advocate|prosecutor|judicial|judge|munsi\w*|notary)\b'),
    text: _re(r"(?<![a-z])(?:ll\.?\s?b|ll\.?\s?m)(?![a-z])|bar council|degree in law|law graduate|enrolled as an? advocate"
        r"|bachelor'?s?\s+(?:degree\s+)?(?:in|of)\s+laws?"),
  ),
];

// "Preferably B.Ed", "B.Ed (desirable)", "DMLT preferred": nice to have, not needed.
final _optionalBefore = _re(r'(?:preferabl\w*|desirabl\w*)\W+(?:[\w.]+\W+){0,2}$');
final _optionalAfter = _re(r'^\W+(?:[\w.]+\W+)?(?:desirabl|preferr|preferabl|will be an advantage)');

bool _required(String text, RegExp what) {
  for (final m in what.allMatches(text)) {
    final before = text.substring((m.start - 30).clamp(0, m.start), m.start);
    final after = text.substring(m.end, (m.end + 25).clamp(m.end, text.length));
    if (!_optionalBefore.hasMatch(before) && !_optionalAfter.hasMatch(after)) return true;
  }
  return false;
}

const _languageNames = [...kIndianLanguages, 'Oriya'];
final _lang = _languageNames.join('|');
final _langList = '((?:$_lang)(?:\\W+(?:and|or|&|/|,)?\\W*(?:$_lang))*)';

/// Phrases that make a language a must ("knowledge of Konkani", "passed with Marathi
/// subject", "Marathi medium", "speak, read and write Odia"). Group 1 is the list.
final _languagePhrases = [
  _re('(?:knowledge|proficiency|command|fluency)\\s+(?:of|in)\\s+(?:the\\s+)?$_langList'),
  _re('(?:passed|pass)\\s+(?:with|in)\\s+$_langList'),
  _re('with\\s+$_langList\\s+(?:as\\s+(?:a\\s+)?)?(?:subject|language)'),
  _re('$_langList\\s+(?:language\\s+)?(?:is\\s+)?(?:compulsory|mandatory|essential)'),
  _re('$_langList\\s+medium'),
  _re('(?:read|write|speak)[\\w ,]{0,40}?\\b$_langList'),
];
final _oneLanguage = _re('\\b($_lang)\\b');
final _optionalNear = _re(r'desirabl|preferabl|preferred|advantage');

String _canonical(String name) {
  final lower = name.toLowerCase();
  if (lower == 'oriya') return 'Odia';
  return _languageNames.firstWhere((l) => l.toLowerCase() == lower);
}

List<Set<String>> _requiredLanguages(String text) {
  final groups = <Set<String>>[];
  for (final re in _languagePhrases) {
    for (final m in re.allMatches(text)) {
      final around = text.substring((m.start - 25).clamp(0, m.start), (m.end + 25).clamp(m.end, text.length));
      if (_optionalNear.hasMatch(around)) continue;
      final list = m.group(1)!;
      final names = {for (final l in _oneLanguage.allMatches(list)) _canonical(l.group(1)!)};
      if (names.isEmpty) continue;
      // "Marathi or Hindi" / "Marathi/Hindi": either will do. "Marathi & English": both.
      if (_re(r'\bor\b|/').hasMatch(list)) {
        groups.add(names);
      } else {
        for (final n in names) {
          groups.add({n});
        }
      }
    }
  }
  return groups;
}

/// What one post asks for beyond the degree.
ExtraRequirements requirementsOf(PublishedPost post) {
  final text = [post.qualificationText, post.rawEligibilityText].whereType<String>().join(' ');
  return ExtraRequirements(
    professions: {
      if (text.isNotEmpty && _required(text, _teachingRe)) Profession.teaching,
      if (text.isNotEmpty && _required(text, _tetRe)) Profession.tet,
      for (final rule in _rules)
        if (rule.applies(post.postName, text)) rule.profession,
    },
    languages: text.isEmpty ? const [] : _requiredLanguages(text),
    subjects: subjectsOf(post),
  );
}

/// The first requirement this post has that you don't, as a short reason
/// ("Needs B.Ed / D.El.Ed", "Needs Marathi"), or null when you meet them all.
String? unmetRequirement(ExtraRequirements r, JobPreferences prefs) {
  for (final p in Profession.values) {
    if (r.professions.contains(p) && !prefs.qualifications.contains(p.key)) return 'Needs ${p.needs}';
  }
  for (final group in r.languages) {
    if (group.intersection(prefs.languages).isEmpty) return 'Needs ${group.join(' or ')}';
  }
  final fit = subjectFit(r.subjects, prefs);
  if (fit?.verdict == SubjectVerdict.other) return fit!.reason;
  return null;
}

/// What to check on a job you'd see when one of its posts doesn't say which
/// branch or subject it wants ("branch", "subject", "trade"), or null.
String? subjectUnclear(FeedItem item, JobPreferences prefs) {
  if (prefs.subjects.isEmpty) return null;
  final published = {for (final p in item.job?.posts ?? const <PublishedPost>[]) p.id: p};
  for (final post in item.posts.isEmpty ? [item.bestPost] : item.posts) {
    final p = published[post.postDetailId];
    if (p == null) continue;
    final fit = subjectFit(requirementsOf(p).subjects, prefs);
    if (fit?.verdict == SubjectVerdict.unclear) return fit!.noun;
  }
  return null;
}

/// Why none of this job's posts suit you, or null if at least one does. Every post
/// you'd see must fail, so a job with one post you can apply for always stays.
String? unmetRequirementForJob(FeedItem item, JobPreferences prefs) {
  final published = {for (final p in item.job?.posts ?? const <PublishedPost>[]) p.id: p};
  String? first;
  for (final post in item.posts.isEmpty ? [item.bestPost] : item.posts) {
    final p = published[post.postDetailId];
    if (p == null) return null; // nothing to read: keep it
    final reason = unmetRequirement(requirementsOf(p), prefs);
    if (reason == null) return null;
    first ??= reason;
  }
  return first;
}

/// The job with only the posts whose extra requirements you meet, so a health
/// office hiring a Pharmacist, an ANM and a clerk shows you the clerk. Unchanged
/// when every post (or none) fits; a job where none fit is hidden instead.
FeedItem keepPostsYouMeet(FeedItem item, JobPreferences prefs) {
  if (item.posts.length < 2) return item;
  final published = {for (final p in item.job?.posts ?? const <PublishedPost>[]) p.id: p};
  final kept = [
    for (final post in item.posts)
      if (published[post.postDetailId] case final p
          when p == null || unmetRequirement(requirementsOf(p), prefs) == null)
        post,
  ];
  return kept.isEmpty || kept.length == item.posts.length ? item : item.withPosts(kept);
}

/// Professional qualifications your profile already shows: the degree you picked
/// (B.Ed, LL.B, B.Pharm, MBBS…) or what you typed under "Others" (GNM, BAMS, DMLT…).
Set<String> qualificationsFromProfile(UserProfileData? profile) {
  if (profile == null) return const {};
  final found = <String>{
    for (final degree in profile.allDegrees)
      ...switch (degree) {
        'B_ED' || 'M_ED' => {Profession.teaching.key},
        'LLB' || 'LLM' => {Profession.law.key},
        'B_PHARM' || 'M_PHARM' => {Profession.pharmacy.key},
        'MBBS' || 'MD_MS' => {Profession.doctor.key},
        _ => const <String>{},
      },
  };
  final typed = profile.customQualificationText ?? '';
  if (typed.trim().isEmpty) return found;
  final byText = {
    Profession.teaching: _teachingRe,
    Profession.tet: _tetRe,
    Profession.nursing: _re(r'(?<![a-z])(?:a\.?\s?n\.?\s?m|g\.?\s?n\.?\s?m)(?![a-z])|nursing|midwi'),
    Profession.doctor: _re(r'(?<![a-z])(?:mbbs|bds|bams|bhms|bums|bsms|bnys|md|ayush)(?![a-z])'),
    Profession.pharmacy: _re(r'pharm'),
    Profession.lab: _re(r'(?<![a-z])(?:dmlt|bmlt|mlt)(?![a-z])|paramedical|radiograph|lab technolog|optometr'),
    Profession.physio: _re(r'(?<![a-z])(?:bpt|mpt)(?![a-z])|physiotherap'),
    Profession.law: _re(r'(?<![a-z])(?:llb|ll\.b|llm)(?![a-z])|\blaw\b'),
  };
  for (final MapEntry(key: p, value: re) in byText.entries) {
    if (re.hasMatch(typed)) found.add(p.key);
  }
  return found;
}
