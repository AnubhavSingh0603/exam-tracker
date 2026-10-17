import 'package:flutter/foundation.dart';

/// Useful things you did, and what each is worth. Only actions that move your job
/// search forward earn XP; opening the app never does.
enum XpAction {
  appliedToJob(20, 'Applied to a job', perDay: 10),
  addedExam(15, 'Added an exam', perDay: 5),
  savedIds(10, 'Saved your IDs', perDay: 5),
  setExamDate(10, 'Updated an exam date', perDay: 5),
  checkedDashboard(5, 'Checked a dashboard', perDay: 5),
  completedProfile(25, 'Finished your profile', perDay: 1),
  privateApplied(15, 'Applied to a company', perDay: 10),
  privateProgress(10, 'Moved an application forward', perDay: 10),
  privateOffer(50, 'Got an offer!', perDay: 3);

  const XpAction(this.points, this.label, {required this.perDay});
  final int points;
  final String label;

  /// More than this in one day earns nothing (no farming by tapping).
  final int perDay;
}

/// Level names, one per level; past the list, "Summiteer N".
const _levelNames = [
  'Aspirant', 'Applicant', 'Candidate', 'Contender', 'Achiever', 'Trailblazer', 'Topper', 'Summiteer', //
];

/// XP needed to *reach* [level] (level 1 = 0). Each step asks 50 more than the
/// last: 0, 100, 250, 450, 700… so early levels come fast.
int xpForLevel(int level) => level <= 1 ? 0 : 25 * (level - 1) * (level + 2);

int levelFor(int xp) {
  var level = 1;
  while (xpForLevel(level + 1) <= xp) {
    level++;
  }
  return level;
}

String levelName(int level) =>
    level <= _levelNames.length ? _levelNames[level - 1] : 'Summiteer ${level - _levelNames.length + 1}';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Your XP, level and streak. Pure: [award] returns the new state and what happened.
@immutable
class XpState {
  const XpState({this.xp = 0, this.streak = 0, this.lastActiveDay, this.today = const {}, this.todayDay});

  final int xp;

  /// Days in a row with something useful done. One missed day is forgiven.
  final int streak;
  final DateTime? lastActiveDay;

  /// Times each action earned XP on [todayDay] (for the daily caps).
  final Map<String, int> today;
  final DateTime? todayDay;

  int get level => levelFor(xp);
  String get levelTitle => levelName(level);
  int get levelStart => xpForLevel(level);
  int get nextLevelAt => xpForLevel(level + 1);

  /// 0..1 through the current level.
  double get levelProgress => (xp - levelStart) / (nextLevelAt - levelStart);

  /// Something useful done today (the daily ring is full).
  bool doneToday(DateTime now) => lastActiveDay != null && _day(lastActiveDay!) == _day(now);

  /// The streak as it stands [now]: still alive after one missed day, gone after two.
  int streakOn(DateTime now) {
    final last = lastActiveDay;
    if (last == null) return 0;
    return _day(now).difference(_day(last)).inDays <= 2 ? streak : 0;
  }

  ({XpState state, int gained, bool levelUp, bool streakUp}) award(XpAction action, DateTime now) {
    final day = _day(now);
    final counts = todayDay == day ? today : const <String, int>{};
    final used = counts[action.name] ?? 0;
    if (used >= action.perDay) return (state: this, gained: 0, levelUp: false, streakUp: false);

    final last = lastActiveDay == null ? null : _day(lastActiveDay!);
    final gap = last == null ? null : day.difference(last).inDays;
    final newStreak = switch (gap) {
      null => 1,
      0 => streak, // already counted today
      1 || 2 => streak + 1, // next day, or one day missed (forgiven)
      _ => 1, // two or more missed days: start again
    };
    final next = XpState(
      xp: xp + action.points,
      streak: newStreak,
      lastActiveDay: day,
      today: {...counts, action.name: used + 1},
      todayDay: day,
    );
    return (state: next, gained: action.points, levelUp: next.level > level, streakUp: newStreak > streak);
  }

  Map<String, Object?> toJson() => {
        'xp': xp,
        'streak': streak,
        'last_active_day': lastActiveDay?.toIso8601String(),
        'today': today,
        'today_day': todayDay?.toIso8601String(),
      };

  factory XpState.fromJson(Map<String, dynamic> j) => XpState(
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        lastActiveDay: DateTime.tryParse(j['last_active_day'] as String? ?? ''),
        today: {for (final e in (j['today'] as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as num).toInt()},
        todayDay: DateTime.tryParse(j['today_day'] as String? ?? ''),
      );
}
