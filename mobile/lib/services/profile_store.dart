import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// The eligibility profile, kept on the phone (matching runs here), stamped with
/// when it was saved so the Drive backup can tell which copy is newer.
abstract final class ProfileStore {
  static const _key = 'profile.cache';

  /// The profile and when it was saved (null for a profile saved before backups existed).
  static Future<(UserProfileData?, DateTime?)> readStamped() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(
          {'profile': data.toJson(), 'saved_at': (savedAt ?? DateTime.now()).toUtc().toIso8601String()}),
    );
  }

  static Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}
