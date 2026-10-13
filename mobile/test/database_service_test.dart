import 'dart:io';

import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/models/vault_entry.dart';
import 'package:exam_tracker/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseService db;
  final now = DateTime.utc(2026, 10, 11, 12);

  TrackedApplication app(String id, {DateTime? examAt}) => TrackedApplication(
        id: id,
        examName: 'SSC CGL',
        postName: 'Inspector',
        status: ApplicationStatus.applied,
        examAt: examAt,
        totalSeats: 26,
        urSeats: 20,
        quotaSeats: 6,
        category: 'SC',
        createdAt: now,
        updatedAt: now,
      );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await DatabaseService.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  test('round-trips an application including seats and timestamps', () async {
    final exam = now.add(const Duration(days: 30));
    await db.upsertApplication(app('a', examAt: exam));
    final loaded = (await db.getApplication('a'))!;
    expect(loaded.examAt, exam);
    expect(loaded.totalSeats, 26);
    expect(loaded.category, 'SC');
    expect(loaded.calendarSynced, isFalse);
  });

  test('upsert updates in place and keeps the vault (no REPLACE cascade)', () async {
    await db.upsertApplication(app('a'));
    await db.upsertVault(const VaultEntry(appId: 'a', registrationId: 'REG123'));
    await db.upsertApplication(app('a').copyWith(status: ApplicationStatus.admitCardLive));

    expect((await db.getApplication('a'))!.status, ApplicationStatus.admitCardLive);
    expect((await db.getVault('a'))!.registrationId, 'REG123');
  });

  test('calendar refs drive calendarSynced and cascade on delete', () async {
    await db.upsertApplication(app('a'));
    await db.upsertEventRef(const CalendarEventRef(appId: 'a', kind: 'exam', calendarId: '1', eventId: '99'));
    expect((await db.getApplication('a'))!.calendarSynced, isTrue);

    await db.deleteApplication('a');
    expect(await db.getEventRefs('a'), isEmpty);
    expect(await db.getVault('a'), isNull);
  });

  test('archive flag and ordering (dated first, soonest first)', () async {
    await db.upsertApplication(app('later', examAt: now.add(const Duration(days: 40))));
    await db.upsertApplication(app('undated'));
    await db.upsertApplication(app('sooner', examAt: now.add(const Duration(days: 5))));
    await db.setArchived('later', archived: true);

    final all = await db.listApplications();
    expect(all.map((a) => a.id), ['sooner', 'later', 'undated']);
    expect(all.firstWhere((a) => a.id == 'later').archived, isTrue);
  });

  test('feed cache keeps only the latest body', () async {
    await db.cacheFeed('{"v":1}', now);
    await db.cacheFeed('{"v":2}', now);
    expect((await db.readFeedCache())!.$1, '{"v":2}');
  });
  test('timeline and exam-watcher state are stored per application', () async {
    await db.upsertApplication(app('a').copyWith());
    await db.upsertApplication(TrackedApplication(
      id: 'b',
      examName: 'SSC CGL',
      postName: 'Inspector',
      status: ApplicationStatus.applied,
      jobPostId: 'job-1',
      createdAt: now,
      updatedAt: now,
    ));
    await db.saveTimeline('job-1', '{"job_post_id":"job-1","exam_start":"2026-12-14"}');
    await db.saveWatcherState(
      'b',
      status: 'admit_card_live',
      updatesJson: '[{"milestone":"admit_card","title":"Admit Card","url":"https://x"}]',
    );

    final b = (await db.getApplication('b'))!;
    expect(b.timeline?.examStart, DateTime(2026, 12, 14));
    expect(b.effectiveExamAt, DateTime(2026, 12, 14));
    expect(b.displayStatus, TrackerStatus.admitCardLive);
    expect(b.latestUpdate('admit_card')?.url, 'https://x');

    // A local edit (upsert) must not wipe what the server sent.
    await db.upsertApplication(b.copyWith(status: ApplicationStatus.examScheduled));
    final again = (await db.getApplication('b'))!;
    expect(again.watcherStatus, TrackerStatus.admitCardLive);
    expect(again.timeline, isNotNull);
    expect((await db.getApplication('a'))!.timeline, isNull);
  });

  test('upgrading a v1 install keeps applications and vault entries', () async {
    final dir = await Directory.systemTemp.createTemp('exam_tracker_db');
    final path = '${dir.path}/v1.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute("""CREATE TABLE tracked_applications (
          id TEXT PRIMARY KEY, exam_name TEXT NOT NULL, post_name TEXT NOT NULL, organization TEXT,
          status TEXT NOT NULL CHECK (status IN ('applied','admit_card_live','exam_scheduled')),
          deadline_timestamp INTEGER, exam_timestamp INTEGER, admit_card_url TEXT, portal_url TEXT,
          category TEXT, total_seats INTEGER, ur_seats INTEGER, quota_seats INTEGER,
          archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)""");
            await d.execute("""CREATE TABLE credentials_vault (app_id TEXT PRIMARY KEY
          REFERENCES tracked_applications(id) ON DELETE CASCADE, registration_id TEXT, roll_number TEXT,
          notes TEXT, updated_at INTEGER NOT NULL)""");
            await d.execute("""CREATE TABLE calendar_event_refs (app_id TEXT NOT NULL, kind TEXT NOT NULL,
          calendar_id TEXT NOT NULL, android_calendar_event_id TEXT NOT NULL, synced_at INTEGER NOT NULL,
          PRIMARY KEY (app_id, kind))""");
            await d.execute(
                'CREATE TABLE feed_cache (id INTEGER PRIMARY KEY, body TEXT NOT NULL, fetched_at INTEGER NOT NULL)');
            await d.insert('tracked_applications', {
              'id': 'old',
              'exam_name': 'RRB NTPC',
              'post_name': 'Clerk',
              'status': 'applied',
              'created_at': 1,
              'updated_at': 1,
            });
            await d.insert('credentials_vault', {'app_id': 'old', 'roll_number': 'R-42', 'updated_at': 1});
          },
        ));
    await v1.close();

    final upgraded = await DatabaseService.open(factory: databaseFactoryFfi, path: path);
    final old = (await upgraded.getApplication('old'))!;
    expect(old.examName, 'RRB NTPC');
    expect(old.watcherStatus, isNull);
    expect((await upgraded.getVault('old'))!.rollNumber, 'R-42');
    await upgraded.saveWatcherState('old', status: 'result_declared', updatesJson: '[]');
    expect((await upgraded.getApplication('old'))!.displayStatus, TrackerStatus.resultDeclared);
    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
