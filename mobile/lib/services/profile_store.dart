import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// The eligibility profile, kept on the phone (matching runs here), stamped with
/// when it was saved so the Drive backup can tell which copy is newer. Date of
/// birth, category and PwBD status are personal, so it lives in the Keystore-backed
/// encrypted storage; a copy from before that is moved over and deleted.
abstract final class ProfileStore {
  static const _key = 'profile.cache';
  static const _secure = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static Future<String?> _raw() async {
    final stored = await _secure.read(key: _key);
    if (stored != null) return stored;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_key); // saved in plain settings before 0.10.1
    if (legacy != null) {
      await _secure.write(key: _key, value: legacy);
      await prefs.remove(_key);
    }
    return legacy;
  }

  /// The profile and when it was saved (null for a profile saved before backups existed).
  static Future<(UserProfileData?, DateTime?)> readStamped() async {
    try {
      final raw = await _raw();
      if (raw == null) return (null, null);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['profile'] is Map<String, dynamic>) {
        return (
          UserProfileData.fromJson(json['profile'] as Map<String, dynamic>),
          DateTime.tryParse(json['saved_at'] as String? ?? ''),
        );
      }
      return (UserProfileData.fromJson(json), null); // older format: the bare profile
    } catch (_) {
      return (null, null); // corrupt: the profile sheet asks again
    }
  }

  static Future<UserProfileData?> read() async => (await readStamped()).$1;

  static Future<void> write(UserProfileData data, {DateTime? savedAt}) async {
    await _secure.write(
      key: _key,
      value: jsonEncode(
          {'profile': data.toJson(), 'saved_at': (savedAt ?? DateTime.now()).toUtc().toIso8601String()}),
    );
    await (await SharedPreferences.getInstance()).remove(_key); // no plain copy left behind
  }

  static Future<void> clear() async {
    await _secure.delete(key: _key);
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
