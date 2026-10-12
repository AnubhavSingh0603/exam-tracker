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
}
