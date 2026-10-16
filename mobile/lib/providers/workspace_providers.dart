import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// Govt exams, or private (corporate) jobs: two workspaces under one account.
enum Workspace { govt, private }

@immutable
class WorkspaceState {
  const WorkspaceState({this.privateEnabled = false, this.current = Workspace.govt});

  /// Settings › Jobs › "Private jobs (beta)". Off by default.
  final bool privateEnabled;
  final Workspace current;

  /// The workspace actually shown: always Govt when Private is off (or not built).
  Workspace get shown => Env.privateJobsAvailable && privateEnabled ? current : Workspace.govt;
}

class WorkspaceNotifier extends Notifier<WorkspaceState> {
  static const _kEnabled = 'workspace.privateEnabled';
  static const _kCurrent = 'workspace.current';

  @override
  WorkspaceState build() {
    _load();
    return const WorkspaceState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = WorkspaceState(
      privateEnabled: prefs.getBool(_kEnabled) ?? false,
      current: prefs.getString(_kCurrent) == Workspace.private.name ? Workspace.private : Workspace.govt,
    );
  }

  Future<void> setPrivateEnabled(bool on) async {
    state = WorkspaceState(privateEnabled: on, current: on ? state.current : Workspace.govt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, on);
    if (!on) await prefs.setString(_kCurrent, Workspace.govt.name);
  }

  Future<void> switchTo(Workspace w) async {
    state = WorkspaceState(privateEnabled: state.privateEnabled, current: w);
    await (await SharedPreferences.getInstance()).setString(_kCurrent, w.name);
  }
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(WorkspaceNotifier.new);
