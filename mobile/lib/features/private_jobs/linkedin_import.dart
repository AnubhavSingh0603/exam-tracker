import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// What a LinkedIn data export (Settings › Data privacy › Get a copy of your data)
/// says about you. Read on the phone from the ZIP LinkedIn emails you; nothing is
/// uploaded anywhere.
@immutable
class LinkedInData {
  const LinkedInData({
    this.headline = '',
    this.education = const [],
    this.positions = const [],
    this.skills = const [],
  });

  final String headline;
  final List<LinkedInEducation> education;
  final List<LinkedInPosition> positions;
  final List<String> skills;

  bool get isEmpty => headline.isEmpty && education.isEmpty && positions.isEmpty && skills.isEmpty;

  /// Months worked, overlapping jobs counted once, current jobs up to [now].
  int monthsOfExperience(DateTime now) {
    final spans = [
      for (final p in positions)
        if (p.start != null) (p.start!, p.end ?? now),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var months = 0;
    DateTime? coveredUntil;
    for (final (start, end) in spans) {
      final from = coveredUntil != null && coveredUntil.isAfter(start) ? coveredUntil : start;
      if (end.isAfter(from)) months += (end.year - from.year) * 12 + end.month - from.month;
      if (coveredUntil == null || end.isAfter(coveredUntil)) coveredUntil = end;
    }
    return months;
  }

  /// Years, rounded down to the half year: never more experience than you have.
  double yearsOfExperience(DateTime now) => (monthsOfExperience(now) / 6).floor() / 2;

  /// JobSummit degree codes (DegreeOption.code) the education list names.
  List<String> degreeCodes() => {
        for (final e in education)
          if (degreeCodeFor(e.degree) case final code?) code,
      }.toList();

  /// The latest job title, as a starting "target role".
  String? get latestTitle {
    final dated = [...positions]..sort((a, b) => (b.start ?? DateTime(0)).compareTo(a.start ?? DateTime(0)));
    return dated.isEmpty ? null : dated.first.title;
  }
}

@immutable
class LinkedInEducation {
  const LinkedInEducation({required this.school, required this.degree, this.start, this.end});
  final String school;
  final String degree;
  final DateTime? start;
  final DateTime? end;
}

@immutable
class LinkedInPosition {
  const LinkedInPosition({required this.company, required this.title, this.start, this.end});
  final String company;
  final String title;
  final DateTime? start;
  final DateTime? end; // null = current
}

/// Reads the export ZIP. Throws [FormatException] if it isn't one.
LinkedInData readLinkedInExport(List<int> zipBytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw const FormatException('That isn’t a ZIP file. Pick the file LinkedIn emailed you.');
  }
  List<Map<String, String>>? table(String name) {
    for (final f in archive.files) {
      if (f.isFile && f.name.split('/').last.toLowerCase() == name.toLowerCase()) {
        return parseLinkedInCsv(utf8.decode(f.content, allowMalformed: true));
      }
    }
    return null;
  }

  final profile = table('Profile.csv') ?? const [];
  final education = table('Education.csv') ?? const [];
  final positions = table('Positions.csv') ?? const [];
  final skills = table('Skills.csv') ?? const [];
  final data = LinkedInData(
    headline: profile.isEmpty ? '' : (profile.first['Headline'] ?? '').trim(),
    education: [
      for (final r in education)
        if ((r['Degree Name'] ?? '').trim().isNotEmpty || (r['School Name'] ?? '').trim().isNotEmpty)
          LinkedInEducation(
            school: (r['School Name'] ?? '').trim(),
            degree: (r['Degree Name'] ?? '').trim(),
            start: parseLinkedInDate(r['Start Date']),
            end: parseLinkedInDate(r['End Date']),
          ),
    ],
    positions: [
      for (final r in positions)
        if ((r['Title'] ?? '').trim().isNotEmpty)
          LinkedInPosition(
            company: (r['Company Name'] ?? '').trim(),
            title: (r['Title'] ?? '').trim(),
            start: parseLinkedInDate(r['Started On']),
            end: parseLinkedInDate(r['Finished On']),
          ),
    ],
    skills: [
      for (final r in skills)
        if ((r['Name'] ?? '').trim().isNotEmpty) r['Name']!.trim(),
    ],
  );
  if (data.isEmpty && profile.isEmpty && education.isEmpty && positions.isEmpty) {
    throw const FormatException('No LinkedIn profile files in that ZIP. Pick the export LinkedIn emailed you.');
  }
  return data;
}

