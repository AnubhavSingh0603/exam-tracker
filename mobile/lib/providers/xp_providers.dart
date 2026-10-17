import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/xp.dart';

/// What just happened, for the "+20 XP" pop and the level-up moment.
@immutable
class XpAward {
  const XpAward({
    required this.action,
    required this.gained,
    required this.levelUp,
    required this.level,
    required this.streakUp,
    required this.streak,
    required this.at,
  });

  final XpAction action;
  final int gained;
  final bool levelUp;
  final int level;
  final bool streakUp;
  final int streak;
  final DateTime at;
}

class XpNotifier extends Notifier<XpState> {
  static const _key = 'xp.state';

  @override
  XpState build() {
    _load();
    return const XpState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) state = XpState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable: start from zero rather than break anything.
    }
  }

  /// Gives the points for [action] (nothing past its daily cap) and announces it.
  Future<XpAward?> award(XpAction action) async {
    final now = DateTime.now();
    final r = state.award(action, now);
    if (r.gained == 0) return null;
    state = r.state;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(r.state.toJson()));
    } catch (_) {}
    final award = XpAward(
      action: action,
      gained: r.gained,
      levelUp: r.levelUp,
      level: r.state.level,
      streakUp: r.streakUp,
      streak: r.state.streak,
      at: now,
    );
    ref.read(lastXpAwardProvider.notifier).state = award;
    return award;
  }
}

final xpProvider = NotifierProvider<XpNotifier, XpState>(XpNotifier.new);

/// The latest award: the app shell listens and celebrates it.
final lastXpAwardProvider = StateProvider<XpAward?>((ref) => null);
