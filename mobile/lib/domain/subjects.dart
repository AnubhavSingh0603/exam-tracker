import 'package:flutter/foundation.dart';

import '../models/job_preferences.dart';
import '../models/jobs_data.dart';
import '../models/user_profile.dart';
import 'eligibility.dart';

/// A branch, subject, trade or specialisation inside a degree group.
@immutable
class Subject {
  const Subject(this.key, this.label, this.words, {this.abbreviations, this.related = const []});

  /// Stored in the profile.
  final String key;
  final String label;

  /// How posts write it, matched in any case.
  final String words;

  /// Short forms, matched in capitals only so "it" or "me" in a sentence don't count.
  final String? abbreviations;

  /// Keys of subjects whose jobs often accept this one too: offered, never ticked.
  final List<String> related;
}

/// Degrees whose posts name a branch or subject ("B.Tech Civil", "M.Sc Physics",
/// "ITI Electrician", "MBA Finance"), with the subjects to pick from.
class SubjectGroup {
  SubjectGroup({
    required this.key,
    required this.label,
    required this.noun,
    required this.degrees,
    required String degreeWords,
    String? degreeAbbreviations,
    required this.subjects,
  })  : _degree = [
          _re(degreeWords),
          if (degreeAbbreviations != null) RegExp('(?<![A-Za-z])(?:$degreeAbbreviations)(?![A-Za-z])'),
        ],
        _strip = [
          _re('(?<![a-z])(?:$degreeWords|$_genericWords)(?![a-z])'),
          if (degreeAbbreviations != null) RegExp('(?<![A-Za-z])(?:$degreeAbbreviations)(?![A-Za-z])'),
        ];

  /// Stored in the profile.
  final String key;

  /// "B.Sc / M.Sc subjects".
  final String label;

  /// "branch", "subject", "trade": for "Check branch".
  final String noun;

  /// Degree codes (kDegrees) this group covers.
  final Set<String> degrees;
  final List<Subject> subjects;
  final List<RegExp> _degree;
  final List<RegExp> _strip;

  late final Map<Subject, List<RegExp>> _subjectRes = {
    for (final s in subjects)
      s: [
        _re(s.words),
        if (s.abbreviations case final a?) RegExp('(?<![A-Za-z])(?:$a)(?![A-Za-z])'),
      ],
  };

  Subject? subject(String key) => subjects.where((s) => s.key == key).firstOrNull;

  bool _namesDegree(String s) => _degree.any((re) => re.hasMatch(s));

  /// A stream for this group's degrees ("B.Sc. Physics" for B.Sc / M.Sc).
  bool streamBelongs(String stream) => _namesDegree(stream);

  /// The subjects this text names as a must ("Mechanical/Civil preferred" doesn't).
  Set<String> subjectsIn(String text) => {
        for (final MapEntry(key: subject, value: res) in _subjectRes.entries)
          if (res.expand((re) => re.allMatches(text)).any((m) {
            final before = text.substring((m.start - 30).clamp(0, m.start), m.start);
            final after = text.substring(m.end, (m.end + 40).clamp(m.end, text.length));
            return !_optionalBefore.hasMatch(before) && !_optionalAfter.hasMatch(after);
          }))
            subject.key,
      };

  /// What's left of a stream once the degree words go: "" for "B.E./B.Tech
  /// Engineering", "Railway" for "B.E./B.Tech Railway Engineering".
  String _leftover(String stream) {
    var s = stream;
    for (final re in _strip) {
      s = s.replaceAll(re, ' ');
    }
    return s.replaceAll(RegExp('[^A-Za-z]+'), ' ').trim();
  }
}

RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

const _genericWords = r"degree|diploma|graduate|graduation|post|bachelor'?s?|master'?s?|in|of|with|or|and|equivalent"
    r"|three-year|3\s+years?|course|honours|hons|engineering|technology|engg|science|arts|commerce|subject|subjects"
    r"|specialization|specialisation|recognised|recognized|university|from|a|an|the";

final _any = _re(r'any\s+(?:branch|discipline|stream|subject|speciali[sz]ation|trade|engineering|field)'
    r'|all\s+(?:branches|disciplines|streams|subjects|trades)|(?:branch|discipline|subject)\s+(?:of\s+engineering\s+)?'
    r'(?:is\s+)?no\s+bar|irrespective\s+of\s+(?:branch|discipline|subject|stream)');
