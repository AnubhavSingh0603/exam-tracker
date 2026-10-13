import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'exam_timeline.dart';
import 'links.dart';

enum ApplicationStatus {
  applied('applied', 'Applied'),
  admitCardLive('admit_card_live', 'Admit card live'),
  examScheduled('exam_scheduled', 'Exam scheduled');

  const ApplicationStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ApplicationStatus fromWire(String? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => ApplicationStatus.applied);
}

/// Exam-watcher progress (backend `ApplicationStatus` minus "discovered").
/// Local [ApplicationStatus] covers what the user sets by hand; this is what the
/// watcher found on the exam's notice boards. The card shows whichever is further.
enum TrackerStatus {
  applied('applied', 'Applied'),
  admitCardLive('admit_card_live', 'Admit Card Live'),
  examScheduled('exam_scheduled', 'Exam Scheduled'),
  answerKeyLive('answer_key_live', 'Answer Key Released'),
  resultDeclared('result_declared', 'Result Declared');

  const TrackerStatus(this.wire, this.label);
  final String wire;
  final String label;

  static TrackerStatus? fromWire(String? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// One notice the exam watcher found (stored newest first in `updates_json`).
@immutable
class ExamUpdate {
  const ExamUpdate({
    required this.milestone,
    required this.title,
    required this.url,
    this.eventDate,
    this.detectedAt,
    this.source,
  });

  final String milestone; // admit_card | exam_schedule | postponed | answer_key | result
  final String title;
  final String url;
  final DateTime? eventDate;
  final DateTime? detectedAt;
  final String? source; // official | aggregator

  static DateTime? _day(Object? v) {
    final d = v is String ? DateTime.tryParse(v) : null;
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory ExamUpdate.fromJson(Map<String, dynamic> j) => ExamUpdate(
        milestone: j['milestone'] as String? ?? '',
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        eventDate: _day(j['event_date']),
        detectedAt: j['detected_at'] is String ? DateTime.tryParse(j['detected_at'] as String) : null,
        source: j['source'] as String?,
      );

  Map<String, Object?> toJson() => {
        'milestone': milestone,
        'title': title,
        'url': url,
        'event_date': eventDate == null ? null : _iso(eventDate!),
        'detected_at': detectedAt?.toUtc().toIso8601String(),
        'source': source,
      };
}

int? _ms(DateTime? d) => d?.toUtc().millisecondsSinceEpoch;
DateTime? _dt(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : null;

@immutable
class TrackedApplication {
  const TrackedApplication({
    required this.id,
    required this.examName,
    required this.postName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.organization,
    this.deadline,
    this.examAt,
    this.admitCardUrl,
    this.portalUrl,
    this.applyUrl,
    this.category,
    this.totalSeats,
    this.urSeats,
    this.quotaSeats,
    this.archived = false,
    this.calendarSynced = false,
    this.jobPostId,
    this.timeline,
    this.timelineRaw,
    this.watcherStatus,
    this.updates = const [],
  });

  /// Backend `post_detail_id` when tracked from the feed, so the feed can hide it.
  final String id;
  final String examName;
  final String postName;
  final String? organization;
  final ApplicationStatus status;
  final DateTime? deadline;
  final DateTime? examAt;
  final String? admitCardUrl;

  /// The organisation's website: the exam watcher checks it for notices.
  final String? portalUrl;

  /// The registration / application login page, when a job site linked it.
  final String? applyUrl;
  final String? category; // UR / SC / ST / OBC / EWS
  final int? totalSeats;
  final int? urSeats;
  final int? quotaSeats;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Derived (from calendar_event_refs), never written back.
  final bool calendarSynced;

  /// Backend `job_post_id` (the notification), used to refresh [timeline].
  final String? jobPostId;

  /// Post-application milestones from the server; null until first fetched.
  final ExamTimeline? timeline;

  /// The same timeline as stored JSON, so the exam watcher can add to it.
  final Map<String, dynamic>? timelineRaw;

  /// What the exam watcher found on notice boards; null until it finds something.
  final TrackerStatus? watcherStatus;

  /// Watcher notices, newest first.
  final List<ExamUpdate> updates;

  /// The further of what the user set and what the watcher found.
  TrackerStatus get displayStatus {
    final local = switch (status) {
      ApplicationStatus.applied => TrackerStatus.applied,
      ApplicationStatus.admitCardLive => TrackerStatus.admitCardLive,
      ApplicationStatus.examScheduled => TrackerStatus.examScheduled,
    };
    final found = watcherStatus;
    return found != null && found.index > local.index ? found : local;
  }

  /// Newest watcher notice of a kind ('admit_card', 'result', ...).
  ExamUpdate? latestUpdate(String milestone) {
    for (final u in updates) {
      if (u.milestone == milestone) return u;
    }
    return null;
  }

  /// Exam date the user entered, else the one the notification announced.
  DateTime? get effectiveExamAt => examAt ?? timeline?.examStart;

  /// The date that matters *now* for this application.
  DateTime? get focusDate => switch (status) {
        ApplicationStatus.applied => effectiveExamAt ?? deadline,
        ApplicationStatus.admitCardLive || ApplicationStatus.examScheduled => effectiveExamAt,
      };

  /// Where you log in to pay, correct the form or download the admit card: the
  /// application page, else the official website.
  String? get applicationUrl => preferredUrl(applyUrl, portalUrl);

  /// Best link for "application login" / "download admit card".
  String? get actionUrl => status == ApplicationStatus.admitCardLive
      ? (admitCardUrl ?? timeline?.admitCardUrl ?? applicationUrl)
      : applicationUrl;

  static List<ExamUpdate> _updates(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return [
        for (final u in jsonDecode(raw) as List<dynamic>) ExamUpdate.fromJson(u as Map<String, dynamic>)
      ];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic>? _timelineRaw(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null; // unreadable: rebuilt by the next watcher run
    }
  }

  static ExamTimeline? _timeline(Map<String, dynamic>? raw) {
    if (raw == null || raw['job_post_id'] is! String) return null;
    try {
      return ExamTimeline.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'exam_name': examName,
        'post_name': postName,
        'organization': organization,
        'status': status.wire,
        'deadline_timestamp': _ms(deadline),
        'exam_timestamp': _ms(examAt),
        'admit_card_url': admitCardUrl,
        'portal_url': portalUrl,
        'apply_url': applyUrl,
        'category': category,
        'total_seats': totalSeats,
        'ur_seats': urSeats,
        'quota_seats': quotaSeats,
        'archived': archived ? 1 : 0,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
        'job_post_id': jobPostId,
        // timeline/server state is written separately (DatabaseService.saveTimeline,
        // saveWatcherState) so a local edit never overwrites it with a stale copy.
      };

  factory TrackedApplication.fromRow(Map<String, Object?> r) => TrackedApplication(
        id: r['id']! as String,
        examName: r['exam_name']! as String,
        postName: r['post_name']! as String,
        organization: r['organization'] as String?,
        status: ApplicationStatus.fromWire(r['status'] as String?),
        deadline: _dt(r['deadline_timestamp']),
        examAt: _dt(r['exam_timestamp']),
        admitCardUrl: r['admit_card_url'] as String?,
        portalUrl: r['portal_url'] as String?,
        applyUrl: r['apply_url'] as String?,
        category: r['category'] as String?,
        totalSeats: r['total_seats'] as int?,
        urSeats: r['ur_seats'] as int?,
        quotaSeats: r['quota_seats'] as int?,
        archived: r['archived'] == 1,
        calendarSynced: r['calendar_synced'] == 1,
        createdAt: _dt(r['created_at'])!,
        updatedAt: _dt(r['updated_at'])!,
        jobPostId: r['job_post_id'] as String?,
        timeline: _timeline(_timelineRaw(r['timeline_json'])),
        timelineRaw: _timelineRaw(r['timeline_json']),
        // Column name kept from the server era; it now holds the phone watcher's status.
        watcherStatus: TrackerStatus.fromWire(r['server_status'] as String?),
        updates: _updates(r['updates_json']),
      );

  TrackedApplication copyWith({
    ApplicationStatus? status,
    DateTime? examAt,
    String? admitCardUrl,
    bool? archived,
    DateTime? updatedAt,
  }) =>
      TrackedApplication(
        id: id,
        examName: examName,
        postName: postName,
        organization: organization,
        status: status ?? this.status,
        deadline: deadline,
        examAt: examAt ?? this.examAt,
        admitCardUrl: admitCardUrl ?? this.admitCardUrl,
        portalUrl: portalUrl,
        applyUrl: applyUrl,
        category: category,
        totalSeats: totalSeats,
        urSeats: urSeats,
        quotaSeats: quotaSeats,
        archived: archived ?? this.archived,
        calendarSynced: calendarSynced,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        jobPostId: jobPostId,
        timeline: timeline,
        timelineRaw: timelineRaw,
        watcherStatus: watcherStatus,
        updates: updates,
      );
}
