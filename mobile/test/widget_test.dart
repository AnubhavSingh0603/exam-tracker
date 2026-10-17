import 'package:exam_tracker/theme/app_theme.dart';
import 'package:exam_tracker/widgets/pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.darkPastel(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  testWidgets('seat pill uses the spec format', (tester) async {
    await tester.pumpWidget(_wrap(const SeatPill(total: 26, ur: 20, quota: 6, category: 'SC')));
    expect(find.text('🎯 26 Seats (20 UR + 6 SC)'), findsOneWidget);
  });
}
