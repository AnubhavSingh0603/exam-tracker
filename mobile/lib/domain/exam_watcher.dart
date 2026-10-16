/// Phase 2 on the phone: is this notice about *my* exam, and what does it announce?
/// A port of backend/app/services/exam_watcher.py + alert_matching.py (pure, no I/O).
///
/// The phone runs the watcher because it is in India: official portals (UPSC,
/// railway boards…) block GitHub's US servers but not you.
library;

import 'package:flutter/foundation.dart';

import '../models/tracked_application.dart';
import 'exam_catalog.dart';

/// Backend `ExamMilestone` wire values.
enum Milestone {
  postponed('postponed'),
  result('result'),
  answerKey('answer_key'),
  admitCard('admit_card'),
  examSchedule('exam_schedule');

  const Milestone(this.wire);
  final String wire;

  static Milestone? fromWire(String? v) {
    for (final m in values) {
      if (m.wire == v) return m;
    }
    return null;
  }
}

RegExp _phrases(List<String> words) => RegExp('\\b(?:${words.join('|')})\\b', caseSensitive: false);

/// Checked in order, first match wins: the most specific / latest stage first,
/// so "Result along with Final Answer Key" is a result.
final List<(Milestone, RegExp)> milestonePatterns = [
  (Milestone.postponed, _phrases([r'postpone\w*', r're-?scheduled?', 'deferred', r'cancell?ed'])),
  (
    Milestone.result,
    _phrases([
      r'results?',
      r'merit lists?',
      r'select(?:ion)? lists?',
      r'cut[- ]?offs?',
      r'score ?cards?',
      'final selection',
      r'marks of (?:the )?candidates',
    ]),
  ),
  (
    Milestone.answerKey,
    _phrases([
      r'answer keys?',
      r'(?:provisional|tentative) keys?',
      r'response sheets?',
      r'objection\w*',
      r'question papers?'
    ]),
  ),
  (
    Milestone.admitCard,
    _phrases(
        [r'e-?admit cards?', r'admit cards?', r'hall tickets?', r'call letters?', 'admission certificate']),
  ),
  (
    Milestone.examSchedule,
    _phrases([
      r'exam(?:ination)? dates?',
      r'dates? of (?:the )?exam(?:ination)?',
      r'exam(?:ination)? schedule',
      r'schedule of (?:the )?exam(?:ination)?',
      r'exam(?:ination)? calendar',
      'exam city',
      'city intimation',
      'intimation slip',
      r'time ?table',
    ]),
  ),
];

Milestone? classifyMilestone(String text) {
  for (final (m, pattern) in milestonePatterns) {
    if (pattern.hasMatch(text)) return m;
  }
  return null;
}

const _monthNames = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

// Pieces of the date patterns. Month names must be whole words, so "decision" or
// "mayor" never read as a month.
const _mon = r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?'
    r'|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b\.?';
const _ord = r'(?:st|nd|rd|th)?';
const _yr = r'((?:19|20)\d{2})';
const _to = r'\s*(?:to|till|until|-|–|—|&|and)\s*';
const _day = r'(?<![\w-])(\d{1,2})'; // not "Tier-1", not the "26" of "2026"

// Windows: "12.10.2026 to 19.10.2026", "12–19 October 2026", "28 Nov to 3 Dec",
// "October 12–19, 2026". Single dates: "14.12.2026", "3rd March 2027", "Oct 12, 2026".
final _numRange = RegExp('\\b(\\d{1,2})[./-](\\d{1,2})[./-]$_yr$_to(\\d{1,2})[./-](\\d{1,2})[./-]$_yr\\b',
    caseSensitive: false);
final _dayRange = RegExp('$_day$_ord(?:\\s+$_mon(?:,?\\s*$_yr)?)?$_to(\\d{1,2})$_ord\\s+$_mon(?:,?\\s*$_yr)?',
    caseSensitive: false);
final _monthRange =
    RegExp('\\b$_mon\\s+(\\d{1,2})$_ord$_to(\\d{1,2})$_ord(?:,?\\s*$_yr)?(?!\\d)', caseSensitive: false);
// "September 30, 2026 – October 30, 2026", "Sep 30 to Oct 30, 2026".
final _monthDayRange = RegExp(
    '\\b$_mon\\s+(\\d{1,2})$_ord(?:,?\\s*$_yr)?$_to$_mon\\s+(\\d{1,2})$_ord(?:,?\\s*$_yr)?(?!\\d)',
    caseSensitive: false);
