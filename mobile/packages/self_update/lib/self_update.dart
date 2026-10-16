import 'package:flutter/services.dart';

/// What the phone allows right now for installing JobSummit's own update.
class SelfUpdateStatus {
  const SelfUpdateStatus({
    this.sdk = 0,
    this.canInstall = false,
    this.selfInstalled = false,
    this.silent = false,
    this.unmetered = false,
    this.appVisible = false,
    this.updatesDir = '',
  });

  factory SelfUpdateStatus.fromMap(Map<String, Object?> m) => SelfUpdateStatus(
        sdk: m['sdk'] as int? ?? 0,
        canInstall: m['canInstall'] == true,
        selfInstalled: m['selfInstalled'] == true,
        silent: m['silent'] == true,
        unmetered: m['unmetered'] == true,
        appVisible: m['appVisible'] == true,
        updatesDir: m['updatesDir'] as String? ?? '',
      );

  final int sdk;

  /// "Install unknown apps" is allowed for JobSummit.
  final bool canInstall;

  /// JobSummit installed the current version itself (after one in-app update).
  final bool selfInstalled;

  /// Android 12+ and both of the above: updates install without asking.
  final bool silent;

  /// Wi-Fi (or another network that isn't metered).
  final bool unmetered;

  /// The app is on screen: installing now would close it under the user.
  final bool appVisible;

  /// Where downloaded updates are kept (the app's cache).
  final String updatesDir;
}

class SelfUpdate {
  const SelfUpdate();

  static const _channel = MethodChannel('jobsummit/self_update');

  Future<SelfUpdateStatus> status() async =>
      SelfUpdateStatus.fromMap(await _channel.invokeMapMethod<String, Object?>('status') ?? const {});

  /// Hands the verified APK to Android. [interactive]: started from the app, so a
  /// confirmation (if Android wants one) opens at once instead of as a notification.
  Future<void> install(String path, {required bool interactive}) =>
      _channel.invokeMethod<void>('install', {'path': path, 'interactive': interactive});
}
