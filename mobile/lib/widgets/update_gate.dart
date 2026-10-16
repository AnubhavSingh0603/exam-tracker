import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import '../services/auto_update.dart';
import '../utils/system_actions.dart';
import 'update_dialog.dart';

/// Checks for updates after the first frame and whenever the app returns to the
/// foreground (the service itself throttles to once per 12 h). Never blocks startup.
///
/// With automatic updates on and Android allowing it, there is no prompt: the new
/// version downloads (on Wi-Fi) and installs when the app leaves the screen.
/// Otherwise the usual prompt asks. After an update: "Updated to v…".
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> with WidgetsBindingObserver {
  static const _kLastVersion = 'update.lastVersion';
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announceUpdate();
      _check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _check();
      case AppLifecycleState.paused:
        // Left the app: a waiting update can install now without interrupting.
        unawaited(AutoUpdater(ref.read(updateServiceProvider)).installIfReady().catchError((_) => AutoUpdateResult.ready));
      default:
        break;
    }
  }

  Future<void> _check() async {
    if (_showing) return;
    final service = ref.read(updateServiceProvider);
    final update = await service.check();
    if (update == null || !mounted) return;
    if (!update.mandatory && await AutoUpdater.isEnabled()) {
      final auto = AutoUpdater(service);
      try {
        if ((await auto.status()).silent) {
          unawaited(auto.run(appInUse: true).catchError((_) => AutoUpdateResult.offline));
          return;
        }
      } catch (_) {
        // No installer on this build: fall back to the prompt.
      }
    }
    if (!mounted) return;
    _showing = true;
    await showUpdateDialog(context, service, update);
    _showing = false;
  }

  Future<void> _announceUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final version = (await PackageInfo.fromPlatform()).version;
    final before = prefs.getString(_kLastVersion);
    await prefs.setString(_kLastVersion, version);
    if (before != null && before != version && mounted) showCalmSnack(context, 'Updated to JobSummit $version.');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