final _numDate = RegExp('\\b(\\d{1,2})[./-](\\d{1,2})[./-]$_yr\\b', caseSensitive: false);
final _dayMonth = RegExp('$_day$_ord\\s+$_mon(?:,?\\s*$_yr)?', caseSensitive: false);
final _monthDay = RegExp('\\b$_mon\\s+(\\d{1,2})$_ord(?:,?\\s*$_yr)?(?!\\d)', caseSensitive: false);

/// Every pattern above, to blank dates out of a text.
final _dateRe = RegExp(
    [_numRange, _dayRange, _monthRange, _monthDayRange, _numDate, _dayMonth, _monthDay].map((r) => r.pattern).join('|'),
    caseSensitive: false);

/// An exam's dates as a notice prints them: one day, or a window ([end] set).
typedef EventWindow = ({DateTime start, DateTime? end});

int _month(String name) => _monthNames.indexOf(name.substring(0, 3).toLowerCase()) + 1;

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
  final date = DateTime(y, m, d);
  return date.month == m ? date : null; // 31 Feb
}

/// A year for a date printed without one: the one that puts it closest to [ref].
int _yearNear(int m, int d, DateTime ref) {
  var best = ref.year;
  var bestGap = 1 << 30;
  for (final y in [ref.year - 1, ref.year, ref.year + 1]) {
    final gap = DateTime(y, m, d).difference(ref).inDays.abs();
    if (gap < bestGap) {
      best = y;
      bestGap = gap;
    }
  }
  return best;
}

EventWindow? _window(DateTime? start, DateTime? end) {
  if (start == null) return null;
  if (end == null || end == start) return (start: start, end: null);
  if (end.isBefore(start) || end.difference(start).inDays > 62) return null; // not one exam window
  return (start: start, end: end);
}

/// From one range match: the end's month and year carry over to the start ("12–19
/// October"), stepping back a month or year when the start would come after the end.
EventWindow? _range(int d1, int? m1, int? y1, int d2, int m2, int? y2, DateTime ref) {
  final endYear = y2 ?? y1 ?? _yearNear(m2, d2, ref);
  final end = _valid(endYear, m2, d2);
  if (end == null) return null;
  var sm = m1 ?? m2;
  var sy = y1 ?? endYear;
  if (m1 == null && d1 > d2) sm -= 1; // "28 to 3 December"
  if (sm == 0) {
    sm = 12;
    sy -= 1;
  }
  if (y1 == null && DateTime(sy, sm, d1).isAfter(end)) sy -= 1; // "28 Dec to 3 Jan 2027"
  return _window(_valid(sy, sm, d1), end);
}

/// The exam date or window a notice prints first. Without a year, the year nearest
/// [reference] (default: today). Where a single date and a window overlap ("Tier 1
/// October 12–19"), the window wins.
EventWindow? extractEventWindow(String text, {DateTime? reference}) {
  final ref = reference ?? DateTime.now();
  int? n(String? g) => g == null ? null : int.parse(g);
  int? mon(String? g) => g == null ? null : _month(g);
  final found = <(int, int, bool, EventWindow)>[];
  void add(RegExpMatch m, EventWindow? w, {required bool range}) {
    if (w != null) found.add((m.start, m.end, range, w));
  }

  for (final m in _numRange.allMatches(text)) {
    final start = _valid(n(m[3])!, n(m[2])!, n(m[1])!);
    add(m, _window(start, _valid(n(m[6])!, n(m[5])!, n(m[4])!)), range: true);
  }
  for (final m in _dayRange.allMatches(text)) {
    add(m, _range(n(m[1])!, mon(m[2]), n(m[3]), n(m[4])!, mon(m[5])!, n(m[6]), ref), range: true);
  }
  for (final m in _monthRange.allMatches(text)) {
    add(m, _range(n(m[2])!, null, null, n(m[3])!, mon(m[1])!, n(m[4]), ref), range: true);
  }
  for (final m in _monthDayRange.allMatches(text)) {
    add(m, _range(n(m[2])!, mon(m[1]), n(m[3]), n(m[5])!, mon(m[4])!, n(m[6]), ref), range: true);
  }
  for (final m in _numDate.allMatches(text)) {
    add(m, _window(_valid(n(m[3])!, n(m[2])!, n(m[1])!), null), range: false);
  }
  for (final m in _dayMonth.allMatches(text)) {
    final mo = mon(m[2])!, d = n(m[1])!;
    add(m, _window(_valid(n(m[3]) ?? _yearNear(mo, d, ref), mo, d), null), range: false);
  }
  for (final m in _monthDay.allMatches(text)) {
    final mo = mon(m[1])!, d = n(m[2])!;
    add(m, _window(_valid(n(m[3]) ?? _yearNear(mo, d, ref), mo, d), null), range: false);
  }
  if (found.isEmpty) return null;
  found.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
  final first = found.first;
  for (final f in found) {
    if (f.$3 && f.$1 < first.$2 && f.$2 > first.$1) return f.$4; // a window overlapping it
  }
  return first.$4;
}

