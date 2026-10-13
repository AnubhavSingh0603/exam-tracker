import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../models/jobs_data.dart';
import 'database_service.dart';

/// Result of a load: the jobs and whether they came from the offline cache.
class JobsLoad {
  const JobsLoad(this.file, {required this.fetchedAt, required this.fromCache});

  final JobsFile file;
  final DateTime fetchedAt;
  final bool fromCache;
}

/// Downloads jobs.json from the data branch, keeping the last good copy in
/// SQLite for offline start-up. Uses the ETag so an unchanged file costs a
/// few bytes, not the whole download.
class JobsRepository {
  JobsRepository(this._db, {http.Client? client}) : _client = client ?? http.Client();

  final DatabaseService _db;
  final http.Client _client;

  static const _etagKey = 'jobs.etag';
  static const _timeout = Duration(seconds: 20);

  Uri get _url => Uri.parse('${Env.dataBaseUrl}/jobs.json');

  Future<JobsLoad?> cached() async {
    final cached = await _db.readFeedCache();
    if (cached == null) return null;
    try {
      return JobsLoad(
        JobsFile.fromJson(jsonDecode(cached.$1) as Map<String, dynamic>),
        fetchedAt: cached.$2,
        fromCache: true,
      );
    } catch (_) {
      return null; // a cache written by an older app version: refetch
    }
  }

  /// Network first; falls back to the cache. Throws only when there is neither.
  Future<JobsLoad> load() async {
    final cache = await cached();
    try {
      final prefs = await SharedPreferences.getInstance();
      final etag = cache == null ? null : prefs.getString(_etagKey);
      final res = await _client
          .get(_url, headers: {'Accept': 'application/json', if (etag != null) 'If-None-Match': etag})
          .timeout(_timeout);
      final now = DateTime.now();
      if (res.statusCode == 304 && cache != null) {
        await _db.touchFeedCache(now);
        return JobsLoad(cache.file, fetchedAt: now, fromCache: false);
      }
      if (res.statusCode != 200) {
        throw http.ClientException('jobs.json: HTTP ${res.statusCode}', _url);
      }
      final body = utf8.decode(res.bodyBytes);
      final file = JobsFile.fromJson(jsonDecode(body) as Map<String, dynamic>); // validate before caching
      await _db.cacheFeed(body, now);
      final newEtag = res.headers['etag'];
      if (newEtag != null) await prefs.setString(_etagKey, newEtag);
      return JobsLoad(file, fetchedAt: now, fromCache: false);
    } catch (_) {
      if (cache != null) return cache;
      rethrow;
    }
  }

  void close() => _client.close();
}
