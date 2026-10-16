import 'package:exam_tracker/models/tracked_application.dart';
import 'package:exam_tracker/models/vault_entry.dart';
import 'package:exam_tracker/providers/pin_providers.dart';
import 'package:exam_tracker/providers/providers.dart';
import 'package:exam_tracker/services/secret_store.dart';
import 'package:exam_tracker/widgets/dashboard_check_sheet.dart';
import 'package:exam_tracker/widgets/pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the PIN is stored only as a salted hash and checked against it', () async {
    final store = SecretStore();
    expect(await store.hasPin(), isFalse);
    await store.setPin('4821');
    expect(await store.hasPin(), isTrue);
    expect(await store.verifyPin('4821'), isTrue);
    expect(await store.verifyPin('1234'), isFalse);
    final raw = await const FlutterSecureStorage().readAll();
    expect(raw.values.any((v) => v.contains('4821')), isFalse);
    await store.clearPin();
    expect(await store.hasPin(), isFalse);
  });

  test('unlocks for a while; five wrong tries make you wait, even with the right PIN', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final lock = c.read(pinLockProvider.notifier);
    await c.read(pinLockProvider.future);
    await lock.enable('4821');
    expect(c.read(pinLockProvider).requireValue.unlocked(DateTime.now()), isTrue);
    lock.lock();
    expect(c.read(pinLockProvider).requireValue.unlocked(DateTime.now()), isFalse);

    for (var left = 4; left >= 1; left--) {
      expect((await lock.unlock('0000') as PinWrong).triesLeft, left);
    }
    expect(await lock.unlock('0000'), isA<PinWait>());
    expect(await lock.unlock('4821'), isA<PinWait>()); // still waiting
  });

  testWidgets('locked IDs ask for the PIN, then open', (tester) async {
    await SecretStore().setPin('4821');
    bool? result;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async => result = await ensureUnlocked(context, ref),
            child: const Text('Show'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '0000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Wrong PIN. 4 tries left.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '4821');
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Check dashboard: copy and open first, then the password; findings go back to the card', (tester) async {
    final now = DateTime(2026, 10, 17);
    final app = TrackedApplication(
      id: 'cgl',
      examName: 'SSC CGL 2026',
      postName: 'SSC CGL 2026',
      status: ApplicationStatus.applied,
      applyUrl: 'https://ssc.gov.in/login',
      createdAt: now,
      updatedAt: now,
    );
    var examDone = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vaultEntryProvider.overrideWith((ref, id) async => const VaultEntry(appId: 'cgl', registrationId: 'REG123')),
        hasPasswordProvider.overrideWith((ref, id) async => true),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showDashboardCheck(context, ref, app,
                onAdmitCardOut: () {}, onExamDone: () => examDone = true),
            child: const Text('Check'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(find.text('1 · Copy Reg No & open login'), findsOneWidget);
    expect(find.text('2 · Copy password'), findsOneWidget);
    await tester.tap(find.text('Exam is done'));
    await tester.pumpAndSettle();
    expect(examDone, isTrue);
    expect(find.text('Check your dashboard'), findsNothing); // sheet closed
  });
}
