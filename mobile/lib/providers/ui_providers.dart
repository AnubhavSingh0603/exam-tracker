import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or follow the phone. Read once in main() so the first frame is
/// already in the right colours.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier([this._initial = ThemeMode.system]);

  final ThemeMode _initial;
  static const _key = 'ui.themeMode';

  @override
  ThemeMode build() => _initial;

  static Future<ThemeMode> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // Kept for this session only.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
