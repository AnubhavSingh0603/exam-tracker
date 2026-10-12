import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Portal passwords/PINs, encrypted by the Android Keystore. Works offline.
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
}
