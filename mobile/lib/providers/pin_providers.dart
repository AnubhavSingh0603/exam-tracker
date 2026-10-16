import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracked_application.dart';
import 'providers.dart';

/// The optional PIN lock for saved IDs and passwords. Off unless set in Settings.
@immutable
class PinState {
  const PinState({this.enabled = false, this.unlockedUntil, this.failures = 0, this.blockedUntil});

  final bool enabled;
  final DateTime? unlockedUntil;
  final int failures;
  final DateTime? blockedUntil;

  /// Nothing to hide: no PIN, or it was entered in the last few minutes.
  bool unlocked(DateTime now) => !enabled || (unlockedUntil?.isAfter(now) ?? false);
}

sealed class PinAttempt {
  const PinAttempt();
}

final class PinOk extends PinAttempt {
  const PinOk();
}

final class PinWrong extends PinAttempt {
  const PinWrong(this.triesLeft);
  final int triesLeft;
}

final class PinWait extends PinAttempt {
  const PinWait(this.until);
  final DateTime until;
}

class PinLockNotifier extends AsyncNotifier<PinState> {
  /// How long one correct PIN keeps IDs visible.
  static const unlockFor = Duration(minutes: 5);
  static const maxTries = 5;
  static const waitAfterTries = Duration(seconds: 30);

  @override
  Future<PinState> build() async => PinState(enabled: await ref.read(secretStoreProvider).hasPin());

  PinState get _now => state.dataOrNull ?? const PinState();

  Future<void> enable(String pin) async {
    await ref.read(secretStoreProvider).setPin(pin);
    state = AsyncData(PinState(enabled: true, unlockedUntil: DateTime.now().add(unlockFor)));
  }

  Future<PinAttempt> unlock(String pin) async {
    final now = DateTime.now();
    final s = _now;
    final blocked = s.blockedUntil;
    if (blocked != null && blocked.isAfter(now)) return PinWait(blocked);
    if (await ref.read(secretStoreProvider).verifyPin(pin)) {
      state = AsyncData(PinState(enabled: s.enabled, unlockedUntil: now.add(unlockFor)));
      return const PinOk();
    }
    final failures = s.failures + 1;
    if (failures >= maxTries) {
      final until = now.add(waitAfterTries);
      state = AsyncData(PinState(enabled: s.enabled, blockedUntil: until));
      return PinWait(until);
    }
    state = AsyncData(PinState(enabled: s.enabled, failures: failures));
    return PinWrong(maxTries - failures);
  }

  void lock() => state = AsyncData(PinState(enabled: _now.enabled));

  /// "Forgot PIN": removes the PIN together with the IDs and passwords saved on
  /// this phone, so the PIN can't be skipped to read them. (With Google backup on,
  /// they come back from Drive at the next sync, behind no PIN.)
  Future<void> forget() async {
    final secrets = ref.read(secretStoreProvider);
    final db = ref.read(databaseProvider);
    for (final app in ref.read(trackedAppsProvider).dataOrNull ?? const <TrackedApplication>[]) {
      await secrets.deletePassword(app.id);
      ref
        ..invalidate(vaultEntryProvider(app.id))
        ..invalidate(hasPasswordProvider(app.id));
    }
    await db.deleteAllVault();
    await secrets.clearPin();
    state = const AsyncData(PinState());
  }
}

final pinLockProvider = AsyncNotifierProvider<PinLockNotifier, PinState>(PinLockNotifier.new);
