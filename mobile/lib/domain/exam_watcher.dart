/// Phase 2 on the phone: is this notice about *my* exam, and what does it announce?
/// A port of backend/app/services/exam_watcher.py + alert_matching.py (pure, no I/O).
///
/// The phone runs the watcher because it is in India: official portals (UPSC,
/// railway boards…) block GitHub's US servers but not you.
library;

import 'package:flutter/foundation.dart';

import '../models/tracked_application.dart';

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
final _dateRe = RegExp(
  r'\b(\d{1,2})[./-](\d{1,2})[./-]((?:19|20)\d{2})\b'
  r'|\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+((?:19|20)\d{2})\b',
  caseSensitive: false,
);

/// First date printed in the notice ("Exam on 14.12.2026" -> 14 Dec 2026), day first.
DateTime? extractEventDate(String text) {
  for (final m in _dateRe.allMatches(text)) {
    final int day;
    final int month;
    final int year;
    if (m.group(1) != null) {
      day = int.parse(m.group(1)!);
      month = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
    } else {
      day = int.parse(m.group(4)!);
      month = _monthNames.indexOf(m.group(5)!.toLowerCase()) + 1;
      year = int.parse(m.group(6)!);
    }
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000 || year > 2100) continue;
    final d = DateTime(year, month, day);
    if (d.month != month) continue; // 31 Feb
    return d;
  }
  return null;
}

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
  return alertMatchesExam(text, examName, organization);
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
  const PageLink({required this.url, required this.title, this.context = ''});

  final String url;
  final String title;
  final String context;
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
  });

  final Milestone milestone;
  final String title;
  final String url;
  final UpdateSource source;
  final DateTime? eventDate;
}

/// New milestone notices for one exam among a page's links.
List<DetectedUpdate> detectUpdates(
  Iterable<PageLink> links, {
  required String examName,
  required String? organization,
  required UpdateSource source,
  required bool examSpecificPage,
  required Set<String> knownUrls,
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
    if (!examSpecificPage && !namesThisExam(text, examName, organization)) continue;
    seen.add(url);
    final title = link.title.isEmpty ? text : link.title;
    found.add(DetectedUpdate(
      milestone: milestone,
      title: title.length > 300 ? title.substring(0, 300) : title,
      url: url,
      source: source,
      eventDate: extractEventDate(text),
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
  switch (u.milestone) {
    case Milestone.admitCard:
      t['admit_card_url'] = u.url;
      firstDate('admit_card_release');
      // "Admit Card (Exam on 14.12.2026)": the printed date is the exam date, if none is known yet.
      final d = u.eventDate;
      if (d != null && !d.isBefore(DateTime(seenOn.year, seenOn.month, seenOn.day))) {
        t['exam_start'] ??= _isoDate(d);
      }
    case Milestone.examSchedule || Milestone.postponed:
      if (text.contains('city') || text.contains('intimation')) t['exam_city_slip_url'] = u.url;
      final d = u.eventDate;
      if (d != null && !d.isBefore(DateTime(seenOn.year, seenOn.month, seenOn.day))) {
        t['exam_start'] = _isoDate(d); // a newer schedule/postponement notice wins
      }
    case Milestone.answerKey:
      if (text.contains('objection') || text.contains('challenge')) {
        t['challenge_portal_url'] = u.url;
      } else if (text.contains('question paper')) {
        t['question_paper_url'] = u.url;
      } else {
        t['answer_key_url'] = u.url;
        firstDate('answer_key_release');
      }
    case Milestone.result:
      t[text.contains('score') ? 'scorecard_url' : 'merit_list_url'] = u.url;
      firstDate('result_date');
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