final _generic = _re(r'engineering|technology|engg|science|arts|commerce|humanities');
final _vague = _re(r'relevant|related|allied|concerned|appropriate|respective|specified|equivalent|etc');
final _optionalBefore = _re(r'(?:preferabl\w*|desirabl\w*)\W+(?:[\w.]+\W+){0,2}$');
final _optionalAfter = _re(r'^\W*(?:[\w.&]+\W+){0,4}?(?:preferred|preferable|desirable)');
final _diploma = _re('diploma');

final engineering = SubjectGroup(
  key: 'engineering',
  label: 'Engineering branch',
  noun: 'branch',
  degrees: {'B_TECH', 'M_TECH', 'DIPLOMA'},
  degreeWords: r'b\.?\s?e\.?|b\.?\s?tech\.?|m\.?\s?e\.?|m\.?\s?tech\.?|amie|be|btech|me|mtech|polytechnic|engg\.?'
      r'|engineering',
  subjects: const [
    Subject('electronics', 'Electronics / ECE', r'electronic|vlsi|microwave|embedded system',
        abbreviations: r'ECE|E\s?&\s?C|EC|EEE|VLSI|RF', related: ['telecom', 'instrumentation', 'electrical']),
    Subject('telecom', 'Telecom / E&TC', r'tele-?\s?communication|communication(?!\s+skill)|radio',
        abbreviations: r'E\s?&\s?TC|EXTC|ENTC|ETCE', related: ['electronics']),
    Subject('instrumentation', 'Instrumentation', r'instrumentation',
        abbreviations: r'E\s?&\s?I|EIE|AEI', related: ['electronics', 'electrical']),
    Subject('electrical', 'Electrical / EEE', r'electrical|power engineering|power systems?',
        abbreviations: r'EEE|EE', related: ['electronics', 'instrumentation']),
    Subject('computer', 'Computer / IT',
        r'computer\s+(?:science|engineering|technology|applications?)|information\s+(?:technology|science|security|systems)'
            r'|software|data science|artificial intelligence|machine learning|cyber',
        abbreviations: r'CSE|CS|IT|I\.T\.|AI|ML', related: ['electronics']),
    Subject('civil', 'Civil',
        r'civil(?!\s+(?:services?|court|hospital|judge|defen[cs]e|supplies|aviation|surgeon|police|registration|society))'
            r'|structural|construction|geotech|transportation engineering|water resource|hydraulic'
            r'|environmental engineering',
        related: ['geo', 'agriculture']),
    Subject('mechanical', 'Mechanical',
        r'mechanical|(?<![a-z])mech(?![a-z])|mechatronic|automobile|production|manufacturing'
            r'|industrial(?!\s+electronic)|thermal|marine engineering',
        related: ['aero', 'metallurgy']),
    Subject('chemical', 'Chemical', r'chemical|petroleum|petrochemical|polymer|plastic', related: ['metallurgy']),
    Subject('metallurgy', 'Metallurgy / Materials', r'metallurg|materials?\s+(?:science|engineering)',
        related: ['mechanical', 'mining']),
    Subject('mining', 'Mining', r'(?<![a-z])mining|(?<![a-z])mine(?![a-z])', related: ['metallurgy', 'geo']),
    Subject('agriculture', 'Agriculture / Food', r'agricultur|dairy|food\s+(?:technology|engineering)',
        related: ['civil']),
    Subject('biotech', 'Biotech / Biomedical', r'bio-?\s?technolog|bio-?medical|biochemical'),
    Subject('aero', 'Aeronautical', r'aero|aviation|avionic', related: ['mechanical']),
    Subject('textile', 'Textile', r'textile'),
    Subject('geo', 'Geoinformatics / GIS', r'geo-?informatic|remote sensing|geolog|geoscience',
        abbreviations: r'GIS', related: ['civil']),
  ],
);

