import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Portal passwords/PINs, encrypted by the Android Keystore. Works offline.
/// Also holds the optional PIN that locks saved IDs (only a salted hash of it).
class SecretStore {
  SecretStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;

  static String _key(String appId) => 'vault.password.$appId';

  Future<String?> readPassword(String appId) => _storage.read(key: _key(appId));

  Future<bool> hasPassword(String appId) => _storage.containsKey(key: _key(appId));

  Future<void> writePassword(String appId, String value) =>
      _storage.write(key: _key(appId), value: value);

  Future<void> deletePassword(String appId) => _storage.delete(key: _key(appId));

  // --- Optional PIN lock ------------------------------------------------------

  static const _pinHash = 'pin.hash';
  static const _pinSalt = 'pin.salt';

  Future<bool> hasPin() => _storage.containsKey(key: _pinHash);

  Future<void> setPin(String pin) async {
    final random = Random.secure();
    final salt = base64Encode([for (var i = 0; i < 16; i++) random.nextInt(256)]);
    await _storage.write(key: _pinSalt, value: salt);
    await _storage.write(key: _pinHash, value: _hash(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _pinSalt);
    final hash = await _storage.read(key: _pinHash);
    return salt != null && hash != null && _hash(pin, salt) == hash;
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _pinHash);
    await _storage.delete(key: _pinSalt);
  }

  /// Salted and repeated, so the stored value doesn't give the PIN away at a glance.
  /// (Four digits can't be made strong; the Keystore encryption around it is what
  /// keeps it from other apps.)
  static String _hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }
}
