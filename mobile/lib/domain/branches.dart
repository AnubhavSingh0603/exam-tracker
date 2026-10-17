import 'package:flutter/foundation.dart';

import '../models/jobs_data.dart';
import '../models/user_profile.dart';

/// Engineering branches, grouped the way posts name them. A post "B.E./B.Tech
/// Electronics & Communication" names [electronics] and [telecom]; "Electrical &
/// Electronics" names [electrical] and [electronics].
enum Branch {
  electronics('electronics', 'Electronics / ECE', r'electronic|vlsi|microwave|embedded system',
      r'ECE|E\s?&\s?C|EC|EEE|VLSI|RF'),
  telecom('telecom', 'Telecom / E&TC', r'tele-?\s?communication|communication(?!\s+skill)|radio', r'E\s?&\s?TC|EXTC|ENTC|ETCE'),
  instrumentation('instrumentation', 'Instrumentation', r'instrumentation', r'E\s?&\s?I|EIE|AEI'),
  electrical('electrical', 'Electrical / EEE', r'electrical|power engineering|power systems?', r'EEE|EE'),
  computer('computer', 'Computer / IT',
      r'computer\s+(?:science|engineering|technology|applications?)|information\s+(?:technology|science|security|systems)'
          r'|software|data science|artificial intelligence|machine learning|cyber',
      r'CSE|CS|IT|I\.T\.|AI|ML'),
  civil('civil', 'Civil',
      r'civil(?!\s+(?:services?|court|hospital|judge|defen[cs]e|supplies|aviation|surgeon|police|registration|society))'
          r'|structural|construction|geotech|transportation engineering|water resource|hydraulic|environmental engineering'),
  mechanical('mechanical', 'Mechanical',
      r'mechanical|(?<![a-z])mech(?![a-z])|mechatronic|automobile|production|manufacturing|industrial(?!\s+electronic)'
          r'|thermal|marine engineering'),
  chemical('chemical', 'Chemical', r'chemical|petroleum|petrochemical|polymer|plastic'),
  metallurgy('metallurgy', 'Metallurgy / Materials', r'metallurg|materials?\s+(?:science|engineering)'),
  mining('mining', 'Mining', r'(?<![a-z])mining|(?<![a-z])mine(?![a-z])'),
  agriculture('agriculture', 'Agriculture / Food', r'agricultur|dairy|food\s+(?:technology|engineering)'),
  biotech('biotech', 'Biotech / Biomedical', r'bio-?\s?technolog|bio-?medical|biochemical'),
  aero('aero', 'Aeronautical', r'aero|aviation|avionic'),
  textile('textile', 'Textile', r'textile'),
  geo('geo', 'Geoinformatics / GIS', r'geo-?informatic|remote sensing|geolog|geoscience', r'GIS');

  const Branch(this.key, this.label, this.words, [this.abbreviations]);

  /// Stored in the profile.
  final String key;
  final String label;

  /// Matched in any case.
  final String words;

  /// Short forms, matched in capitals only so "it" and "me" in a sentence don't count.
  final String? abbreviations;

  static Branch? fromKey(String? key) => values.where((b) => b.key == key).firstOrNull;

  /// Branches whose jobs someone from this branch can usually apply for too:
  /// ECE graduates sit Electronics, Telecom, Instrumentation and Electrical posts.
  Set<Branch> get usuallyAlso => switch (this) {
        electronics => const {telecom, instrumentation, electrical},
        telecom => const {electronics},
        instrumentation => const {electronics, electrical},
        electrical => const {electronics, instrumentation},
        _ => const {},
      };
}

RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

final _branchRes = {
  for (final b in Branch.values)
    b: [
      _re(b.words),
      if (b.abbreviations case final a?) RegExp('(?<![A-Za-z])(?:$a)(?![A-Za-z])'),
    ],
};

/// Degrees the branch rule applies to. Anything else you hold (an MBA, an M.Sc)
/// may open the post another way, so the rule stands aside.
const kEngineeringDegrees = {'B_TECH', 'M_TECH', 'DIPLOMA'};

/// Branch-free degrees that never qualify you alone, so they don't lift the rule.
const _schoolDegrees = {'CLASS_10', 'CLASS_12'};

final _engineeringStream = _re(r'(?<![a-z])(?:b\.?\s?e\.?|b\.?\s?tech\.?|m\.?\s?e\.?|m\.?\s?tech\.?|amie|be|btech|me|mtech'
    r'|polytechnic|engg\.?)(?![a-z])|engineering');
final _diploma = _re('diploma');
final _anyBranch = _re(r'any\s+(?:branch|discipline|stream|speciali[sz]ation|trade|engineering)'
    r'|all\s+(?:branches|disciplines|streams)|(?:branch|discipline)\s+(?:of\s+engineering\s+)?(?:is\s+)?no\s+bar'
    r'|irrespective\s+of\s+(?:branch|discipline)');
// What's left of "B.E./B.Tech Engineering" or "Three-year Diploma" once the degree words go.
final _degreeWords = _re(r"(?<![a-z])(?:b\.?\s?e\.?|b\.?\s?tech\.?|m\.?\s?e\.?|m\.?\s?tech\.?|be|btech|me|mtech|amie|degree"
    r"|diploma|graduate|bachelor'?s?|master'?s?|in|of|engineering|technology|engg\.?|three-year|3\s+years?|or"
    r"|equivalent|and)(?![a-z])|[^a-z]");
final _generic = _re(r'engineering|technology|engg');
final _vague = _re(r'relevant|related|allied|concerned|appropriate|respective|specified|equivalent');
// "Mechanical/Civil preferred", "preferably Electrical": nice to have, not needed.
final _optionalBefore = _re(r'(?:preferabl\w*|desirabl\w*)\W+(?:[\w.]+\W+){0,2}$');
final _optionalAfter = _re(r'^\W*(?:[\w.&]+\W+){0,4}?(?:preferred|preferable|desirable)');

