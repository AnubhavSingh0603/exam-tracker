import 'package:flutter/foundation.dart';

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
    this.category,
    this.totalSeats,
    this.urSeats,
    this.quotaSeats,
    this.archived = false,
    this.calendarSynced = false,
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
  final String? portalUrl;
  final String? category; // UR / SC / ST / OBC / EWS
  final int? totalSeats;
  final int? urSeats;
  final int? quotaSeats;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Derived (from calendar_event_refs), never written back.
  final bool calendarSynced;

  /// The date that matters *now* for this application.
  DateTime? get focusDate => switch (status) {
        ApplicationStatus.applied => examAt ?? deadline,
        ApplicationStatus.admitCardLive || ApplicationStatus.examScheduled => examAt,
      };

  /// Best link for "open portal" / "download admit card".
  String? get actionUrl => status == ApplicationStatus.admitCardLive
      ? (admitCardUrl ?? portalUrl)
      : portalUrl;

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
        'category': category,
        'total_seats': totalSeats,
        'ur_seats': urSeats,
        'quota_seats': quotaSeats,
        'archived': archived ? 1 : 0,
        'created_at': _ms(createdAt),
        'updated_at': _ms(updatedAt),
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
        category: r['category'] as String?,
        totalSeats: r['total_seats'] as int?,
        urSeats: r['ur_seats'] as int?,
        quotaSeats: r['quota_seats'] as int?,
        archived: r['archived'] == 1,
        calendarSynced: r['calendar_synced'] == 1,
        createdAt: _dt(r['created_at'])!,
        updatedAt: _dt(r['updated_at'])!,
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
        category: category,
        totalSeats: totalSeats,
        urSeats: urSeats,
        quotaSeats: quotaSeats,
        archived: archived ?? this.archived,
        calendarSynced: calendarSynced,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