final iti = SubjectGroup(
  key: 'iti',
  label: 'ITI trade',
  noun: 'trade',
  degrees: {'ITI'},
  degreeWords: r'iti|ncvt|scvt|nac|national (?:trade|apprentice\w*) certificate|trade certificate|trade',
  degreeAbbreviations: r'ITI',
  subjects: const [
    Subject('electrician', 'Electrician', r'electrician', related: ['wireman']),
    Subject('wireman', 'Wireman', r'wireman', related: ['electrician']),
    Subject('fitter', 'Fitter', r'fitter', related: ['turner', 'machinist']),
    Subject('turner', 'Turner', r'turner', related: ['fitter', 'machinist']),
    Subject('machinist', 'Machinist', r'machinist', related: ['fitter', 'turner']),
    Subject('welder', 'Welder', r'welder', related: ['sheet_metal']),
    Subject('mmv', 'Mechanic (Motor Vehicle)', r'motor vehicle|(?<![a-z])mmv(?![a-z])|auto(?:mobile)? mechanic',
        related: ['diesel']),
    Subject('diesel', 'Mechanic (Diesel)', r'diesel', related: ['mmv']),
    Subject('electronics_mech', 'Electronics Mechanic', r'electronics? mechanic', related: ['instrument_mech']),
    Subject('instrument_mech', 'Instrument Mechanic', r'instrument mechanic', related: ['electronics_mech']),
    Subject('refrigeration', 'Refrigeration & AC', r'refrigeration|air[- ]condition', abbreviations: r'RAC'),
    Subject('copa', 'Computer Operator (COPA)', r'computer operator|programming assistant', abbreviations: r'COPA'),
    Subject('draughtsman_civil', 'Draughtsman (Civil)', r'draughts?man\W+civil|civil draughts?man',
        related: ['draughtsman_mech']),
    Subject('draughtsman_mech', 'Draughtsman (Mechanical)', r'draughts?man\W+mech\w*|mechanical draughts?man',
        related: ['draughtsman_civil']),
    Subject('plumber', 'Plumber', r'plumber'),
    Subject('carpenter', 'Carpenter', r'carpenter'),
    Subject('painter', 'Painter', r'painter'),
    Subject('sheet_metal', 'Sheet Metal Worker', r'sheet metal', related: ['welder']),
  ],
);

final science = SubjectGroup(
  key: 'science',
  label: 'B.Sc / M.Sc subjects',
  noun: 'subject',
  degrees: {'B_SC', 'M_SC'},
  degreeWords: r'b\.?\s?sc\.?|m\.?\s?sc\.?|bachelor of science|master of science',
  subjects: const [
    Subject('physics', 'Physics', r'physics', related: ['electronics', 'mathematics']),
    Subject('chemistry', 'Chemistry', r'chemistry|chemical science', related: ['biochemistry']),
    Subject('mathematics', 'Mathematics', r'mathematic|(?<![a-z])maths?(?![a-z])', related: ['statistics', 'physics']),
    Subject('statistics', 'Statistics', r'statistic', related: ['mathematics']),
    Subject('botany', 'Botany', r'botany|plant science', related: ['zoology', 'life_science']),
    Subject('zoology', 'Zoology', r'zoology|animal science', related: ['botany', 'life_science']),
    Subject('life_science', 'Biology / Life Sciences', r'biology|life sciences?|bio-?sciences?',
        related: ['botany', 'zoology']),
    Subject('microbiology', 'Microbiology', r'micro-?biology', related: ['biotechnology', 'biochemistry']),
    Subject('biotechnology', 'Biotechnology', r'bio-?\s?technology', related: ['microbiology', 'biochemistry']),
    Subject('biochemistry', 'Biochemistry', r'bio-?chemistry', related: ['chemistry', 'biotechnology']),
    Subject('computer', 'Computer Science / IT',
        r'computer|information technology|data science', abbreviations: r'CS|IT', related: ['electronics']),
    Subject('electronics', 'Electronics', r'electronic', related: ['physics', 'computer']),
    Subject('agriculture', 'Agriculture', r'agricultur', related: ['horticulture', 'forestry']),
    Subject('horticulture', 'Horticulture', r'horticultur', related: ['agriculture']),
    Subject('forestry', 'Forestry', r'forestry', related: ['agriculture', 'environment']),
    Subject('geology', 'Geology / Earth Science', r'geolog|earth science|geo-?physics', related: ['geography']),
    Subject('geography', 'Geography', r'geography', related: ['geology']),
    Subject('environment', 'Environmental Science', r'environment', related: ['forestry']),
    Subject('home_science', 'Home Science / Nutrition', r'home science|nutrition|dietetic|food science'),
    Subject('fisheries', 'Fisheries', r'fisher'),
    Subject('forensic', 'Forensic Science', r'forensic'),
    Subject('psychology', 'Psychology', r'psychology'),
  ],
);

