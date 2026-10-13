import 'dart:io';

import 'package:exam_tracker/domain/feed_builder.dart';
import 'package:exam_tracker/models/feed.dart';
import 'package:exam_tracker/models/jobs_data.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:exam_tracker/services/calendar_sync_service.dart';
import 'package:exam_tracker/services/database_service.dart';
import 'package:exam_tracker/services/deadline_reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;

final now = DateTime.utc(2026, 10, 14, 6);

/// Records what would have gone into the phone's calendar.
class FakeCalendar extends CalendarSyncService {
  FakeCalendar(super.db);

  final events = <String, DateTime>{}; // eventId -> deadline
  final deleted = <String>[];
  var next = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<(String, String)?> writeJobDeadline({
    required String title,
    required String description,
    required DateTime deadline,
    required DateTime now,
    String? calendarId,
    String? eventId,
    Duration every = const Duration(hours: 4),
  }) async {
    final id = eventId ?? 'e${next++}';
    events[id] = deadline;
    return ('cal', id);
  }

  @override
  Future<void> deleteEvent(String calendarId, String eventId) async {
    deleted.add(eventId);
    events.remove(eventId);
  }
}

List<FeedItem> jobs(Map<String, Duration> closesIn) => buildFeed(
      jobs: JobsFile.fromJson({
        'schema': 1,
        'generated_at': now.toIso8601String(),
        'jobs': [
          for (final MapEntry(key: id, value: d) in closesIn.entries)
            {
              'id': id,
              'organization': 'Org $id',
              'exam_name': 'Exam $id',
              'application_deadline': now.add(d).toIso8601String(),
              'posts': [
                {
                  'id': 'p-$id',
                  'post_name': 'Officer $id',
                  'base_max_age': 32,
                  'age_as_on': '2026-10-01',
                  'min_qualification_level': 'UG',
                  'is_open_to_any_graduate': true,
                  'vacancy': {'ur': 10, 'sc': 3, 'st': 1, 'obc': 5, 'ews': 2, 'total': 21},
                }
              ],
            }
        ],
      }),
      profile: UserProfileData(
        displayName: 'Me',
        dateOfBirth: DateTime(2000, 1, 1),
        category: ReservationCategory.ur,
        qualificationTier: 'UG',
        degreeTitle: 'B_TECH',
      ),
      appliedPostIds: const {},
      now: now,
      fetchedAt: now,
    ).items;

void main() {
  late Directory dir;
  late DatabaseService db;

  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('reminders');
    db = await DatabaseService.open(factory: databaseFactoryFfi, path: '${dir.path}/r.db');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('only jobs closing within a day get a reminder; a reject removes it, a restore brings it back', () async {
    final calendar = FakeCalendar(db);
    final reminders = DeadlineReminders(db, calendar: calendar);
    final open = jobs({'soon': const Duration(hours: 23), 'later': const Duration(days: 3)});

    expect(await reminders.sync(open, now: now), 1);
    expect(calendar.events.values, [now.add(const Duration(hours: 23))]);
    final row = (await db.listJobReminders()).single;
    expect(row['job_post_id'], 'soon');
    expect(row['notified_at'], now.millisecondsSinceEpoch);

    // Swiped left ("not for me"): it's no longer among the open jobs.
    expect(await reminders.sync([for (final j in open) if (j.jobPostId != 'soon') j], now: now), 0);
    expect(calendar.events, isEmpty);
    expect(await db.listJobReminders(), isEmpty);

    // Brought back from the Hidden list.
    expect(await reminders.sync(open, now: now), 1);
    expect(calendar.events, hasLength(1));
  });

  test('the notification repeats about every 4 hours; switching the reminders off removes everything', () async {
    final calendar = FakeCalendar(db);
    final reminders = DeadlineReminders(db, calendar: calendar);
    final open = jobs({'soon': const Duration(hours: 20)});

    await reminders.sync(open, now: now);
    final hourLater = now.add(const Duration(hours: 1));
    await reminders.sync(open, now: hourLater);
    expect((await db.listJobReminders()).single['notified_at'], now.millisecondsSinceEpoch); // not yet again

    final fourLater = now.add(const Duration(hours: 4));
    await reminders.sync(open, now: fourLater);
    expect((await db.listJobReminders()).single['notified_at'], fourLater.millisecondsSinceEpoch);
    expect(calendar.events, hasLength(1)); // the same event, not a new one each time

    await reminders.sync(open, now: fourLater, enabled: false);
    expect(calendar.events, isEmpty);
    expect(await db.listJobReminders(), isEmpty);
  });
}
