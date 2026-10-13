import 'dart:io';

import 'package:exam_tracker/services/data_source.dart';
import 'package:exam_tracker/services/database_service.dart';
import 'package:exam_tracker/services/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const pages = 'https://owner.github.io/repo';
const raw = 'https://raw.githubusercontent.com/owner/repo/data';
const pagesHost = 'owner.github.io';
const rawHost = 'raw.githubusercontent.com';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a blocked address falls back to the other, which is then tried first', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.host);
      if (req.url.host == pagesHost) throw const SocketException('Connection refused');
      return http.Response('{"notices": []}', 200);
    });
    final source = DataSource(client, bases: [pages, raw]);
    expect((await source.get('notices.json')).base, raw);
    expect((await source.get('notices.json')).base, raw);
    expect(calls, [pagesHost, rawHost, rawHost]); // no second wait on the blocked one
  });

  test('GitHub Pages not switched on yet (404) is skipped as well', () async {
    final client = MockClient(
        (req) async => req.url.host == pagesHost ? http.Response('Not Found', 404) : http.Response('{}', 200));
    expect((await DataSource(client, bases: [pages, raw]).get('jobs.json')).base, raw);
  });

  test('when both are unreachable the error comes through', () async {
    final client = MockClient((_) async => throw const SocketException('offline'));
    await expectLater(DataSource(client, bases: [pages, raw]).get('jobs.json'), throwsA(isA<SocketException>()));
  });

  group('jobs.json', () {
    late Directory dir;
    late DatabaseService db;

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jobs_repo');
      db = await DatabaseService.open(factory: databaseFactoryFfi, path: '${dir.path}/t.db');
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    String file(String generatedAt) => '{"schema": 1, "generated_at": "$generatedAt", "jobs": []}';

    test('ETags go only to the address that issued them; an older copy never replaces a newer one', () async {
      var pagesUp = true;
      final etagSent = <String, String?>{};
      final client = MockClient((req) async {
        etagSent[req.url.host] = req.headers['If-None-Match'];
        if (req.url.host == pagesHost) {
          if (!pagesUp) throw const SocketException('blocked');
          return req.headers['If-None-Match'] == '"p1"'
              ? http.Response('', 304)
              : http.Response(file('2026-10-13T08:00:00Z'), 200, headers: {'etag': '"p1"'});
        }
        // The other address still serves the previous pipeline run.
        return http.Response(file('2026-10-13T04:00:00Z'), 200, headers: {'etag': '"r1"'});
      });
      final repo = JobsRepository(db, client: client, bases: [pages, raw]);
      final newest = DateTime.utc(2026, 10, 13, 8);

      expect((await repo.load()).file.generatedAt.isAtSameMomentAs(newest), isTrue);
      final unchanged = await repo.load();
      expect(etagSent[pagesHost], '"p1"'); // answered 304: nothing downloaded
      expect(unchanged.file.generatedAt.isAtSameMomentAs(newest), isTrue);

      pagesUp = false;
      final fallback = await repo.load();
      expect(etagSent[rawHost], isNull); // Pages' ETag means nothing to raw
      expect(fallback.file.generatedAt.isAtSameMomentAs(newest), isTrue); // kept the newer copy
    });
  });
}
