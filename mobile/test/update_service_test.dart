import 'dart:convert';

import 'package:exam_tracker/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sha = 'a3f1c2d4e5b6978877665544332211009988776655443322110099887766aabb';

void main() {
  test('release number survives the ×10 + ABI version-code scheme', () {
    expect(releaseNumberOf(40), 4); // universal
    expect(releaseNumberOf(42), 4); // arm64-v8a split of the same release
    expect(releaseNumberOf(50) > releaseNumberOf(43), isTrue); // newer universal beats older split
    // What the published split APKs really carry: Flutter adds ABI × 1000.
    expect(releaseNumberOf(2121), 12); // arm64 0.9.2
    expect(releaseNumberOf(1131), 13); // armeabi-v7a 0.10.0
    expect(releaseNumberOf(120), 12); // universal 0.9.2
  });

  test('manifest picks the device ABI, falls back to universal', () {
    final manifest = {
      'version_code': 5,
      'version_name': '0.4.1',
      'min_supported_version_code': 2,
      'release_notes': 'Calmer hero card',
      'apks': {
        'universal': {'url': 'https://github.com/o/r/releases/download/v0.4.1/u.apk', 'sha256': _sha},
        'arm64-v8a': {'url': 'https://github.com/o/r/releases/download/v0.4.1/a64.apk', 'sha256': _sha, 'size_bytes': 9437184},
      },
    };
    final arm = UpdateInfo.fromManifest(manifest, 'arm64-v8a')!;
    expect(arm.apkUrl, endsWith('a64.apk'));
    expect(arm.sizeLabel, '9.0 MB');
    expect(UpdateInfo.fromManifest(manifest, 'x86')!.apkUrl, endsWith('u.apk'));
    expect(arm.isTrustworthy, isTrue);
  });

  test('server payload parses and untrustworthy assets are rejected', () {
    final info = UpdateInfo.fromServer({
      'latest_version_code': 5,
      'version_name': '0.4.1',
      'min_supported_version_code': 1,
      'release_notes': '',
      'apk_url': 'http://insecure.example/app.apk',
      'sha256': _sha,
    });
    expect(info.isTrustworthy, isFalse); // http, not https

    final noHash = UpdateInfo.fromServer({
      'latest_version_code': 5,
      'version_name': '0.4.1',
      'apk_url': 'https://example.org/app.apk',
      'sha256': 'not-a-hash',
    });
    expect(noHash.isTrustworthy, isFalse);
  });

  group('checking GitHub', () {
    final manifest = jsonEncode({
      'version_code': 9,
      'version_name': '0.8.0',
      'apks': {
        'universal': {'url': 'https://github.com/x/releases/download/v0.8.0/a.apk', 'sha256': _sha},
      },
    });

    UpdateService service({bool offline = false}) => UpdateService(
          client: MockClient((_) async => offline ? throw http.ClientException('offline') : http.Response(manifest, 200)),
          manifestUrl: 'https://github.com/x/releases/latest/download/latest.json',
          enabled: true,
        );

    setUp(() {
      // 0.7.1 installed (release 8, arm64 split: versionCode 82).
      PackageInfo.setMockInitialValues(
          appName: 'JobSummit', packageName: 'p', version: '0.7.1', buildNumber: '82', buildSignature: '');
      SharedPreferences.setMockInitialValues({});
    });

    test('a newer release is offered', () async {
      expect((await service().check(force: true))?.info.versionName, '0.8.0');
    });

    test('after "Later" the automatic check stays quiet, but "Check for updates" still offers it', () async {
      await service().skip(9);
      expect(await service().check(force: true), isNull);
      expect((await service().checkNow())?.info.versionName, '0.8.0');
    });

    test('unreachable GitHub: quiet automatically, an error when asked (not "up to date")', () async {
      expect(await service(offline: true).check(force: true), isNull);
      await expectLater(service(offline: true).checkNow(), throwsA(isA<UpdateCheckFailed>()));
    });
  });

  group('real split-APK version codes', () {
    // What the release workflow now publishes for release 13 (0.10.0).
    final manifest = jsonEncode({
      'release': 13,
      'version_code': 1013,
      'version_name': '0.10.0',
      'apks': {
        'universal': {'url': 'https://github.com/jobsummit/JobSummit/releases/download/v0.10.0/a.apk', 'sha256': _sha},
      },
    });

    UpdateService service() => UpdateService(
          client: MockClient((_) async => http.Response(manifest, 200)),
          manifestUrl: 'https://github.com/jobsummit/JobSummit/releases/latest/download/latest.json',
          enabled: true,
        );

    void installed(String versionCode) {
      PackageInfo.setMockInitialValues(
          appName: 'JobSummit', packageName: 'p', version: '0.9.2', buildNumber: versionCode, buildSignature: '');
      SharedPreferences.setMockInitialValues({});
    }

    test('arm64 0.9.2 (version code 2121) is offered 0.10.0', () async {
      installed('2121');
      expect((await service().checkNow())?.info.versionName, '0.10.0');
    });

    test('arm64 0.10.0 (2131) is up to date', () async {
      installed('2131');
      expect(await service().checkNow(), isNull);
    });

    test('apps already on phones (code ~/ 10) also see it, through the inflated version_code', () {
      final oldInstalled = 2121 ~/ 10; // what 0.10.0 and older compute
      expect(1013 > oldInstalled, isTrue);
      expect(1013 > 4131 ~/ 10, isTrue); // even an x86_64 split
    });
  });
}
