import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// Android versionCode = release number × 10 + ABI digit (set in build.gradle.kts),
/// so every newer release outranks every older one, split or universal.
int releaseNumberOf(int androidVersionCode) => androidVersionCode ~/ 10;

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
      versionCode: (j['version_code'] as num).toInt(),
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
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const checkInterval = Duration(hours: 12);
  static const _timeout = Duration(seconds: 8);
  static const _kLastCheck = 'update.lastCheckMs';
  static const _kSkipped = 'update.skippedVersion';

  Future<UpdateCheck?> check({bool force = false}) async {
    if (!Env.updatesEnabled) return null;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_kLastCheck) ?? 0;
    if (!force && now - last < checkInterval.inMilliseconds) return null;

    final package = await PackageInfo.fromPlatform();
    final installed = releaseNumberOf(int.tryParse(package.buildNumber) ?? 0);
    final abi = await _primaryAbi();

    final remote = await _fromManifest(abi);
    await prefs.setInt(_kLastCheck, now);
    if (remote == null || !remote.isTrustworthy || remote.versionCode <= installed) return null;

    final mandatory = installed < remote.minSupportedVersionCode;
    if (!mandatory && prefs.getInt(_kSkipped) == remote.versionCode) return null;
    return UpdateCheck(info: remote, installedVersionName: package.version, mandatory: mandatory);
  }

  /// "Later": don't offer this exact version again (a newer one will still show).
  Future<void> skip(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSkipped, versionCode);
  }

  /// Downloads, verifies the SHA-256, then opens the system installer.
  /// Android additionally refuses the install unless it's signed with our key.
  Stream<UpdateProgress> download(UpdateInfo info) async* {
    try {
      final events = OtaUpdate().execute(
        info.apkUrl,
        destinationFilename: 'exam-tracker-${info.versionName}.apk',
        sha256checksum: info.sha256,
      );
      await for (final event in events) {
        yield _mapEvent(event);
      }
    } catch (_) {
      yield const UpdateFailed('Download failed. Check your connection and try again.');
    }
  }

  UpdateProgress _mapEvent(OtaEvent event) {
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final pct = double.tryParse(event.value ?? '');
        return UpdateDownloading(pct == null ? null : (pct / 100).clamp(0.0, 1.0));
      case OtaStatus.INSTALLING:
        return const UpdateInstalling();
      case OtaStatus.CHECKSUM_ERROR:
        return const UpdateFailed('The download was damaged, so it was not installed. Please try again.');
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        return const UpdateFailed(
          'Android needs permission to install updates from this app.',
          suggestSettings: true,
        );
      case OtaStatus.ALREADY_RUNNING_ERROR:
        return const UpdateDownloading(null);
      default:
        return const UpdateFailed('The update could not be installed.', suggestSettings: true);
    }
  }

  Future<UpdateInfo?> _fromManifest(String? abi) async {
    if (Env.releaseManifestUrl.isEmpty) return null;
    try {
      // GitHub's /releases/latest/download/<asset> redirects to the newest release's file.
      final res = await _client.get(Uri.parse(Env.releaseManifestUrl)).timeout(_timeout);
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
