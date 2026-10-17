import 'package:exam_tracker/domain/xp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mon = DateTime(2026, 10, 19, 10);

  test('levels come quickly at first, then spread out', () {
    expect([for (var l = 1; l <= 5; l++) xpForLevel(l)], [0, 100, 250, 450, 700]);
    expect(levelFor(0), 1);
    expect(levelFor(99), 1);
    expect(levelFor(100), 2);
    expect(levelFor(460), 4);
    expect(levelName(1), 'Aspirant');
    expect(levelName(8), 'Summiteer');
    expect(levelName(10), 'Summiteer 3');
  });

  test('useful actions earn XP; a level-up is reported', () {
    var s = const XpState();
    for (var i = 0; i < 4; i++) {
      s = s.award(XpAction.appliedToJob, mon).state;
    }
    final r = s.award(XpAction.appliedToJob, mon);
    expect(r.gained, 20);
    expect(r.state.xp, 100);
    expect(r.levelUp, isTrue);
    expect(r.state.levelProgress, 0);
  });

  test('daily caps stop farming, and reset the next day', () {
    var s = const XpState();
    for (var i = 0; i < 5; i++) {
      s = s.award(XpAction.checkedDashboard, mon).state;
    }
    expect(s.award(XpAction.checkedDashboard, mon).gained, 0);
    expect(s.award(XpAction.checkedDashboard, mon.add(const Duration(days: 1))).gained, 5);
  });

  test('the streak grows day by day and forgives one missed day', () {
    var s = const XpState().award(XpAction.savedIds, mon).state;
    expect(s.streak, 1);
    s = s.award(XpAction.savedIds, mon.add(const Duration(hours: 3))).state;
    expect(s.streak, 1); // same day
    s = s.award(XpAction.savedIds, mon.add(const Duration(days: 1))).state;
    expect(s.streak, 2);
    s = s.award(XpAction.savedIds, mon.add(const Duration(days: 3))).state; // missed Wednesday
    expect(s.streak, 3);
    expect(s.streakOn(mon.add(const Duration(days: 5))), 3); // one more missed day: still alive
    expect(s.streakOn(mon.add(const Duration(days: 6))), 0); // two missed: gone
    s = s.award(XpAction.savedIds, mon.add(const Duration(days: 7))).state;
    expect(s.streak, 1);
  });

  test('the daily ring and saving', () {
    final s = const XpState().award(XpAction.addedExam, mon).state;
    expect(s.doneToday(mon.add(const Duration(hours: 5))), isTrue);
    expect(s.doneToday(mon.add(const Duration(days: 1))), isFalse);
    final back = XpState.fromJson(s.toJson());
    expect((back.xp, back.streak), (15, 1));
    expect(back.today, {'addedExam': 1});
  });
}
