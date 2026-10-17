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

  test('apply, undo, apply: one job earns once; undo takes the XP and the streak day back', () {
    final key = xpExamKey(jobPostId: '123', examName: 'SSC CGL 2026');
    var s = XpState(streak: 4, lastActiveDay: mon.subtract(const Duration(days: 1)));
    var r = s.award(XpAction.appliedToJob, mon, key: key);
    expect((r.gained, r.state.xp, r.state.streak), (20, 20, 5));
    s = r.state;

    final u = s.revoke(key, mon);
    expect((u.lost, u.state.xp), (20, 0));
    expect(u.state.streak, 4, reason: 'the only thing today was undone');
    expect(u.state.doneToday(mon), isFalse);
    s = u.state;

    for (var i = 0; i < 3; i++) {
      r = s.award(XpAction.appliedToJob, mon, key: key);
      s = r.state;
    }
    expect(s.xp, 20, reason: 'applying again earns it again, once');
    expect(s.streak, 5);
    expect(s.revoke('job:never-earned', mon).lost, 0);
  });

  test('repeating the same thing earns nothing: re-added exams, stages moved back and forth', () {
    var s = const XpState();
    final exam = xpExamKey(examName: ' SSC CHSL 2026 ');
    expect(exam, xpExamKey(examName: 'ssc chsl 2026'));
    s = s.award(XpAction.addedExam, mon, key: exam).state;
    expect(s.award(XpAction.addedExam, mon, key: exam).gained, 0, reason: 'deleted and added again');
    s = s.award(XpAction.privateProgress, mon, key: 'stage:papp:1:interview').state;
    expect(s.award(XpAction.privateProgress, mon, key: 'stage:papp:1:interview').gained, 0);
    expect(s.award(XpAction.setExamDate, mon, key: 'date:$exam').gained, 10);
    expect(s.xp, 25);
  });

  test('a dashboard check earns once per exam per day', () {
    final key = 'dash:job:1:${xpDayStamp(mon)}';
    final s = const XpState().award(XpAction.checkedDashboard, mon, key: key).state;
    expect(s.award(XpAction.checkedDashboard, mon, key: key).gained, 0);
    final tue = mon.add(const Duration(days: 1));
    final r = s.award(XpAction.checkedDashboard, tue, key: 'dash:job:1:${xpDayStamp(tue)}');
    expect(r.gained, 5);
    expect(r.state.earned.containsKey(key), isFalse, reason: 'yesterday’s daily key is dropped');
  });

  test('recount: XP is what the things add up to; the streak stays; keys survive saving', () {
    final s = XpState(xp: 160, streak: 3, lastActiveDay: mon).recount({
      'job:1': XpEarned(XpAction.appliedToJob, 20, mon),
      'exam:ssc chsl 2026': XpEarned(XpAction.addedExam, 15, mon),
      'ids:job:1': XpEarned(XpAction.savedIds, 10, mon),
    });
    expect((s.xp, s.streak), (45, 3));
    final back = XpState.fromJson(s.toJson());
    expect(back.xp, 45);
    expect(back.earned.keys, unorderedEquals(['job:1', 'exam:ssc chsl 2026', 'ids:job:1']));
    expect(back.award(XpAction.appliedToJob, mon, key: 'job:1').gained, 0);
  });
}
