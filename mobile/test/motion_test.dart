import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/app_icons.dart';
import 'package:exam_tracker/widgets/motion.dart';
import 'package:exam_tracker/widgets/pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _theme = AppTheme.of(Brightness.light); // one instance: a new one would animate a theme change

Widget _app(Widget child, {bool animationsOff = false}) => MaterialApp(
      theme: _theme,
      builder: (context, c) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: animationsOff), child: c!),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  final now = DateTime.now();

  testWidgets('only a countdown under 24 hours glows, and never with animations off', (tester) async {
    await tester.pumpWidget(_app(CountdownPill(due: now.add(const Duration(days: 3)), now: now)));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_app(CountdownPill(due: now.add(const Duration(hours: 20)), now: now)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(
        _app(CountdownPill(due: now.add(const Duration(hours: 20)), now: now), animationsOff: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(DuoIcon), findsOneWidget); // the duotone reminder icon
  });

  testWidgets('the applied tick plays and removes itself', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showAppliedCelebration(ctx);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