final arts = SubjectGroup(
  key: 'arts',
  label: 'B.A. / M.A. subjects',
  noun: 'subject',
  degrees: {'B_A', 'M_A'},
  degreeWords: r'bachelor of arts|master of arts|arts|humanities',
  degreeAbbreviations: r'B\.?\s?A\.?|M\.?\s?A\.?',
  subjects: const [
    Subject('hindi', 'Hindi', r'hindi'),
    Subject('english', 'English', r'english'),
    Subject('sanskrit', 'Sanskrit', r'sanskrit'),
    Subject('urdu', 'Urdu', r'urdu'),
    Subject('economics', 'Economics', r'economics', related: ['statistics']),
    Subject('history', 'History', r'history', related: ['political_science']),
    Subject('political_science', 'Political Science', r'political science|politics',
        related: ['history', 'public_admin']),
    Subject('public_admin', 'Public Administration', r'public administration', related: ['political_science']),
    Subject('geography', 'Geography', r'geography'),
    Subject('sociology', 'Sociology', r'sociology', related: ['social_work']),
    Subject('psychology', 'Psychology', r'psychology'),
    Subject('philosophy', 'Philosophy', r'philosophy'),
    Subject('mathematics', 'Mathematics', r'mathematic|(?<![a-z])maths?(?![a-z])', related: ['statistics']),
    Subject('statistics', 'Statistics', r'statistic', related: ['economics', 'mathematics']),
    Subject('social_work', 'Social Work', r'social work', abbreviations: r'MSW|BSW', related: ['sociology']),
    Subject('journalism', 'Journalism / Mass Comm.', r'journalism|mass comm\w*'),
    Subject('education', 'Education', r'(?<![a-z])education(?![a-z])'),
    Subject('fine_arts', 'Fine Arts / Music', r'fine arts?|music|painting|dance|drawing'),
    Subject('library', 'Library Science', r'library'),
  ],
);

final commerce = SubjectGroup(
  key: 'commerce',
  label: 'B.Com / M.Com subjects',
  noun: 'subject',
  degrees: {'B_COM', 'M_COM'},
  degreeWords: r'b\.?\s?com\.?|m\.?\s?com\.?|bachelor of commerce|master of commerce|commerce',
  subjects: const [
    Subject('accounting', 'Accounting / Finance', r'account|finance|financial', related: ['taxation']),
    Subject('banking', 'Banking & Insurance', r'banking|insurance', related: ['accounting']),
    Subject('taxation', 'Taxation', r'taxation|(?<![a-z])tax(?![a-z])', related: ['accounting']),
    Subject('business', 'Business Studies', r'business|management'),
  ],
);

final management = SubjectGroup(
  key: 'management',
  label: 'MBA specialisation',
  noun: 'specialisation',
  degrees: {'MBA'},
  degreeWords: r'mba|pgdm|pgdbm|master of business administration|post[- ]?graduate diploma in (?:business )?management',
  subjects: const [
    Subject('finance', 'Finance', r'finance|financial|banking', related: ['marketing']),
    Subject('hr', 'HR / Personnel', r'human resource|personnel|industrial relations', abbreviations: r'HR|HRM'),
    Subject('marketing', 'Marketing', r'marketing|sales'),
    Subject('operations', 'Operations / Supply chain', r'operations|supply chain|logistics|materials management'),
    Subject('systems', 'IT / Systems', r'information technology|systems|business analytics', abbreviations: r'IT'),
    Subject('rural', 'Rural / Agri-business', r'rural|agri'),
    Subject('international', 'International Business', r'international business|foreign trade'),
  ],
);

