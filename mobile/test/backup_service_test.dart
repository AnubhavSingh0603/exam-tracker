import 'dart:convert';
import 'dart:io';

import 'package:exam_tracker/models/backup_snapshot.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/models/user_profile.dart';
import 'package:exam_tracker/models/vault_entry.dart';
import 'package:exam_tracker/services/backup_service.dart';
import 'package:exam_tracker/services/database_service.dart';
import 'package:exam_tracker/services/drive_backup_client.dart';
import 'package:exam_tracker/services/profile_store.dart';
import 'package:exam_tracker/services/secret_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory Google Drive app folder holding the one backup file.
class FakeDrive {
  String? fileId;
  String? content;
  int creates = 0;
  int updates = 0;
  int rejectNext401 = 0;
  int rejectedTokens = 0;

  BackupSnapshot get snapshot => BackupSnapshot.fromJson(jsonDecode(content!) as Map<String, dynamic>);

  DriveBackupClient client() => DriveBackupClient(
        authHeaders: () async => {'Authorization': 'Bearer t'},
        onRejectedToken: (_) async => rejectedTokens++,
        client: MockClient(_handle),
      );

  Future<http.Response> _handle(http.Request req) async {
    if (rejectNext401 > 0) {
      rejectNext401--;
      return http.Response('{"error":{"code":401}}', 401);
    }
    final path = req.url.path;
    if (req.method == 'GET' && path == '/drive/v3/files') {
      expect(req.url.queryParameters['spaces'], 'appDataFolder');
      return http.Response(
          jsonEncode({
            'files': [
              if (fileId != null) {'id': fileId, 'modifiedTime': '2026-10-20T00:00:00Z'}
            ]
          }),
          200);
    }
    if (req.method == 'GET' && path == '/drive/v3/files/$fileId') return http.Response(content!, 200);
    if (req.method == 'POST' && path == '/upload/drive/v3/files') {
      final boundary = req.headers['content-type']!.split('boundary=').last;
      final part = req.body.split('--$boundary')[2]; // [preamble, metadata, file, --]
      final metadata = jsonDecode(req.body.split('--$boundary')[1].split('\r\n\r\n')[1].trim());
      expect(metadata['parents'], ['appDataFolder']);
      content = part.split('\r\n\r\n')[1].trimRight();
      fileId = 'f1';
      creates++;
      return http.Response('{"id":"f1"}', 200);
    }
    if (req.method == 'PATCH' && path == '/upload/drive/v3/files/$fileId') {
      content = req.body;
      updates++;
      return http.Response('{"id":"$fileId"}', 200);
    }
    return http.Response('unexpected ${req.method} ${req.url}', 400);
  }
}

