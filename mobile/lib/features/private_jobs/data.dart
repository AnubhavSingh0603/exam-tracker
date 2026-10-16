import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/data_source.dart';
import 'models.dart';

/// private_jobs.json from the data pipeline, with the last good copy kept in the
/// app's files so the feed works offline.
class PrivateJobsRepository {
  PrivateJobsRepository(this._client, {Future<Directory> Function()? dir, List<String>? bases})
      : _dir = dir ?? getApplicationSupportDirectory,
        _bases = bases;

  final http.Client _client;
  final Future<Directory> Function() _dir;
  final List<String>? _bases;

  Future<File> _cache() async => File(p.join((await _dir()).path, 'private_jobs.json'));

  /// Fresh from GitHub when reachable, else the last copy; empty before the first.
  Future<({List<PrivateJob> jobs, DateTime? generatedAt, bool fresh})> load() async {
    final cache = await _cache();
    try {
      final res = (await DataSource(_client, bases: _bases).get('private_jobs.json')).response;
      if (res.statusCode == 200) {
        final parsed = _parse(utf8.decode(res.bodyBytes));
        await cache.writeAsBytes(res.bodyBytes, flush: true);
        return (jobs: parsed.$1, generatedAt: parsed.$2, fresh: true);
      }
    } catch (_) {
      // Offline or not published yet: the cached copy below.
    }
    if (await cache.exists()) {
      final parsed = _parse(await cache.readAsString());
      return (jobs: parsed.$1, generatedAt: parsed.$2, fresh: false);
    }
    return (jobs: const <PrivateJob>[], generatedAt: null, fresh: false);
  }

  static (List<PrivateJob>, DateTime?) _parse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    return (
      [for (final job in (j['jobs'] as List<dynamic>? ?? const [])) PrivateJob.fromJson(job as Map<String, dynamic>)],
      DateTime.tryParse(j['generated_at'] as String? ?? ''),
    );
  }
}

/// The private profile, in the Keystore-backed encrypted storage under its own key,
/// apart from the Govt profile.
class PrivateProfileStore {
  PrivateProfileStore([FlutterSecureStorage? storage])
      : _storage =
            storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;
  static const _key = 'private.profile';

  Future<PrivateProfile> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? const PrivateProfile() : PrivateProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PrivateProfile();
    }
  }

  Future<void> write(PrivateProfile profile) => _storage.write(key: _key, value: jsonEncode(profile.toJson()));
}

/// Private applications in their own database file, so the Govt database and its
/// migrations never change for this feature.
class PrivateApplicationsStore {
  PrivateApplicationsStore._(this._db);

  final Database _db;

  static Future<PrivateApplicationsStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'private_jobs.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE applications (
            id         TEXT PRIMARY KEY,
            job_id     TEXT,
            company    TEXT NOT NULL,
            title      TEXT NOT NULL,
            url        TEXT,
            stage      TEXT NOT NULL,
            notes      TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )'''),
      ),
    );
    return PrivateApplicationsStore._(db);
  }

  Future<List<PrivateApplication>> list() async => [
        for (final r in await _db.query('applications', orderBy: 'updated_at DESC')) PrivateApplication.fromRow(r),
      ];

  Future<void> save(PrivateApplication app) =>
      _db.insert('applications', app.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(String id) => _db.delete('applications', where: 'id = ?', whereArgs: [id]);

  Future<void> close() => _db.close();
}