/// CSV with quoted fields (commas, quotes and line breaks inside quotes). Rows before
/// the header (LinkedIn sometimes adds "Notes:" lines) are skipped: the header is the
/// first row whose cells look like column names.
List<Map<String, String>> parseLinkedInCsv(String raw) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  final text = raw.startsWith('﻿') ? raw.substring(1) : raw;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((v) => v.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);

  const known = {'Headline', 'Degree Name', 'School Name', 'Title', 'Company Name', 'Name', 'First Name'};
  final headerAt = rows.indexWhere((r) => r.any(known.contains));
  if (headerAt < 0) return const [];
  final header = rows[headerAt];
  return [
    for (final r in rows.skip(headerAt + 1))
      {for (var i = 0; i < math.min(header.length, r.length); i++) header[i].trim(): r[i]},
  ];
}

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// "Jan 2020", "Jan 15, 2020", "2020", "2020-01": the first of that month.
DateTime? parseLinkedInDate(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return null;
  final year = RegExp(r'(19|20)\d\d').firstMatch(s);
  if (year == null) return null;
  final y = int.parse(year.group(0)!);
  for (var m = 0; m < 12; m++) {
    if (s.contains(_months[m])) return DateTime(y, m + 1);
  }
  final numeric = RegExp(r'(19|20)\d\d-(\d\d)').firstMatch(s);
  if (numeric != null) return DateTime(y, int.parse(numeric.group(2)!).clamp(1, 12));
  return DateTime(y);
}

/// LinkedIn's free-text degree name -> JobSummit DegreeOption.code, or null.
String? degreeCodeFor(String degree) {
  final d = ' ${degree.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  bool has(String pattern) => RegExp(pattern).hasMatch(d);
  if (has(r' (ph ?d|doctor of philosophy) ')) return 'PHD';
  if (has(r' (m ?tech|m e|master of (technology|engineering)) ')) return 'M_TECH';
  if (has(r' (b ?tech|b e|be|bachelor of (technology|engineering)) ')) return 'B_TECH';
  if (has(r' (mba|pgdm|master of business administration) ')) return 'MBA';
  if (has(r' (mca|master of computer applications?) ')) return 'MCA';
  if (has(r' (bca|bachelor of computer applications?) ')) return 'BCA';
  if (has(r' (m ?ed|master of education) ')) return 'M_ED';
  if (has(r' (b ?ed|bachelor of education) ')) return 'B_ED';
  if (has(r' (ll ?m|master of laws?) ')) return 'LLM';
  if (has(r' (ll ?b|bachelor of laws?|ba ll ?b|bba ll ?b) ')) return 'LLB';
  if (has(r' (m ?pharm\w*|master of pharmacy) ')) return 'M_PHARM';
  if (has(r' (b ?pharm\w*|bachelor of pharmacy) ')) return 'B_PHARM';
  if (has(r' (mbbs|bds|bachelor of (medicine|dental surgery)) ')) return 'MBBS';
  if (has(r' (b ?arch|bachelor of architecture) ')) return 'B_ARCH';
  if (has(r' (m ?com|master of commerce) ')) return 'M_COM';
  if (has(r' (b ?com|bachelor of commerce) ')) return 'B_COM';
  if (has(r' (m ?sc|master of science|ms) ')) return 'M_SC';
  if (has(r' (b ?sc|bachelor of science|bs) ')) return 'B_SC';
  if (has(r' (bba|bms|bachelor of (business|management)) ')) return 'BBA';
  if (has(r' (m ?a|master of arts) ')) return 'M_A';
  if (has(r' (b ?a|bachelor of arts) ')) return 'B_A';
  if (has(r' (diploma|polytechnic) ')) return 'DIPLOMA';
  if (has(r' (12th|xii|higher secondary|intermediate|hsc) ')) return 'CLASS_12';
  return null;
}
