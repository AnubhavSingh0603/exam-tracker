import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:exam_tracker/services/auto_update.dart';
import 'package:exam_tracker/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:self_update/self_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInstaller implements SelfUpdate {
  _FakeInstaller(this.dir);

  final String dir;
  bool silent = true;
  bool unmetered = true;
  bool appVisible = false;
  final installed = <(String, bool)>[];

  @override
  Future<SelfUpdateStatus> status() async => SelfUpdateStatus(
        sdk: 34,
        canInstall: true,
        selfInstalled: silent,
        silent: silent,
        unmetered: unmetered,
        appVisible: appVisible,
        updatesDir: dir,
      );

  @override
  Future<void> install(String path, {required bool interactive}) async => installed.add((path, interactive));
}

void main() {
  final apkBytes = List<int>.generate(50000, (i) => i % 251);
  late Directory tmp;
  late _FakeInstaller installer;
  late int apkRequests;
  late List<int> served;

  String manifest(int code) => jsonEncode({
        'version_code': code,
        'version_name': '0.$code.0',
        'apks': {
          'universal': {
            'url': 'https://github.com/jobsummit/JobSummit/releases/download/v/a.apk',
            'sha256': sha256.convert(apkBytes).toString(),
            'size_bytes': apkBytes.length,
          },
        },
      });

  UpdateService service({int latest = 9}) => UpdateService(
        client: MockClient((req) async {
          if (req.url.path.endsWith('latest.json')) return http.Response(manifest(latest), 200);
          apkRequests++;
          return http.Response.bytes(served, 200);
        }),
        manifestUrl: 'https://github.com/jobsummit/JobSummit/releases/latest/download/latest.json',
        enabled: true,
        installer: installer,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('updates');
    installer = _FakeInstaller(tmp.path);
    apkRequests = 0;
    served = apkBytes;
    // 0.8.x installed: release 8 (arm64 split, versionCode 82); GitHub has release 9.
    PackageInfo.setMockInitialValues(
        appName: 'JobSummit', packageName: 'p', version: '0.8.0', buildNumber: '82', buildSignature: '');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => tmp.delete(recursive: true));

  List<String> files() => [for (final f in tmp.listSync()) f.uri.pathSegments.last];

  test('on Wi-Fi while the app is closed: downloads, verifies and installs without asking', () async {
    expect(await AutoUpdater(service()).run(), AutoUpdateResult.installing);
    expect(files(), ['jobsummit-9.apk']);
    expect(installer.installed.single.$2, isFalse); // not interactive: silent
  });

  test('on mobile data it waits for Wi-Fi and downloads nothing', () async {
    installer.unmetered = false;
    expect(await AutoUpdater(service()).run(), AutoUpdateResult.waitingForWifi);
    expect(apkRequests, 0);
  });

  test('while the app is in use it only downloads; leaving the app installs it', () async {
    final auto = AutoUpdater(service());
    expect(await auto.run(appInUse: true), AutoUpdateResult.ready);
    expect(installer.installed, isEmpty);
    expect(await auto.installIfReady(), AutoUpdateResult.installing);
    expect(installer.installed.single.$1, endsWith('jobsummit-9.apk'));
  });

  test('where Android still asks (first update), it downloads and leaves the prompt to the app', () async {
    installer.silent = false;
    expect(await AutoUpdater(service()).run(), AutoUpdateResult.ready);
    expect(installer.installed, isEmpty);
    expect(files(), ['jobsummit-9.apk']);
  });

  test('a download is reused, not fetched twice', () async {
    installer.unmetered = true;
    final auto = AutoUpdater(service());
    await auto.run(appInUse: true);
    await auto.run(appInUse: true);
    expect(apkRequests, 1);
  });

  test('a damaged download is thrown away and never installed', () async {
    served = [...apkBytes]..[100] ^= 0xff;
    expect(await AutoUpdater(service()).run(), AutoUpdateResult.offline);
    expect(files(), isEmpty);
    expect(installer.installed, isEmpty);
  });

  test('a leftover file for the installed version is not reinstalled; up to date clears it', () async {
    File('${tmp.path}/jobsummit-8.apk').writeAsBytesSync(apkBytes);
    expect(await AutoUpdater(service(latest: 8)).installIfReady(), AutoUpdateResult.upToDate);
    expect(installer.installed, isEmpty);
    expect(await AutoUpdater(service(latest: 8)).run(), AutoUpdateResult.upToDate);
    expect(files(), isEmpty);
  });

  test('switched off in Settings: nothing happens', () async {
    await AutoUpdater.setEnabled(false);
    expect(await AutoUpdater(service()).run(), AutoUpdateResult.off);
    expect(apkRequests, 0);
  });

  test('"Update now" reports progress, then installs interactively', () async {
    final events = await service().download((await service().checkNow())!.info).toList();
    expect(events.whereType<UpdateDownloading>(), isNotEmpty);
    expect(events.last, isA<UpdateInstalling>());
    expect(installer.installed.single.$2, isTrue);
  });
}
