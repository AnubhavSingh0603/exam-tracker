import 'package:exam_tracker/domain/xp.dart';
import 'package:exam_tracker/providers/xp_providers.dart';
import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/celebrate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.of(Brightness.light),
        home: const XpCelebrations(
          child: Scaffold(body: Column(children: [XpBadge(), TodayProgress()])),
        ),
      ),
    ));
    await tester.pump();
    return c;
  }

  testWidgets('a useful action pops "+XP" and fills today’s ring', (tester) async {
    final c = await pump(tester);
    expect(find.text('Today’s step: one useful thing'), findsOneWidget);
    await c.read(xpProvider.notifier).award(XpAction.savedIds);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('+10 XP · Saved your IDs'), findsOneWidget);
    expect(find.text('Today’s step: done!'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('+10 XP'), findsNothing); // the pop goes away by itself
  });

  testWidgets('a new level gets its moment', (tester) async {
    final c = await pump(tester);
    for (var i = 0; i < 5; i++) {
      await c.read(xpProvider.notifier).award(XpAction.appliedToJob);
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Level up!'), findsOneWidget);
    expect(find.text('You’re now an Applicant.'), findsOneWidget);
    await tester.tap(find.text('Keep climbing'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
  });
}