/// First date printed in the notice ("Exam on 14.12.2026" -> 14 Dec 2026), day first.
/// For a window, its first day.
DateTime? extractEventDate(String text, {DateTime? reference}) =>
    extractEventWindow(text, reference: reference)?.start;

final _yearRe = RegExp(r'\b(20\d\d)\b');

/// Exam years named in the text; full dates (a notice's posting date) don't count.
Set<String> _years(String text) =>
    {for (final m in _yearRe.allMatches(text.replaceAll(_dateRe, ' '))) m.group(1)!};

// --- Alert ↔ exam matching (alert_matching.py) -------------------------------------

const _stopwords = {
  'the',
  'of',
  'and',
  'for',
  'in',
  'to',
  'a',
  'an',
  '&',
  'admit',
  'card',
  'cards',
  'call',
  'letter',
  'hall',
  'ticket',
  'exam',
  'examination',
  'recruitment',
  'online',
  'form',
  'notification',
  'post',
  'posts',
  'various',
  'out',
  'released',
  'download',
  'phase',
  'tier',
  'stage',
  'limited',
  'ltd',
  'india',
  'indian',
  'government',
  'govt',
  'advt',
  'no',
};
const _weak = {
  'combined',
  'level',
  'graduate',
  'graduates',
  'higher',
  'secondary',
  'senior',
  'junior',
  'general',
  'common',
  'entrance',
  'test',
  'selection',
};
final _yearToken = RegExp(r'^(19|20)\d\d$');

Set<String> _tokens(String text) => {
      for (final m in RegExp('[a-z0-9]+').allMatches(text.toLowerCase()))
        if (m.group(0)!.length > 1 && !_stopwords.contains(m.group(0)) && !_yearToken.hasMatch(m.group(0)!))
          m.group(0)!,
    };

/// Both 'rrb' (all words) and 'rb' (without stopwords) for 'Railway Recruitment Board'.
Set<String> _acronyms(String name) {
  final words = [for (final m in RegExp('[A-Za-z]+').allMatches(name)) m.group(0)!];
  final full = words.map((w) => w[0]).join().toLowerCase();
  final short =
      words.where((w) => !_stopwords.contains(w.toLowerCase())).map((w) => w[0]).join().toLowerCase();
  return {
    for (final a in [full, short])
      if (a.length > 1) a
  };
}

/// True when the notice names this exam, not just the same organisation.
bool alertMatchesExam(String alertTitle, String examName, String? organization) {
  final alert = _tokens(alertTitle);
  final org = _tokens(organization ?? '').union(_acronyms(organization ?? ''));
  final examWords = _tokens(examName).difference(org);
  final strong = examWords.difference(_weak).union(_acronyms(examName).difference(org));
  final shared = alert.intersection(examWords.union(strong).union(org));
  if (shared.length < 2) return false;
  if (examWords.difference(_weak).isNotEmpty) return alert.intersection(strong).isNotEmpty;
  return alert.containsAll(examWords) || alert.intersection(strong).isNotEmpty;
}

/// About this exam, and not about another year's edition of it.
bool namesThisExam(String text, String examName, String? organization) {
  final examYears = _years(examName);
  final textYears = _years(text);
  if (examYears.isNotEmpty && textYears.isNotEmpty && examYears.intersection(textYears).isEmpty) return false;
  if (alertMatchesExam(text, examName, organization)) return true;
  // "SSC Combined Graduate Level Tier 1 Admit Card" is "SSC CGL": the exam list knows
  // both names (and needs the board named too, so look-alikes don't match).
  final mine = matchCatalogExam('$examName ${organization ?? ''}');
  return mine != null && matchCatalogExam(text)?.id == mine.id;
}

const _romanStage = {'i': '1', 'ii': '2', 'iii': '3', 'iv': '4', 'v': '5'};

