import 'dart:async';
import 'dart:convert';

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
    await ProfileCache.clear();
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

/// Last saved profile on this phone, so the form and account state work offline,
/// plus a flag for a save that hasn't reached the server yet.
abstract final class ProfileCache {
  static const _key = 'profile.cache';
  static const _pendingKey = 'profile.pendingSync';

  static Future<UserProfileData?> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? null : UserProfileData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt or from an older app version: the server copy wins
    }
  }

  static Future<void> write(UserProfileData data, {required bool pendingSync}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
    await prefs.setBool(_pendingKey, pendingSync);
  }

  static Future<bool> hasPendingSync() async =>
      (await SharedPreferences.getInstance()).getBool(_pendingKey) ?? false;

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_pendingKey);
  }
}

/// The eligibility profile lives on this phone (matching runs here too).
/// Step 3 adds a Google Drive backup so it survives a reinstall.
class ProfileNotifier extends AsyncNotifier<UserProfileData?> {
  @override
  Future<UserProfileData?> build() => ProfileCache.read();

  /// Saves on the phone; the feed recomputes from it. Returns true (kept for
  /// callers that used to wait for a server sync).
  Future<bool> save(UserProfileData data) async {
    await ProfileCache.write(data, pendingSync: false);
    state = AsyncData(data);
    ref.invalidate(feedProvider);
    return true;
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
  // No account needed: jobs come from the public data feed, matching runs on the phone.
  final profile = ref.watch(profileProvider);
  if (profile.isLoading && !profile.hasValue) return AccountStatus.loading;
  final data = profile.dataOrNull;
  return (data == null || !data.isComplete) ? AccountStatus.needsProfile : AccountStatus.ready;
});
