import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// Read/write access to this app's own hidden folder in the user's Google Drive,
/// and nothing else. A "non-sensitive" Google scope: no access to the user's files.
const kDriveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

@immutable
class GoogleUser {
  const GoogleUser({required this.email, this.name, this.photoUrl, this.active = true});

  final String email;
  final String? name;

  /// The Google profile picture (Gmail avatar), when the account has one.
  final String? photoUrl;

  /// false = remembered from an earlier session but not confirmed yet this run
  /// (e.g. started offline). Backups retry the silent sign-in first.
  final bool active;

  String get initial {
    final source = (name?.trim().isNotEmpty ?? false) ? name!.trim() : email;
    return source.isEmpty ? '?' : String.fromCharCode(source.runes.first).toUpperCase();
  }
}

class AuthException implements Exception {
  const AuthException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Google sign-in for the Drive backup. There is no other account: sign-in is a
/// one-time step per phone, then [restore] silently brings it back on every start.
class GoogleAccountService {
  static bool _ready = false;

  /// True while Google's account picker is up: the app is in the background then,
  /// and must not install an update or pop a dialog over the sign-in.
  static bool signingIn = false;

  /// What went wrong, short enough for a message ("PlatformException: …").
  static String describe(Object e) {
    final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 110 ? text : '${text.substring(0, 110)}…';
  }
  GoogleSignInAccount? _account;

  static const _emailKey = 'account.email';
  static const _nameKey = 'account.name';
  static const _photoKey = 'account.photo';

  /// Call once from main(). No-op when this build has no Google client ID.
  static Future<void> initialize() async {
    if (!Env.canSignIn || _ready) return;
    await GoogleSignIn.instance.initialize(serverClientId: Env.googleServerClientId);
    _ready = true;
  }

  bool get available => _ready;

  /// Silent sign-in (no UI). Returns null when the user never signed in on this
  /// phone, signed out, or Google can't be reached right now.
  Future<GoogleUser?> restore() async {
    if (!_ready) return null;
    try {
      final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = attempt == null ? null : await attempt;
      if (account == null) return null;
      _account = account;
      return await _remember(account);
    } catch (_) {
      return null;
    }
  }

  /// The account remembered from an earlier session (for showing who is signed
  /// in while offline), without contacting Google.
  static Future<GoogleUser?> remembered() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey);
    return email == null ? null : GoogleUser(
            email: email, name: prefs.getString(_nameKey), photoUrl: prefs.getString(_photoKey), active: false);
  }

  /// Interactive: account picker, then the Drive-folder permission. Throws
  /// [AuthException]; `cancelled` is true when the user backed out.
  Future<GoogleUser> signIn() async {
    if (!_ready) throw const AuthException('Google sign-in is not set up in this build.');
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AuthException('Google sign-in is not available on this device.');
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      _account = account;
      await account.authorizationClient.authorizeScopes([kDriveAppDataScope]);
      return await _remember(account);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Sign-in cancelled.', cancelled: true);
      }
      throw AuthException(_googleHint(e));
    }
  }

  /// HTTP headers for Drive, or null when Drive access needs the user's OK
  /// again (then call [authorizeDrive] from a button tap).
  Future<Map<String, String>?> driveHeaders() async {
    final account = _account ?? (await restore() == null ? null : _account);
    if (account == null) return null;
    try {
      return await account.authorizationClient.authorizationHeaders([kDriveAppDataScope]);
    } catch (_) {
      return null;
    }
  }

  /// Interactive Drive permission prompt (e.g. after the user revoked it).
  Future<void> authorizeDrive() async {
    final account = _account;
    if (account == null) throw const AuthException('Sign in first.');
    try {
      await account.authorizationClient.authorizeScopes([kDriveAppDataScope]);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Cancelled.', cancelled: true);
      }
      throw AuthException(_googleHint(e));
    }
  }

  /// Drive rejected a token (401): drop it from Google's cache so the next
  /// [driveHeaders] call fetches a fresh one.
  Future<void> invalidate(String bearerHeader) async {
    final token = bearerHeader.replaceFirst('Bearer ', '');
    try {
      await _account?.authorizationClient.clearAuthorizationToken(accessToken: token);
    } catch (_) {}
  }

  /// Signs out of Google in this app. The phone's data stays.
  Future<void> signOut() async {
    _account = null;
    if (_ready) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_photoKey);
  }

  Future<GoogleUser> _remember(GoogleSignInAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, account.email);
    final name = account.displayName;
    if (name != null) await prefs.setString(_nameKey, name);
    final photo = account.photoUrl;
    if (photo != null) {
      await prefs.setString(_photoKey, photo);
    } else {
      await prefs.remove(_photoKey);
    }
    return GoogleUser(email: account.email, name: name, photoUrl: photo);
  }

  static String _googleHint(GoogleSignInException e) {
    final text = '${e.code.name} ${e.description ?? ''}';
    // The usual cause on Android: no Android OAuth client for this package + signing SHA-1.
    if (text.contains('configuration') ||
        text.contains('clientConfiguration') ||
        text.contains('developer')) {
      return 'Google sign-in is misconfigured: the Google Cloud project needs an Android client for this '
          'app\'s package name and signing SHA-1.';
    }
    return 'Google sign-in failed (${e.code.name}).';
  }
}
