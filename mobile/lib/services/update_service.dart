import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:self_update/self_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// The release number (pubspec build number) inside an installed version code.
/// Universal APKs get release × 10; Flutter's split APKs add ABI × 1000 on top
/// (arm64 0.9.2 = 2121), so the thousands are dropped first. Good up to release 99.
int releaseNumberOf(int androidVersionCode) => (androidVersionCode % 1000) ~/ 10;

final _sha256 = RegExp(r'^[0-9a-f]{64}$');

@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.minSupportedVersionCode,
    required this.releaseNotes,
    required this.apkUrl,
    required this.sha256,
    this.sizeBytes,
  });

  final int versionCode; // release number, not the Android versionCode
  final String versionName;
  final int minSupportedVersionCode;
  final String releaseNotes;
  final String apkUrl;
  final String sha256;
  final int? sizeBytes;

  /// Rejects anything we wouldn't want to hand to the installer.
  bool get isTrustworthy => Uri.tryParse(apkUrl)?.scheme == 'https' && _sha256.hasMatch(sha256);

  String? get sizeLabel => sizeBytes == null ? null : '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// `GET /api/v1/app/version` response.
  factory UpdateInfo.fromServer(Map<String, dynamic> j) => UpdateInfo(
        versionCode: (j['latest_version_code'] as num).toInt(),
        versionName: j['version_name'] as String,
        minSupportedVersionCode: (j['min_supported_version_code'] as num?)?.toInt() ?? 1,
        releaseNotes: j['release_notes'] as String? ?? '',
        apkUrl: j['apk_url'] as String,
        sha256: (j['sha256'] as String).toLowerCase(),
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
      );

  /// `latest.json` attached to the GitHub Release (same file the server serves from).
  static UpdateInfo? fromManifest(Map<String, dynamic> j, String? abi) {
    final apks = j['apks'] as Map<String, dynamic>? ?? const {};
    final asset = (apks[abi] ?? apks['universal']) as Map<String, dynamic>?;
    if (asset == null) return null;
    return UpdateInfo(
      // `release` is the real number; `version_code` is inflated for apps up to
      // 0.10.0, whose own arithmetic over-counted (see the release workflow).
      versionCode: ((j['release'] ?? j['version_code']) as num).toInt(),
      versionName: j['version_name'] as String,
      minSupportedVersionCode: (j['min_supported_version_code'] as num?)?.toInt() ?? 1,
      releaseNotes: j['release_notes'] as String? ?? '',
      apkUrl: asset['url'] as String,
      sha256: (asset['sha256'] as String).toLowerCase(),
      sizeBytes: (asset['size_bytes'] as num?)?.toInt(),
    );
  }
}

@immutable
class UpdateCheck {
  const UpdateCheck({required this.info, required this.installedVersionName, required this.mandatory});

  final UpdateInfo info;
  final String installedVersionName;

  /// Installed release is below `min_supported_version_code`: no "Later" button.
  final bool mandatory;
}

sealed class UpdateProgress {
  const UpdateProgress();
}

final class UpdateDownloading extends UpdateProgress {
  const UpdateDownloading(this.fraction);
  final double? fraction; // null = indeterminate
}

final class UpdateInstalling extends UpdateProgress {
  const UpdateInstalling();
}

final class UpdateFailed extends UpdateProgress {
  const UpdateFailed(this.message, {this.suggestSettings = false});
  final String message;

  /// Install permission / Samsung Auto Blocker: the fix is in system settings.
  final bool suggestSettings;
}

/// Checks for and installs new APKs for the `direct` build. All network work
/// is best-effort: any failure simply means "no update offered right now".
class UpdateCheckFailed implements Exception {
  const UpdateCheckFailed();
}

/// The downloaded APK's checksum didn't match latest.json.
class UpdateDamaged implements Exception {
  const UpdateDamaged();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class UpdateService {
  UpdateService({http.Client? client, String? manifestUrl, bool? enabled, SelfUpdate? installer})
      : _client = client ?? http.Client(),
        _manifestUrl = manifestUrl ?? Env.releaseManifestUrl,
        _enabled = enabled ?? Env.updatesEnabled,
        _installer = installer ?? const SelfUpdate();

  final http.Client _client;
  final String _manifestUrl;
  final bool _enabled;
  final SelfUpdate _installer;

  /// Updates are possible in this build (the `direct` flavour).
  bool get enabled => _enabled;

  SelfUpdate get installer => _installer;

  static const checkInterval = Duration(hours: 12);
  static const _timeout = Duration(seconds: 8);
  static const _kLastCheck = 'update.lastCheckMs';
  static const _kSkipped = 'update.skippedVersion';

  /// The automatic check (app start): at most every [checkInterval] unless
  /// [force]d, quiet on failure, and a version the user put off with "Later"
  /// is not offered again.
  Future<UpdateCheck?> check({bool force = false}) async {
    if (!_enabled) return null;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_kLastCheck) ?? 0;
    if (!force && now - last < checkInterval.inMilliseconds) return null;
    try {
      final found = await checkNow();
      if (found == null || found.mandatory) return found;
      return prefs.getInt(_kSkipped) == found.info.versionCode ? null : found;
    } on UpdateCheckFailed {
      return null;
    }
  }