/// "tier-1", "cbt-2", "prelims", "mains", "interview", or null when none is named.
String? stageKey(String text) {
  final t = text.toLowerCase();
  final m = RegExp(r'\b(tier|phase|paper|cbt|stage)[\s-]*(iv|v|i{1,3}|\d)\b').firstMatch(t);
  if (m != null) return '${m.group(1)}-${_romanStage[m.group(2)] ?? m.group(2)}';
  if (RegExp(r'\b(?:prelim\w*|preliminary|pre)\b').hasMatch(t)) return 'prelims';
  if (RegExp(r'\bmains?\b').hasMatch(t)) return 'mains';
  if (RegExp(r'\b(?:interview|personality test)\b').hasMatch(t)) return 'interview';
  return null;
}

/// A notice about another stage than the one tracked ("Tier 1 Admit Card" for an
/// exam tracked at Tier-2). One naming no stage is about the whole exam.
bool namesAnotherStage(String text, String? trackedStage) {
  if (trackedStage == null) return false;
  final mine = stageKey(trackedStage);
  final theirs = stageKey(text);
  return mine != null && theirs != null && mine != theirs;
}

/// A recruitment's own page (".../cen-03-2026/") rather than a whole notice board:
/// notices there may just say "Download Admit Card".
bool isExamSpecificPage(String url) {
  final path = (Uri.tryParse(url)?.path ?? '').replaceAll(RegExp(r'^/+|/+$'), '');
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return segments.length >= 2 || RegExp(r'\d').hasMatch(path);
}

// --- Links ---------------------------------------------------------------------------

/// A link on a page (or in notices.json) with the text around it.
@immutable
class PageLink {
  const PageLink({required this.url, required this.title, this.context = '', this.link});

  final String url;
  final String title;
  final String context;

  /// notices.json: the official link the pipeline found on the notice's page.
  final String? link;
}

final _tracking = RegExp(r'^(utm_|fbclid|gclid|ref$|amp$)');

/// Drop fragments and tracking parameters so one notice is never "new" twice.
String canonicalUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme) return url.trim();
  final query =
      u.query.split('&').where((kv) => kv.isNotEmpty && !_tracking.hasMatch(kv.split('=').first)).join('&');
  return Uri(
    scheme: u.scheme.toLowerCase(),
    host: u.host.toLowerCase(),
    port: u.hasPort ? u.port : null,
    path: u.path.isEmpty ? '/' : u.path,
    query: query.isEmpty ? null : query,
  ).toString();
}

enum UpdateSource { official, aggregator }

@immutable
class DetectedUpdate {
  const DetectedUpdate({
    required this.milestone,
    required this.title,
    required this.url,
    required this.source,
    this.eventDate,
    this.eventEnd,
    this.link,
  });

  final Milestone milestone;
  final String title;
  final String url;
  final UpdateSource source;
  final DateTime? eventDate;

  /// The official link for it (admit card download, answer key, result), if known.
  final String? link;

  String get open => link ?? url;

  /// Last day, when the notice gives a window ("12–19 October").
  final DateTime? eventEnd;
}

/// New milestone notices for one exam among a page's links.
List<DetectedUpdate> detectUpdates(
  Iterable<PageLink> links, {
  required String examName,
  required String? organization,
  required UpdateSource source,
  required bool examSpecificPage,
  required Set<String> knownUrls,
  DateTime? now,
  String? stage,
}) {
  final found = <DetectedUpdate>[];
  final seen = {...knownUrls};
  final examYears = _years(examName);
  for (final link in links) {
    final url = canonicalUrl(link.url);
    if (seen.contains(url)) continue;
    final text = '${link.title} ${link.context}'.trim();
    final milestone = classifyMilestone(text);
    if (milestone == null) continue;
    final textYears = _years(text);
    if (examYears.isNotEmpty && textYears.isNotEmpty && examYears.intersection(textYears).isEmpty) continue;
    if (namesAnotherStage(text, stage)) continue; // a Tier 1 notice for an exam tracked at Tier-2
    if (!examSpecificPage && !namesThisExam(text, examName, organization)) continue;
    seen.add(url);
    final title = link.title.isEmpty ? text : link.title;
    final window = extractEventWindow(text, reference: now);
    found.add(DetectedUpdate(
      milestone: milestone,
      title: title.length > 300 ? title.substring(0, 300) : title,
      url: url,
      source: source,
      eventDate: window?.start,
      eventEnd: window?.end,
      link: link.link,
    ));
  }
  return found;
}

const _statusFor = {
  Milestone.admitCard: TrackerStatus.admitCardLive,
  Milestone.examSchedule: TrackerStatus.examScheduled,
  Milestone.answerKey: TrackerStatus.answerKeyLive,
  Milestone.result: TrackerStatus.resultDeclared,
};

