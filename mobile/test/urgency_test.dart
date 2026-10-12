import 'package:exam_tracker/domain/urgency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 11, 12);

  group('urgencyFor', () {
    test('bands match the backend thresholds', () {
      expect(urgencyFor(null, now), Urgency.info);
      expect(urgencyFor(now.add(const Duration(hours: 71)), now), Urgency.urgent);
      expect(urgencyFor(now.add(const Duration(hours: 72)), now), Urgency.warning);
      expect(urgencyFor(now.add(const Duration(days: 14)), now), Urgency.warning);
      expect(urgencyFor(now.add(const Duration(days: 15)), now), Urgency.safe);
    });

    test('wire values map from the API', () {
      expect(urgencyFromWire('critical'), Urgency.urgent);
      expect(urgencyFromWire('approaching'), Urgency.warning);
      expect(urgencyFromWire('safe'), Urgency.safe);
      expect(urgencyFromWire('???'), Urgency.info);
    });
  });

  test('countdownLabel is human and singular-aware', () {
    expect(countdownLabel(now.add(const Duration(minutes: 1)), now), '1 min left');
    expect(countdownLabel(now.add(const Duration(hours: 18)), now), '18 hrs left');
    expect(countdownLabel(now.add(const Duration(days: 9)), now), '9 days left');
    expect(countdownLabel(now.subtract(const Duration(minutes: 1)), now), 'Passed');
  });
}
