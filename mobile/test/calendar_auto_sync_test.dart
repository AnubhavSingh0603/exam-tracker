import 'dart:io';

import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/services/calendar_sync_service.dart';
import 'package:exam_tracker/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;

final now = DateTime.utc(2026, 10, 17, 6);

/// Records which exams would have been written to the calendar.
class FakeCalendar extends CalendarSyncService {
  FakeCalendar(super.db, {this.allowed = true});

  final bool allowed;
  final synced = <String>[];

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<CalendarSyncResult> syncExamToCalendar(TrackedApplication app, {DateTime? now}) async {
    synced.add(app.id);
    return const CalendarSyncSuccess(2);
  }
}

TrackedApplication exam(String id, {bool archived = false, bool synced = false}) => TrackedApplication(
      id: id,
      examName: 'Exam $id',
      postName: 'Post',
      status: ApplicationStatus.applied,
      deadline: now.add(const Duration(days: 10)),
      archived: archived,
      calendarSynced: synced,
      createdAt: now,
      updatedAt: now,
    );

void main() {
  late Directory dir;
  late DatabaseService db;

  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('calendar');
    db = await DatabaseService.open(factory: databaseFactoryFfi, path: '${dir.path}/c.db');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('adds active exams not in the calendar yet; skips archived and already added', () async {
    final calendar = FakeCalendar(db);
    final added = await calendar.syncAll([exam('a'), exam('b', archived: true), exam('c', synced: true), exam('d')]);
    expect(calendar.synced, ['a', 'd']);
    expect(added, 2);
  });

  test('never asks: without calendar access it does nothing', () async {
    final calendar = FakeCalendar(db, allowed: false);
    expect(await calendar.syncAll([exam('a')]), 0);
    expect(calendar.synced, isEmpty);
  });

  test('the switch is off until turned on', () async {
    expect(await CalendarAutoSync.enabled(), isFalse);
    await CalendarAutoSync.setEnabled(true);
    expect(await CalendarAutoSync.enabled(), isTrue);
  });
}
