import 'dart:io';

import 'package:self_update/self_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';

/// What one automatic pass did.
enum AutoUpdateResult {
  /// Switched off in Settings, or not the GitHub build.
  off,
  upToDate,

  /// GitHub couldn't be reached; the next pass tries again.
  offline,

  /// A new version is out but this is mobile data: it waits for Wi-Fi.
  waitingForWifi,

  /// Downloaded and verified; installs when the app is not in use (or, where
  /// Android still asks once, through the update prompt).
  ready,

  /// Handed to Android, which installs it and restarts the app.
  installing,
}

/// Automatic updates: new versions download on Wi-Fi and, on Android 12+, install
/// without asking while you're not using the app. Android allows that silent step
/// only once JobSummit installed the current version itself, so the very first
/// update after this feature still goes through the normal prompt.
class AutoUpdater {
  AutoUpdater(this._service, {SelfUpdate? platform}) : _platform = platform ?? _service.installer;

  final UpdateService _service;
  final SelfUpdate _platform;

  static const _kEnabled = 'update.auto';

  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? true;

  static Future<void> setEnabled(bool on) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, on);

  Future<SelfUpdateStatus> status() => _platform.status();

  /// One pass: check, download on Wi-Fi, install silently if allowed and the app
  /// isn't on screen. [appInUse] overrides the phone's own answer (the app knows
  /// it is in the foreground; the background task asks the phone).
  Future<AutoUpdateResult> run({bool? appInUse}) async {
    if (!_service.enabled || !await isEnabled()) return AutoUpdateResult.off;
    final UpdateCheck? check;
    try {
      check = await _service.checkNow();
    } on UpdateCheckFailed {
      return AutoUpdateResult.offline;
    }
    final status = await _platform.status();
    if (check == null) {
      await _service.clearDownloads(status.updatesDir);
      return AutoUpdateResult.upToDate;
    }
    await _service.clearDownloads(status.updatesDir, keep: check.info);
    var apk = await _service.downloaded(check.info, status.updatesDir);
    if (apk == null) {
      if (!status.unmetered) return AutoUpdateResult.waitingForWifi;
      try {
        apk = await _service.fetch(check.info, status.updatesDir);
      } catch (_) {
        return AutoUpdateResult.offline;
      }
    }
    if (!status.silent || (appInUse ?? status.appVisible)) return AutoUpdateResult.ready;
    return _install(apk);
  }

  /// When the app leaves the screen: install a download that is waiting, if
  /// Android lets us do it without asking.
  Future<AutoUpdateResult> installIfReady() async {
    if (!_service.enabled || !await isEnabled()) return AutoUpdateResult.off;
    final status = await _platform.status();
    if (!status.silent) return AutoUpdateResult.ready;
    final dir = Directory(status.updatesDir);
    if (!await dir.exists()) return AutoUpdateResult.upToDate;
    // Files are named jobsummit-<release>.apk and only after their checksum passed.
    final installed = await _service.installedRelease();
    File? newest;
    var newestRelease = installed;
    await for (final f in dir.list()) {
      final release = int.tryParse(RegExp(r'jobsummit-(\d+)\.apk$').firstMatch(f.path)?.group(1) ?? '');
      if (f is File && release != null && release > newestRelease) {
        newest = f;
        newestRelease = release;
      }
    }
    return newest == null ? AutoUpdateResult.upToDate : _install(newest);
  }

  Future<AutoUpdateResult> _install(File apk) async {
    try {
      await _platform.install(apk.path, interactive: false);
      return AutoUpdateResult.installing;
    } catch (_) {
      return AutoUpdateResult.ready; // the prompt offers it next time
    }
  }
}
