import 'package:exam_tracker/models/exam_timeline.dart';
import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/progress_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackedApplication app(String name, {TrackerStatus? w, Map<String, dynamic> t = const {}}) => TrackedApplication(
      id: name,
      examName: name,
      postName: name,
      status: ApplicationStatus.applied,
      createdAt: DateTime(2026, 9),
      updatedAt: DateTime(2026, 9),
      watcherStatus: w,
      timeline: ExamTimeline.fromJson({'job_post_id': name, ...t}),
    );

void main() {
  final now = DateTime(2026, 10, 25);

  test('each exam stands at its stage; finished ones at the summit', () {
    expect(ProgressMap.stopOf(app('IBPS PO XV', w: TrackerStatus.admitCardLive), now), 1);
    expect(ProgressMap.stopOf(app('SSC CGL 2026', t: {'exam_start': '2026-09-30', 'exam_end': '2026-10-19'}), now), 3);
    expect(ProgressMap.stopOf(app('SBI Clerk 2026', w: TrackerStatus.resultDeclared), now), 4);
  });

  test('short badge names keep the board where it fits', () {
    expect(ProgressMap.shortName(app('SSC CGL 2026')), 'SSC CGL');
    expect(ProgressMap.shortName(app('IBPS PO XV')), 'IBPS PO');
    expect(ProgressMap.shortName(app('RRB NTPC (Graduate) 2026')), 'RRB NTPC');
    expect(ProgressMap.shortName(app('My custom exam')), 'MY');
  });

  testWidgets('climbers are drawn and still with animations off', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(Brightness.light),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: c!),
      home: Scaffold(body: ProgressMap(now: now, apps: [app('SSC CGL 2026'), app('IBPS PO XV')])),
    ));
    await tester.pump();
    expect(find.text('SSC CGL'), findsOneWidget);
    expect(find.text('IBPS PO'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
