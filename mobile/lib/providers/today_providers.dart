import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/next_step.dart';
import '../domain/xp.dart';
import 'jobs_providers.dart';
import 'providers.dart';

/// Today shows tiles (Overview) or one big next step (Focus); it remembers which.
enum TodayView { overview, focus }

class TodayViewNotifier extends Notifier<TodayView> {
  static const _key = 'today.view';

  @override
  TodayView build() {
    _load();
    return TodayView.overview;
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      if (v == TodayView.focus.name) state = TodayView.focus;
    } catch (_) {}
  }

  Future<void> show(TodayView view) async {
    state = view;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, view.name);
    } catch (_) {}
  }
}

final todayViewProvider = NotifierProvider<TodayViewNotifier, TodayView>(TodayViewNotifier.new);

/// Steps put off with "Not now": step id → the day it was put off. They come back
/// tomorrow.
class FocusSnoozeNotifier extends Notifier<Map<String, String>> {
  static const _key = 'focus.snoozed';

  @override
  Map<String, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) state = (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
  }

  Future<void> snooze(String stepId, DateTime now) async {
    final today = xpDayStamp(now);
    state = {
      for (final e in state.entries)
        if (e.value == today) e.key: e.value, // yesterday's are forgotten
      stepId: today,
    };
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(state));
    } catch (_) {}
  }
}

final focusSnoozeProvider = NotifierProvider<FocusSnoozeNotifier, Map<String, String>>(FocusSnoozeNotifier.new);

/// Today's Focus queue: what's pending, most urgent first, minus what was put off
/// today.
final focusStepsProvider = Provider<List<NextStep>>((ref) {
  final now = ref.watch(nowProvider);
  final today = xpDayStamp(now);
  final snoozed = ref.watch(focusSnoozeProvider);
  return [
    for (final s in computeNextSteps(
      tracked: ref.watch(activeAppsProvider),
      feed: [for (final r in ref.watch(rankedJobsProvider).take(8)) r.item],
      now: now,
    ))
      if (snoozed[s.id] != today) s,
  ];
});