  /// "Check for updates" in Settings: the user asked, so an update put off
  /// with "Later" still shows. null = up to date. Throws [UpdateCheckFailed]
  /// when GitHub can't be reached, so that is not mistaken for "up to date".
  /// The installed release number (see [releaseNumberOf]).
  Future<int> installedRelease() async =>
      releaseNumberOf(int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0);

  Future<UpdateCheck?> checkNow() async {
    final package = await PackageInfo.fromPlatform();
    final installed = releaseNumberOf(int.tryParse(package.buildNumber) ?? 0);
    final remote = await _fromManifest(await _primaryAbi());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);
    if (remote == null || !remote.isTrustworthy) throw const UpdateCheckFailed();
    if (remote.versionCode <= installed) return null;
    return UpdateCheck(
      info: remote,
      installedVersionName: package.version,
      mandatory: installed < remote.minSupportedVersionCode,
    );
  }

  /// "Later": don't offer this exact version again (a newer one will still show).
  Future<void> skip(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSkipped, versionCode);
  }

  static String _apkName(UpdateInfo info) => 'jobsummit-${info.versionCode}.apk';

  String _apkPath(UpdateInfo info, String dir) => '$dir/${_apkName(info)}';

  /// The APK for [info] if it was downloaded (and verified) before, else null.
  Future<File?> downloaded(UpdateInfo info, String dir) async {
    final file = File(_apkPath(info, dir));
    if (!await file.exists()) return null;
    if ((await sha256.bind(file.openRead()).first).toString() == info.sha256) return file;
    await file.delete(); // damaged or replaced: fetch again
    return null;
  }

  /// Downloads the APK into [dir], checking its SHA-256 as it arrives. Progress
  /// 0..1, or null when the size is unknown. Throws [UpdateDamaged] on a bad
  /// checksum; Android also refuses any APK not signed with our key.
  Future<File> fetch(UpdateInfo info, String dir, {void Function(double? fraction)? onProgress}) async {
    await Directory(dir).create(recursive: true);
    final part = File('${_apkPath(info, dir)}.part');
    final res = await _client.send(http.Request('GET', Uri.parse(info.apkUrl))).timeout(_timeout);
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}');
    final total = res.contentLength ?? info.sizeBytes;
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final out = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null || total == 0 ? null : (received / total).clamp(0.0, 1.0));
      }
    } finally {
      await out.close();
    }
    hasher.close();
    if (digest.value.toString() != info.sha256) {
      await part.delete();
      throw const UpdateDamaged();
    }
    return part.rename(_apkPath(info, dir));
  }

  /// Removes downloads other than [keep] (installed or outdated versions).
  Future<void> clearDownloads(String dir, {UpdateInfo? keep}) async {
    final folder = Directory(dir);
    if (!await folder.exists()) return;
    final keepName = keep == null ? null : _apkName(keep);
    await for (final f in folder.list()) {
      if (f is File && f.uri.pathSegments.last != keepName) await f.delete();
    }
  }

  /// "Update now": download (unless already done), verify, install. Android
  /// restarts the app on the new version; if it wants a tap, its prompt opens.
  Stream<UpdateProgress> download(UpdateInfo info) {
    final events = StreamController<UpdateProgress>();
    () async {
      try {
        final status = await _installer.status();
        final apk = await downloaded(info, status.updatesDir) ??
            await fetch(info, status.updatesDir, onProgress: (f) => events.add(UpdateDownloading(f)));
        events.add(const UpdateInstalling());
        await _installer.install(apk.path, interactive: true);
      } on UpdateDamaged {
        events.add(const UpdateFailed('The download was damaged, so it was not installed. Please try again.'));
      } on PlatformException {
        events.add(const UpdateFailed('The update could not be installed.', suggestSettings: true));
      } catch (_) {
        events.add(const UpdateFailed('Download failed. Check your connection and try again.'));
      }
      await events.close();
    }();
    return events.stream;
  }

  Future<UpdateInfo?> _fromManifest(String? abi) async {
    if (_manifestUrl.isEmpty) return null;
    try {
      // GitHub's /releases/latest/download/<asset> redirects to the newest release's file.
      final res = await _client.get(Uri.parse(_manifestUrl)).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return UpdateInfo.fromManifest(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>, abi);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _primaryAbi() async {
    try {
      final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      return abis.isEmpty ? null : abis.first;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