final medicine = SubjectGroup(
  key: 'medicine',
  label: 'MD / MS speciality',
  noun: 'speciality',
  degrees: {'MD_MS'},
  degreeWords: r'doctor of medicine|master of surgery|post[- ]?graduate degree|post[- ]?graduate diploma',
  degreeAbbreviations: r'MD|M\.D\.|MS|M\.S\.|DNB|DCH|DLO|DDVL|DGO|DA|DMRD|DOMS|D\.?\s?Ortho',
  subjects: const [
    Subject('medicine', 'General Medicine', r'general medicine|internal medicine|(?<![a-z])medicine(?![a-z])'),
    Subject('surgery', 'General Surgery', r'general surgery|(?<![a-z])surgery(?![a-z])'),
    Subject('paediatrics', 'Paediatrics', r'p(?:a)?ediatric|child health', abbreviations: r'DCH'),
    Subject('obgyn', 'Obstetrics & Gynaecology', r'obstetric|gyn(?:a)?ecolog', abbreviations: r'DGO|OBG'),
    Subject('anaesthesia', 'Anaesthesia', r'an(?:a)?esthe', abbreviations: r'DA'),
    Subject('orthopaedics', 'Orthopaedics', r'orthop(?:a)?edic', abbreviations: r'D\.?\s?Ortho'),
    Subject('radiology', 'Radiology', r'radio-?diagnosis|radiology', abbreviations: r'DMRD'),
    Subject('pathology', 'Pathology', r'pathology'),
    Subject('psychiatry', 'Psychiatry', r'psychiatr'),
    Subject('dermatology', 'Dermatology (Skin)', r'dermatolog|(?<![a-z])skin(?![a-z])|venereolog',
        abbreviations: r'DDVL|DVL'),
    Subject('ent', 'ENT', r'otorhinolaryngolog|(?<![a-z])ent(?![a-z])', abbreviations: r'ENT|DLO'),
    Subject('ophthalmology', 'Ophthalmology (Eye)', r'ophthalmolog|(?<![a-z])eye(?![a-z])', abbreviations: r'DOMS'),
    Subject('community', 'Community Medicine / PSM', r'community medicine|preventive|social medicine',
        abbreviations: r'PSM'),
    Subject('microbiology', 'Microbiology', r'micro-?biology'),
    Subject('pharmacology', 'Pharmacology', r'pharmacology'),
  ],
);

/// Every group, in the order the profile shows them.
final kSubjectGroups = [engineering, iti, science, arts, commerce, management, medicine];

SubjectGroup? subjectGroup(String key) => kSubjectGroups.where((g) => g.key == key).firstOrNull;

/// The groups whose subjects someone holding [degreeCodes] can pick. An M.Sc
/// counts as a B.Sc, so one list covers both.
List<SubjectGroup> groupsForDegrees(Iterable<String> degreeCodes) {
  final held = {for (final d in degreeCodes) ...degreeCodesHeld(d), ...degreeCodes};
  return [for (final g in kSubjectGroups) if (g.degrees.intersection(held).isNotEmpty) g];
}

enum SubjectVerdict {
  /// Names one of your subjects.
  match,

  /// Any subject will do ("any discipline", "Degree in Engineering").
  any,

  /// Names only subjects you didn't pick.
  other,

  /// Doesn't say which ("relevant discipline").
  unclear,
}

/// What one post asks for within one group.
@immutable
class SubjectNeed {
  const SubjectNeed(this.group,
      {this.named = const {}, this.unknown = const [], this.any = false, this.bare = false, this.texts = const []});

  final SubjectGroup group;

  /// Subject keys the post names.
  final Set<String> named;

  /// Streams naming something outside the list ("Railway Engineering" → "Railway").
  final List<String> unknown;
  final bool any;

  /// Just the degree ("B.Tech"), with nothing else named.
  final bool bare;

  /// What the post says for this group, for subjects you typed yourself.
  final List<String> texts;

  SubjectVerdict verdictFor(SubjectChoice mine) {
    if (named.intersection(mine.subjects).isNotEmpty) return SubjectVerdict.match;
    if (mine.customTerms.any((t) => customTextMatches(t, texts))) return SubjectVerdict.match;
    if (any) return SubjectVerdict.any;
    if (named.isNotEmpty || unknown.isNotEmpty) return SubjectVerdict.other;
    if (bare) return SubjectVerdict.any;
    return SubjectVerdict.unclear;
  }

  /// "Civil / Mechanical", for "Needs …".
  String get namedLabel => named.isNotEmpty
      ? [for (final s in group.subjects) if (named.contains(s.key)) s.label].take(3).join(' / ')
      : unknown.take(2).join(' / ');
}

/// The subjects a post asks for, per group of the degrees it accepts; null when
/// it's open to any graduate.
@immutable
class PostSubjects {
  const PostSubjects(this.needs, this.allowedDegrees);

  final Map<String, SubjectNeed> needs;
  final Set<String> allowedDegrees;
}