/// Highest status the milestones imply; never moves backwards.
TrackerStatus advanceStatus(TrackerStatus current, Iterable<Milestone> milestones) {
  var best = current;
  for (final m in milestones) {
    final target = _statusFor[m];
    if (target != null && target.index > best.index) best = target;
  }
  return best;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Fills the exam's 5-stage timeline (the `timeline` JSON from jobs.json) from a new
/// notice. Newest link wins; a milestone's date is set on first sighting only.
Map<String, dynamic> fillTimeline(Map<String, dynamic> timeline, DetectedUpdate u, DateTime seenOn) {
  final t = {...timeline};
  final text = u.title.toLowerCase();
  final today = _isoDate(seenOn);
  void firstDate(String key) => t[key] ??= today;
  // Dates up to 60 days back still count: a notice first seen mid-window or just
  // after the exam is how the app learns the exam already happened.
  final start = u.eventDate;
  final end = u.eventEnd;
  final usable = start != null &&
      !(end ?? start).isBefore(DateTime(seenOn.year, seenOn.month, seenOn.day).subtract(const Duration(days: 60)));
  void setExam() {
    t['exam_start'] = _isoDate(start!);
    if (end != null) {
      t['exam_end'] = _isoDate(end);
    } else {
      t.remove('exam_end');
    }
  }

  switch (u.milestone) {
    case Milestone.admitCard:
      t['admit_card_url'] = u.open;
      firstDate('admit_card_release');
      // "Admit Card (Exam on 14.12.2026)": the printed date is the exam date, if none is known yet.
      if (usable && t['exam_start'] == null) setExam();
    case Milestone.examSchedule || Milestone.postponed:
      if (text.contains('city') || text.contains('intimation')) t['exam_city_slip_url'] = u.open;
      if (usable) setExam(); // a newer schedule/postponement notice wins
    case Milestone.answerKey:
      if (text.contains('objection') || text.contains('challenge')) {
        t['challenge_portal_url'] = u.open;
      } else if (text.contains('question paper')) {
        t['question_paper_url'] = u.open;
      } else {
        t['answer_key_url'] = u.open;
        firstDate('answer_key_release');
      }
    case Milestone.result:
      t[text.contains('score') ? 'scorecard_url' : 'merit_list_url'] = u.open;
      firstDate('result_date');
  }
  return t;
}

/// Reads the dates of the stored schedule and admit-card notices again (oldest
/// first, each as of when it was seen), so exams tracked before the date reader
/// understood windows ("12–19 October") get their real start and end. Also undoes
/// that older reader's slip of storing a window's last day as the exam date.
Map<String, dynamic> refreshExamDates(Map<String, dynamic> timeline, List<ExamUpdate> updates, DateTime now) {
  var t = {...timeline};
  for (final u in updates.reversed) {
    final m = Milestone.fromWire(u.milestone);
    if (m == null || m == Milestone.answerKey || m == Milestone.result) continue;
    final seen = u.detectedAt?.toLocal() ?? now;
    final w = extractEventWindow(u.title, reference: seen);
    if (w == null) continue;
    final end = w.end;
    if (m == Milestone.admitCard && end != null && t['exam_start'] == _isoDate(end) && t['exam_end'] == null) {
      t.remove('exam_start'); // the old reader's "19 October" for "12–19 October"
    }
    t = fillTimeline(
      t,
      DetectedUpdate(
          milestone: m,
          title: u.title,
          url: u.url,
          source: UpdateSource.aggregator,
          eventDate: w.start,
          eventEnd: end,
          link: u.link),
      seen,
    );
  }
  return t;
}

/// Notification text per milestone (matches the backend's push texts).
(String, String) notificationText(Milestone m, String examName, String noticeTitle) {
  final (title, body) = switch (m) {
    Milestone.admitCard => (
        '🎫 Admit card out: $examName',
        'Download it now — portals often close it before the exam.'
      ),
    Milestone.examSchedule => ('📅 Exam date update: $examName', noticeTitle),
    Milestone.postponed => ('⚠️ Exam rescheduled: $examName', noticeTitle),
    Milestone.answerKey => (
        '📝 Answer key released: $examName',
        'Check your answers; objections have a deadline.'
      ),
    Milestone.result => ('🏁 Result declared: $examName', noticeTitle),
  };
  return (
    title.length > 120 ? title.substring(0, 120) : title,
    body.length > 240 ? body.substring(0, 240) : body
  );
}
