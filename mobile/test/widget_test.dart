import 'package:exam_tracker/domain/next_step.dart';
import 'package:exam_tracker/domain/urgency.dart';
import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/hero_card.dart';
import 'package:exam_tracker/widgets/pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.darkPastel(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  final now = DateTime.now();

  testWidgets('urgent hero renders in terracotta with its action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(HeroCard(
      step: NextStep(
        kind: NextStepKind.downloadAdmitCard,
        title: 'Download admit card for SSC CGL',
        due: now.add(const Duration(hours: 18, minutes: 5)),
        urgency: Urgency.urgent,
      ),
      now: now,
      onPrimary: () => tapped = true,
    )));

    expect(find.text('Download admit card for SSC CGL'), findsOneWidget);
    expect(find.textContaining('18 hrs left'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));
    expect(button.style?.backgroundColor?.resolve({}), AppPalette.terracotta);

    await tester.tap(find.text('Download admit card'));
    expect(tapped, isTrue);
  });

  testWidgets('seat pill uses the spec format', (tester) async {
    await tester.pumpWidget(_wrap(const SeatPill(total: 26, ur: 20, quota: 6, category: 'SC')));
    expect(find.text('🎯 26 Seats (20 UR + 6 SC)'), findsOneWidget);
  });
}