PostSubjects? subjectsOf(PublishedPost post) {
  if (post.openToAnyGraduate) return null;
  final allowed = post.allowedDegrees.toSet();
  final qualification = post.qualificationText ?? '';
  final needs = <String, SubjectNeed>{};
  for (final g in kSubjectGroups) {
    if (g.degrees.intersection(allowed).isEmpty) continue;
    final streams = [
      for (final s in post.eligibleStreams)
        // Diploma streams count for engineering only when they name a branch:
        // PG and medical diplomas use the same code.
        if (g.streamBelongs(s) || (g == engineering && _diploma.hasMatch(s) && g.subjectsIn(s).isNotEmpty)) s,
    ];
    // DIPLOMA alone could be any diploma: an engineering post must say so.
    if (g == engineering &&
        allowed.intersection({'B_TECH', 'M_TECH'}).isEmpty &&
        streams.isEmpty &&
        !g.streamBelongs(qualification)) {
      continue;
    }
    // Streams are per degree; the qualification text mixes them, so it's read
    // only when no stream says.
    final named = {...g.subjectsIn(post.postName), if (streams.isEmpty) ...g.subjectsIn(qualification)};
    final unknown = <String>[];
    var any = _any.hasMatch(qualification);
    var bare = false;
    for (final s in streams) {
      final inStream = g.subjectsIn(s);
      if (inStream.isNotEmpty) {
        named.addAll(inStream);
        continue;
      }
      if (_any.hasMatch(s)) {
        any = true;
        continue;
      }
      final leftover = g._leftover(s);
      if (leftover.isEmpty) {
        // "Degree in Engineering" opens every branch; a bare "B.Tech" probably does.
        if (_generic.hasMatch(s)) {
          any = true;
        } else {
          bare = true;
        }
      } else if (!_vague.hasMatch(s)) {
        unknown.add(leftover);
      }
    }
    needs[g.key] = SubjectNeed(g,
        named: named,
        unknown: unknown,
        any: any,
        bare: bare,
        texts: [...streams, if (streams.isEmpty) qualification, post.postName]);
  }
  return PostSubjects(needs, allowed);
}

/// Degrees that never qualify you alone, so they don't open a post.
const _schoolDegrees = {'CLASS_10', 'CLASS_12'};

/// How a post fits the subjects you picked: null when the rule doesn't apply,
/// otherwise the verdict and, for [SubjectVerdict.other], the "Needs …" reason.
/// You're in when any degree you hold that the post accepts fits it, or has no
/// subjects picked, or has no subject list at all (an LL.B, a BCA).
({SubjectVerdict verdict, String? reason, String noun})? subjectFit(PostSubjects? post, JobPreferences prefs) {
  if (post == null || prefs.subjects.isEmpty) return null;
  final held = prefs.degreesHeld;
  final routes = post.allowedDegrees.intersection(held).difference(_schoolDegrees);
  if (routes.isEmpty) return null; // not your degree at all: the eligibility check says so
  final grouped = {for (final g in kSubjectGroups) ...g.degrees};
  if (routes.any((d) => !grouped.contains(d))) return null;

  ({SubjectVerdict verdict, String? reason, String noun})? unclear;
  ({SubjectVerdict verdict, String? reason, String noun})? other;
  for (final g in kSubjectGroups) {
    if (g.degrees.intersection(routes).isEmpty) continue;
    final mine = prefs.subjects[g.key];
    final need = post.needs[g.key];
    if (mine == null || mine.isEmpty || need == null) return null; // nothing to compare: open
    switch (need.verdictFor(mine)) {
      case SubjectVerdict.match || SubjectVerdict.any:
        return null;
      case SubjectVerdict.unclear:
        unclear ??= (verdict: SubjectVerdict.unclear, reason: null, noun: g.noun);
      case SubjectVerdict.other:
        other ??= (verdict: SubjectVerdict.other, reason: 'Needs ${need.namedLabel}', noun: g.noun);
    }
  }
  return unclear ?? other;
}

/// "Electronics / ECE, Electrical / EEE" or "Physics + 2 more", for the profile.
String subjectSummary(SubjectChoice choice) {
  final group = subjectGroup(choice.group);
  final labels = [
    for (final s in group?.subjects ?? const <Subject>[]) if (choice.subjects.contains(s.key)) s.label,
    ...choice.customTerms,
  ];
  if (labels.length <= 2) return labels.join(', ');
  return '${labels.take(2).join(', ')} + ${labels.length - 2} more';
}

/// The profile's picks that still apply (a group whose degree was removed is
/// dropped), by group key.
Map<String, SubjectChoice> subjectsFromProfile(UserProfileData? profile) {
  if (profile == null) return const {};
  final groups = {for (final g in groupsForDegrees(profile.allDegrees)) g.key};
  return {
    for (final c in profile.subjects)
      if (groups.contains(c.group) && !c.isEmpty) c.group: c,
  };
}
