

import '../config/env.dart';
import '../domain/xp.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_store.dart';
import 'backup_providers.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'xp_providers.dart';

// -----------------------------------------------------------------------------
// Google account (only used for the Drive backup)
// -----------------------------------------------------------------------------

final googleAccountServiceProvider = Provider<GoogleAccountService>((ref) => GoogleAccountService());

/// The signed-in Google account, or null. Signing in is a one-time step per
/// phone; every start restores it silently.
class GoogleAccountNotifier extends AsyncNotifier<GoogleUser?> {
  GoogleAccountService get _service => ref.read(googleAccountServiceProvider);

  @override
  Future<GoogleUser?> build() async {
    if (!Env.canSignIn) return null;
    // Offline at start: still show who is signed in; backups retry the silent sign-in.
    return await _service.restore() ?? await GoogleAccountService.remembered();
  }

  /// Throws [AuthException]; `cancelled` is true when the user backed out.
  Future<GoogleUser> signIn() async {
    final user = await _service.signIn();
    state = AsyncData(user);
    return user;
  }

  /// Signs out of Google in this app. The phone's data stays.
  Future<void> signOut() async {
    await _service.signOut();
    state = const AsyncData(null);
  }
}

final googleAccountProvider =
    AsyncNotifierProvider<GoogleAccountNotifier, GoogleUser?>(GoogleAccountNotifier.new);

// -----------------------------------------------------------------------------
// Eligibility profile
// -----------------------------------------------------------------------------

/// The eligibility profile lives on this phone (matching runs here too) and is
/// part of the Drive backup.
class ProfileNotifier extends AsyncNotifier<UserProfileData?> {
  @override
  Future<UserProfileData?> build() => ProfileStore.read();

  /// Saves on the phone; the feed recomputes from it and a backup follows.
  Future<bool> save(UserProfileData data) async {
    final firstTime = state.valueOrNull?.isComplete != true && data.isComplete;
    await ProfileStore.write(data);
    if (firstTime) unawaited(ref.read(xpProvider.notifier).award(XpAction.completedProfile, key: 'profile'));
    state = AsyncData(data);
    ref.invalidate(feedProvider);
    ref.read(backupControllerProvider.notifier).markDirty();
    return true;
  }

  /// "Reset profile": back to a blank profile (the setup sheet asks again). Tracked
  /// exams, IDs and settings stay. The backup carries the reset to other phones.
  Future<void> reset() async {
    await ProfileStore.reset();
    state = const AsyncData(null);
    ref.invalidate(feedProvider);
    ref.read(backupControllerProvider.notifier).markDirty();
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfileData?>(ProfileNotifier.new);

enum AccountStatus { loading, needsProfile, ready }

final accountStatusProvider = Provider<AccountStatus>((ref) {
  // No account needed for jobs: they come from the public data feed and matching
  // runs on the phone. Google is only for the backup.
  final profile = ref.watch(profileProvider);
  if (profile.isLoading && !profile.hasValue) return AccountStatus.loading;
  final data = profile.dataOrNull;
  return (data == null || !data.isComplete) ? AccountStatus.needsProfile : AccountStatus.ready;
});
