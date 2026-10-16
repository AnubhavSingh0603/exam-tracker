import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AES-256-GCM for personal data kept in the app's database (Reg/Roll numbers,
/// notes). The key is random, made on this phone, and lives in the Keystore-backed
/// secure storage next to the portal passwords, never in the database itself.
class LocalCipher {
  LocalCipher(List<int> key) : _key = SecretKey(key);

  final SecretKey _key;
  static final _aes = AesGcm.with256bits();

  static const _keyName = 'local.data.key';
  static const _prefix = 'v1:';

  static Future<LocalCipher>? _shared;

  /// The phone's key, made the first time. Only the app (foreground) calls this, so
  /// the background task can never race it into making a second key.
  static Future<LocalCipher> shared() => _shared ??= load();

  static Future<LocalCipher> load([FlutterSecureStorage? storage]) async {
    final store =
        storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
    final saved = await store.read(key: _keyName);
    if (saved != null) return LocalCipher(base64Decode(saved));
    final random = Random.secure();
    final key = [for (var i = 0; i < 32; i++) random.nextInt(256)];
    await store.write(key: _keyName, value: base64Encode(key));
    return LocalCipher(key);
  }

  static bool isEncrypted(String value) => value.startsWith(_prefix);

  Future<String> encrypt(String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: _key);
    return '$_prefix${base64Encode(box.concatenation())}';
  }

  /// Plain text from before encryption comes back as it is (and is encrypted at
  /// the next start, see DatabaseService.encryptStoredIds).
  Future<String> decrypt(String value) async {
    if (!isEncrypted(value)) return value;
    final box = SecretBox.fromConcatenation(
      base64Decode(value.substring(_prefix.length)),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: _key));
  }

  Future<String?> encryptOrNull(Object? plain) async =>
      plain is String && plain.isNotEmpty && !isEncrypted(plain) ? encrypt(plain) : plain as String?;

  /// Null when it can't be read: if Android ever loses the key (it happens on some
  /// phones after a lock-screen reset), the numbers read as empty instead of
  /// breaking the app, and the Drive backup brings them back at the next sync.
  Future<String?> decryptOrNull(Object? value) async {
    if (value is! String) return null;
    try {
      return await decrypt(value);
    } catch (_) {
      return null;
    }
  }
}
