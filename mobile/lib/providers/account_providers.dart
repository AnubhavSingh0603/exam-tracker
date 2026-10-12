import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'providers.dart';

// -----------------------------------------------------------------------------
// Auth (Google sign-in -> backend tokens)
// -----------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService();
  ref.onDispose(service.close);
  return service;
});

class AuthNotifier extends AsyncNotifier<AuthSession?> {
  Future<AuthSession?>? _refreshing;

  AuthService get _service => ref.read(authServiceProvider);

  @override
  Future<AuthSession?> build() async => Env.canSignIn ? _service.load() : null;

  /// Throws [AuthException]; `cancelled` is true when the user backed out.
  Future<void> signIn() async {
    final session = await _service.signInWithGoogle();
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    await _service.signOut(state.dataOrNull);
    await ref.read(databaseProvider).clearFeedCache(); // don't show the last user's jobs
    state = const AsyncData(null);
  }

  /// Valid access token or null. Concurrent callers share one refresh request,
  /// which matters because each refresh rotates (invalidates) the refresh token.
  Future<String?> accessToken({bool forceRefresh = false}) async {
    final session = state.dataOrNull ?? await future;
    if (session == null) return null;
    if (!forceRefresh && session.accessValid) return session.accessToken;
    _refreshing ??= _refresh(session);
    try {
      return (await _refreshing)?.accessToken;
    } finally {
      _refreshing = null;
    }
  }

  Future<AuthSession?> _refresh(AuthSession session) async {
    try {
      final next = await _service.refresh(session);
      state = AsyncData(next); // null => signed out (refresh token revoked/expired)
      return next;
    } catch (_) {
      return null; // offline: keep the session, the next call retries
    }
  }

  Future<void> rememberProfileId(String profileId) async {
    final session = state.dataOrNull;
    if (session != null && session.profileId != profileId) {
      state = AsyncData(await _service.withProfileId(session, profileId));
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthSession?>(AuthNotifier.new);

// -----------------------------------------------------------------------------
// Dev API-key mode: which profile id the feed uses
// -----------------------------------------------------------------------------

class DevProfileIdNotifier extends AsyncNotifier<String?> {
  static const _key = 'dev.profileId';

  @override
  Future<String?> build() async {
    if (!Env.devKeyMode) return null;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;
    return Env.presetUserId.isEmpty ? null : Env.presetUserId;
  }

  Future<void> set(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
    state = AsyncData(id);
  }
}

final devProfileIdProvider = AsyncNotifierProvider<DevProfileIdNotifier, String?>(DevProfileIdNotifier.new);

// -----------------------------------------------------------------------------
// Eligibility profile
// -----------------------------------------------------------------------------

class ProfileNotifier extends AsyncNotifier<UserProfileData?> {
  @override
  Future<UserProfileData?> build() async {
    final api = ref.watch(apiClientProvider);
    if (api == null) return null;
    if (api.usesApiKey) {
      final id = await ref.watch(devProfileIdProvider.future);
      if (id == null) return null;
      final json = await api.getProfileById(id);
      return json == null ? null : UserProfileData.fromJson(json);
    }
    // Rebuild only when the *user* changes, not on every token refresh.
    final userId = ref.watch(authProvider.select((a) => a.dataOrNull?.userId));
    if (userId == null) return null;
    final json = await api.getMyProfile();
    return json == null ? null : UserProfileData.fromJson(json);
  }

  /// Saves to the backend, then refreshes the feed with the new eligibility.
  Future<void> save(UserProfileData data) async {
    final api = ref.read(apiClientProvider);
    if (api == null) throw StateError('No backend configured');
    if (api.usesApiKey) {
      // Admin endpoints can only create, so dev mode stores the new profile id.
      final created = await api.createProfile(data.toJson());
      state = AsyncData(data);
      await ref.read(devProfileIdProvider.notifier).set(created['id'] as String);
    } else {
      final saved = await api.saveMyProfile(data.toJson());
      state = AsyncData(data);
      await ref.read(authProvider.notifier).rememberProfileId(saved['id'] as String);
    }
    ref.invalidate(feedProvider);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfileData?>(ProfileNotifier.new);

enum AccountStatus {
  offline, // no backend in this build, or sign-in not configured
  signedOut,
  loading,
  unavailable, // backend unreachable right now; don't nag
  needsProfile,
  ready,
}

final accountStatusProvider = Provider<AccountStatus>((ref) {
  if (!Env.hasBackend) return AccountStatus.offline;
  if (!Env.devKeyMode) {
    if (!Env.canSignIn) return AccountStatus.offline;
    final auth = ref.watch(authProvider);
    if (auth.isLoading && !auth.hasValue) return AccountStatus.loading;
    if (auth.dataOrNull == null) return AccountStatus.signedOut;
  }
  final profile = ref.watch(profileProvider);
  if (profile.isLoading && !profile.hasValue) return AccountStatus.loading;
  if (profile.hasError && !profile.hasValue) return AccountStatus.unavailable;
  final data = profile.dataOrNull;
  return (data == null || !data.isComplete) ? AccountStatus.needsProfile : AccountStatus.ready;
});
