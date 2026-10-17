import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sounds and vibration for the moments that matter. Sounds are short UI sounds
/// (res/raw/fx_*.wav): they play only with the phone on ring and never pause music.
/// Settings › Look switches each off.
abstract final class Fx {
  static const _channel = MethodChannel('jobsummit/fx');
  static const _kSound = 'fx.sound';
  static const _kVibration = 'fx.vibration';

  static bool sound = true;
  static bool vibration = true;

  /// Once at start (before the first frame).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      sound = prefs.getBool(_kSound) ?? true;
      vibration = prefs.getBool(_kVibration) ?? true;
    } catch (_) {}
  }

  static Future<void> setSound(bool on) async {
    sound = on;
    await (await SharedPreferences.getInstance()).setBool(_kSound, on);
    if (on) tap();
  }

  static Future<void> setVibration(bool on) async {
    vibration = on;
    await (await SharedPreferences.getInstance()).setBool(_kVibration, on);
    if (on) unawaited(HapticFeedback.mediumImpact());
  }

  static void _play(String name) {
    if (!sound) return;
    _channel.invokeMethod<bool>('play', {'name': name}).catchError((Object _) => false);
  }

  static void _buzz(Future<void> Function() haptic) {
    if (vibration) unawaited(haptic());
  }

  /// You applied to something: a bright chime.
  static void applied() {
    _play('fx_success');
    _buzz(HapticFeedback.mediumImpact);
  }

  /// XP earned: a soft pop. [quiet]: only the tick (the chime already played).
  static void xp({bool quiet = false}) {
    if (!quiet) _play('fx_pop');
    _buzz(HapticFeedback.selectionClick);
  }

  /// A new level: a short fanfare and a double buzz.
  static void levelUp() {
    _play('fx_levelup');
    _buzz(() async {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await HapticFeedback.heavyImpact();
    });
  }

  /// Not for me, archive: a soft swoosh.
  static void dismiss() {
    _play('fx_swoosh');
    _buzz(HapticFeedback.lightImpact);
  }

  /// Something saved or done (profile, calendar): a click and a firm tap.
  static void done() {
    _play('fx_tap');
    _buzz(HapticFeedback.mediumImpact);
  }

  /// A stage moved, a switch flipped: a tiny click.
  static void tap() {
    _play('fx_tap');
    _buzz(HapticFeedback.selectionClick);
  }

  /// Copied to the clipboard.
  static void copy() {
    _play('fx_tap');
    _buzz(HapticFeedback.lightImpact);
  }

  /// Something didn't work: a gentle falling two-tone, no buzz.
  static void error() => _play('fx_soft_error');
}
