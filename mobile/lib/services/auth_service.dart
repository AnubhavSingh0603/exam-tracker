import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';

@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.userId,
    required this.email,
    this.name,
    this.profileId,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String userId;
  final String email;
  final String? name;
  final String? profileId;

  bool get accessValid => accessExpiresAt.isAfter(DateTime.now().add(const Duration(seconds: 60)));
  bool get refreshValid => refreshExpiresAt.isAfter(DateTime.now());

  /// Parses the backend's `TokenOut`.
  factory AuthSession.fromTokenResponse(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>;
    return AuthSession(
      accessToken: j['access_token'] as String,
      accessExpiresAt: DateTime.parse(j['access_expires_at'] as String),
      refreshToken: j['refresh_token'] as String,
      refreshExpiresAt: DateTime.parse(j['refresh_expires_at'] as String),
      userId: user['id'] as String,
      email: user['email'] as String,
      name: user['name'] as String?,
      profileId: user['profile_id'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'access_expires_at': accessExpiresAt.toIso8601String(),
        'refresh_token': refreshToken,
        'refresh_expires_at': refreshExpiresAt.toIso8601String(),
        'user': {'id': userId, 'email': email, 'name': name, 'profile_id': profileId},
      };
}

class AuthException implements Exception {
  const AuthException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Google sign-in -> our backend's access/refresh tokens.
///
/// The refresh token is long-lived and rotates on every use, so it lives in the
/// Android Keystore (flutter_secure_storage), never in SQLite or SharedPreferences.
class AuthService {
  AuthService({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
        _client = client ?? http.Client();

  final FlutterSecureStorage _storage;
  final http.Client _client;

  static const _key = 'auth.session';
  static const _timeout = Duration(seconds: 15);
  static bool _googleReady = false;

  /// Call once from main(). No-op when Google sign-in isn't configured for this build.
  static Future<void> initialize() async {
    if (!Env.canSignIn || _googleReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: Env.googleServerClientId);
    _googleReady = true;
  }

  Future<AuthSession?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final session = AuthSession.fromTokenResponse(jsonDecode(raw) as Map<String, dynamic>);
      return session.refreshValid ? session : null;
    } catch (_) {
      return null; // corrupt or from an older format: just sign in again
    }
  }

  Future<void> _save(AuthSession s) => _storage.write(key: _key, value: jsonEncode(s.toJson()));

  Future<AuthSession> signInWithGoogle() async {
    if (!_googleReady) {
      throw const AuthException('Google sign-in is not configured in this build.');
    }
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AuthException('Google sign-in is not available on this device.');
    }
    final String? idToken;
    try {
      final account = await GoogleSignIn.instance.authenticate();
      idToken = account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Sign-in cancelled.', cancelled: true);
      }
      throw AuthException(_googleHint(e));
    }
    if (idToken == null) throw const AuthException('Google did not return an ID token.');

    final res = await _post('/api/v1/auth/google', {'id_token': idToken});
    if (res.statusCode != 200) {
      throw AuthException(_detail(res) ?? 'The server rejected the sign-in (${res.statusCode}).');
    }
    final session = AuthSession.fromTokenResponse(_json(res));
    await _save(session);
    return session;
  }

  /// Rotates the refresh token. Returns null when the session is gone (sign in again).
  Future<AuthSession?> refresh(AuthSession current) async {
    final res = await _post('/api/v1/auth/refresh', {'refresh_token': current.refreshToken});
    if (res.statusCode == 401) {
      await _storage.delete(key: _key);
      return null;
    }
    if (res.statusCode != 200) {
      throw AuthException('Could not refresh the session (${res.statusCode}).');
    }
    final session = AuthSession.fromTokenResponse(_json(res));
    await _save(session);
    return session;
  }

  Future<void> signOut(AuthSession? current) async {
    if (current != null) {
      try {
        await _post('/api/v1/auth/logout', {'refresh_token': current.refreshToken});
      } catch (_) {/* offline: the token simply expires */}
    }
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _storage.delete(key: _key);
  }

  /// Keeps the cached profile id in sync after the profile is first created.
  Future<AuthSession> withProfileId(AuthSession s, String profileId) async {
    final updated = AuthSession(
      accessToken: s.accessToken,
      accessExpiresAt: s.accessExpiresAt,
      refreshToken: s.refreshToken,
      refreshExpiresAt: s.refreshExpiresAt,
      userId: s.userId,
      email: s.email,
      name: s.name,
      profileId: profileId,
    );
    await _save(updated);
    return updated;
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) => _client
      .post(
        Uri.parse('${Env.apiBaseUrl}$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(_timeout);

  static Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  static String? _detail(http.Response r) {
    try {
      final d = _json(r)['detail'];
      return d is String ? d : null;
    } catch (_) {
      return null;
    }
  }

  static String _googleHint(GoogleSignInException e) {
    final text = '${e.code.name} ${e.description ?? ''}';
    // The usual cause on Android: no Android OAuth client for this package + signing SHA-1.
    if (text.contains('configuration') || text.contains('clientConfiguration') || text.contains('developer')) {
      return 'Google sign-in is misconfigured: add an Android OAuth client for this app\'s '
          'package name and signing SHA-1 (see mobile/TESTING.md).';
    }
    return 'Google sign-in failed (${e.code.name}).';
  }

  void close() => _client.close();
}