/// The branches this text names as a must.
Set<Branch> branchesIn(String text) => {
      for (final MapEntry(key: branch, value: res) in _branchRes.entries)
        if (res.expand((re) => re.allMatches(text)).any((m) {
          final before = text.substring((m.start - 30).clamp(0, m.start), m.start);
          final after = text.substring(m.end, (m.end + 40).clamp(m.end, text.length));
          return !_optionalBefore.hasMatch(before) && !_optionalAfter.hasMatch(after);
        }))
          branch,
    };

enum BranchVerdict {
  /// Names one of your branches.
  match,

  /// Any branch will do ("B.E./B.Tech any discipline", "Degree in Engineering").
  anyBranch,

  /// Names only branches you didn't pick.
  other,

  /// An engineering post that doesn't say which branch ("relevant discipline").
  unclear,
}

/// The engineering branches one post asks for.
@immutable
class BranchNeed {
  const BranchNeed({
    this.named = const {},
    this.unknown = const [],
    this.anyBranch = false,
    this.bareDegree = false,
    this.allowedDegrees = const {},
  });

  /// Branches the post's name, streams or qualification text name.
  final Set<Branch> named;

  /// Engineering streams naming a branch outside [Branch] ("Railway Engineering"),
  /// with the degree words taken off.
  final List<String> unknown;
  final bool anyBranch;

  /// Just "B.E./B.Tech" with no branch, beside nothing else.
  final bool bareDegree;
  final Set<String> allowedDegrees;

  BranchVerdict verdictFor(Set<Branch> mine) {
    if (named.intersection(mine).isNotEmpty) return BranchVerdict.match;
    if (anyBranch) return BranchVerdict.anyBranch;
    if (named.isNotEmpty || unknown.isNotEmpty) return BranchVerdict.other;
    if (bareDegree) return BranchVerdict.anyBranch;
    return BranchVerdict.unclear;
  }

  /// "Civil / Mechanical", for "Needs …".
  String get namedLabel => named.isNotEmpty
      ? [for (final b in Branch.values) if (named.contains(b)) b.label].take(3).join(' / ')
      : unknown.take(2).join(' / ');
}

/// What branch this post needs, or null when it isn't an engineering post (or is
/// open to any graduate).
BranchNeed? branchNeedOf(PublishedPost post) {
  if (post.openToAnyGraduate) return null;
  final allowed = post.allowedDegrees.toSet();
  final qualification = post.qualificationText ?? '';
  final engineering = [
    for (final s in post.eligibleStreams)
      if (_engineeringStream.hasMatch(s) || (_diploma.hasMatch(s) && branchesIn(s).isNotEmpty)) s,
  ];
  // DIPLOMA covers PG and medical diplomas too: only an engineering stream counts.
  final engineeringPost = allowed.contains('B_TECH') ||
      allowed.contains('M_TECH') ||
      (allowed.contains('DIPLOMA') && (engineering.isNotEmpty || _engineeringStream.hasMatch(qualification)));
  if (!engineeringPost) return null;

  final named = {...branchesIn(qualification), ...branchesIn(post.postName)};
  final unknown = <String>[];
  var anyBranch = _anyBranch.hasMatch(qualification);
  var bare = false;
  for (final s in engineering) {
    final inStream = branchesIn(s);
    if (inStream.isNotEmpty) {
      named.addAll(inStream);
    } else if (_anyBranch.hasMatch(s)) {
      anyBranch = true;
    } else if (s.replaceAll(_degreeWords, '').isEmpty) {
      // "Degree in Engineering" opens every branch; a bare "B.E./B.Tech" probably does.
      if (_generic.hasMatch(s)) {
        anyBranch = true;
      } else {
        bare = true;
      }
    } else if (!_vague.hasMatch(s)) {
      unknown.add(s.replaceAll(_re(r'^\W*(?:[\w.]+/)*(?:b\.?\s?e|b\.?\s?tech|m\.?\s?e|m\.?\s?tech|diploma)\.?\s*(?:in\s+)?'), '').trim());
    }
  }
  return BranchNeed(named: named, unknown: unknown, anyBranch: anyBranch, bareDegree: bare, allowedDegrees: allowed);
}

/// Whether a degree you hold besides engineering lets you in anyway ("MCA or
/// B.Tech CSE" for someone with an MCA).
bool otherRouteOpen(BranchNeed need, Set<String> degreesHeld) => need.allowedDegrees
    .intersection(degreesHeld)
    .any((d) => !kEngineeringDegrees.contains(d) && !_schoolDegrees.contains(d));

/// Whether the profile holds a degree that has a branch (B.Tech, M.Tech, Diploma).
bool hasBranchDegree(UserProfileData profile) => profile.allDegrees.any(kEngineeringDegrees.contains);

/// "Electronics / ECE + Electrical / EEE", or null when no branch is set.
String? branchSummary(UserProfileData profile) {
  final keys = branchesFromProfile(profile);
  if (keys.isEmpty) return null;
  final mine = Branch.fromKey(profile.branch)!;
  final also = keys.length - 1;
  return also == 0 ? mine.label : '${mine.label} + $also more';
}

/// The branches whose posts the profile can apply for (`Branch.key`s); empty =
/// no branch filter.
Set<String> branchesFromProfile(UserProfileData? profile) {
  final mine = Branch.fromKey(profile?.branch);
  if (profile == null || mine == null || !hasBranchDegree(profile)) return const {};
  return {mine.key, for (final b in profile.alsoBranches) if (Branch.fromKey(b) != null) b};
}