void main() {
  late Directory dir;
  var phones = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async => dir = await Directory.systemTemp.createTemp('backup_test'));
  tearDown(() async => dir.delete(recursive: true));

  /// A brand-new phone (or a reinstall): empty database, preferences and secure storage.
  Future<(DatabaseService, SecretStore)> newPhone() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final db =
        await DatabaseService.open(factory: databaseFactoryFfi, path: '${dir.path}/phone${phones++}.db');
    return (db, SecretStore());
  }

  final now = DateTime.utc(2026, 10, 20, 9);
  TrackedApplication app(String id) => TrackedApplication(
        id: id,
        examName: 'SSC CGL 2026',
        postName: 'Inspector $id',
        status: ApplicationStatus.examScheduled,
        examAt: DateTime.utc(2026, 12, 14, 4),
        createdAt: now,
        updatedAt: now,
      );
  final profile = UserProfileData(
    displayName: 'Me',
    dateOfBirth: DateTime(2000, 1, 1),
    category: ReservationCategory.sc,
    qualificationTier: 'UG',
    degreeTitle: 'B_TECH',
  );

  test('first backup, then a reinstall restores everything', () async {
    final drive = FakeDrive();
    final (dbA, secretsA) = await newPhone();
    await dbA.upsertApplication(app('a'));
    await dbA.upsertVault(const VaultEntry(appId: 'a', registrationId: 'REG-1', rollNumber: 'ROLL-9'));
    await secretsA.writePassword('a', 'portal-pw');
    await dbA.upsertEventRef(const CalendarEventRef(appId: 'a', kind: 'exam', calendarId: 'c', eventId: 'e'));
    await ProfileStore.write(profile);

    final first = await BackupService(db: dbA, secrets: secretsA, drive: drive.client()).sync(now: now);
    expect(first.hadBackup, isFalse);
    expect(drive.creates, 1);
    expect(drive.snapshot.passwords, {'a': 'portal-pw'});
    await dbA.close();

    // Uninstall + reinstall (or a new phone): nothing local.
    final (dbB, secretsB) = await newPhone();
    final restored = await BackupService(db: dbB, secrets: secretsB, drive: drive.client()).sync(now: now);
    expect(restored.hadBackup, isTrue);
    expect(restored.restoredIds, ['a']);
    expect(restored.profileRestored, isTrue);
    expect(restored.calendarWanted, ['a']); // had calendar events on the old phone
    final a = (await dbB.getApplication('a'))!;
    expect(a.status, ApplicationStatus.examScheduled);
    expect(a.examAt, DateTime.utc(2026, 12, 14, 4));
    expect((await dbB.getVault('a'))!.rollNumber, 'ROLL-9');
    expect(await secretsB.readPassword('a'), 'portal-pw');
    expect((await ProfileStore.read())?.degreeTitle, 'B_TECH');
    expect(drive.updates, 1); // the merged copy went back up
    await dbB.close();
  });

  test('a removal on another phone removes the exam here too', () async {
    final drive = FakeDrive()
      ..fileId = 'f1'
      ..content = jsonEncode(BackupSnapshot(
        savedAt: now,
        deviceId: 'other',
        tombstones: {'gone': now},
      ).toJson());
    final (db, secrets) = await newPhone();
    await db.upsertApplication(app('gone').copyWith(updatedAt: now.subtract(const Duration(days: 1))));
    await secrets.writePassword('gone', 'pw');
    await db.upsertApplication(app('kept'));

    final outcome = await BackupService(db: db, secrets: secrets, drive: drive.client()).sync(now: now);
    expect(outcome.removedIds, ['gone']);
    expect(await db.getApplication('gone'), isNull);
    expect(await secrets.readPassword('gone'), isNull);
    expect(await db.getApplication('kept'), isNotNull);
    expect(drive.snapshot.applications.keys, ['kept']);
    expect(drive.snapshot.tombstones.keys, ['gone']);
    await db.close();
  });

  test('"start fresh" replaces this phone\'s data with the backup', () async {
    final drive = FakeDrive()
      ..fileId = 'f1'
      ..content = jsonEncode(BackupSnapshot(
        savedAt: now,
        deviceId: 'other',
        applications: {
          'theirs': {...app('theirs').toRow(), 'calendar_synced': 0}
        },
      ).toJson());
    final (db, secrets) = await newPhone();
    await db.upsertApplication(app('mine'));
    await ProfileStore.write(profile);

    await BackupService(db: db, secrets: secrets, drive: drive.client()).sync(replaceLocal: true, now: now);
    expect([for (final a in await db.listApplications()) a.id], ['theirs']);
    expect(await ProfileStore.read(), isNull); // their backup had no profile
    expect(drive.snapshot.applications.keys, ['theirs']);
    await db.close();
  });

  test('an expired token is refreshed once and the request retried', () async {
    final drive = FakeDrive()..rejectNext401 = 1;
    final (db, secrets) = await newPhone();
    await BackupService(db: db, secrets: secrets, drive: drive.client()).sync(now: now);
    expect(drive.rejectedTokens, 1);
    expect(drive.creates, 1);
    await db.close();
  });
}
