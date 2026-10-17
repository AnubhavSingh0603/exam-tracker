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

  test('every stop and the whole trail sit on the mountain, at any phone width', () {
    for (final width in [320.0, 380.0, 600.0]) {
      final size = Size(width, 210);
      final mountain = ProgressMap.mountainPath(size);
      for (final f in ProgressMap.stops.take(4)) {
        expect(mountain.contains(Offset(f.dx * width, f.dy * 210)), isTrue, reason: 'stop $f at $width');
      }
      for (final metric in ProgressMap.trailPath(size).computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 2) {
          final pos = metric.getTangentForOffset(d)!.position;
          // The last few px meet the summit at the peak itself.
          if (pos.dy < ProgressMap.stops[4].dy * 210 + 8) continue;
          expect(mountain.contains(pos), isTrue, reason: 'trail at $pos, width $width');
        }
      }
    }
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
